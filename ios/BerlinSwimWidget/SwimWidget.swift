import AppIntents
import BadKit
import CoreLocation
import SwiftUI
import WidgetKit

// MARK: - Configuration

enum WidgetTravelMode: String, AppEnum {
    case app, walking, cycling, transit, driving

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Anreise"
    static let caseDisplayRepresentations: [WidgetTravelMode: DisplayRepresentation] = [
        .app: "Wie in der App",
        .walking: "Zu Fuß",
        .cycling: "Fahrrad",
        .transit: "ÖPNV",
        .driving: "Auto",
    ]

    var mode: TravelMode? { TravelMode(rawValue: rawValue) }
}

struct SwimWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Schwimmen gehen"
    static let description = IntentDescription("Welche Bäder du jetzt noch erreichst – mit genug Zeit fürs Training.")

    @Parameter(title: "Anreise", default: .app)
    var travelMode: WidgetTravelMode

    @Parameter(title: "Schwimmdauer (min)", description: "Leer = wie in der App", inclusiveRange: (15, 240))
    var trainingMinutes: Int?

    @Parameter(title: "Nur 50-m-Becken", default: false)
    var only50m: Bool

    @Parameter(title: "Nur Favoriten", default: false)
    var onlyFavorites: Bool
}

struct RefreshIntent: AppIntent {
    static let title: LocalizedStringResource = "Aktualisieren"
    func perform() async throws -> some IntentResult {
        _ = try? await PoolStore.shared.refresh(maxAge: 0)
        return .result()
    }
}

// MARK: - Timeline

struct SwimEntry: TimelineEntry {
    let date: Date
    let plans: [SwimPlan]
    let mode: TravelMode
    let trainingMinutes: Int
    let dataDate: Date?
    let usesLocation: Bool
    /// Minimum lane length the widget filters on (shown in the header).
    var lane: Int? = nil

    static let placeholder = SwimEntry(date: .now, plans: [], mode: .transit, trainingMinutes: 60,
                                       dataDate: nil, usesLocation: true)
}

struct SwimProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SwimEntry { .placeholder }

    func snapshot(for configuration: SwimWidgetIntent, in context: Context) async -> SwimEntry {
        await entries(for: configuration, count: 1).first ?? .placeholder
    }

    func timeline(for configuration: SwimWidgetIntent, in context: Context) async -> Timeline<SwimEntry> {
        // Every 5 minutes for 1.5 h so "noch X min" counts down; then reload.
        let list = await entries(for: configuration, count: 18)
        return Timeline(entries: list, policy: .after(Date().addingTimeInterval(30 * 60)))
    }

    private func entries(for config: SwimWidgetIntent, count: Int) async -> [SwimEntry] {
        var feed = try? await PoolStore.shared.refresh(maxAge: 25 * 60)
        if feed == nil { feed = await PoolStore.shared.cached() }
        var prefs = SharedState.loadPreferences()
        // The widget always plans with a training length and travel mode (its own settings or the app's values).
        prefs.travelSet = true
        prefs.trainingSet = true
        if let m = config.travelMode.mode { prefs.travelMode = m }
        if let t = config.trainingMinutes { prefs.trainingMinutes = t }
        if config.only50m { prefs.minLaneLength = 50 }

        let (origin, usesLocation) = currentOrigin()
        var routed: [String: TimeInterval] = [:]
        if let o = SharedState.travelTimesOrigin(),
           Geo.distance(lat1: o.lat, lon1: o.lon, lat2: origin.lat, lon2: origin.lon) < 500 {
            routed = SharedState.savedTravelTimes()
        }
        let table = TravelTimeTable(origin: origin, mode: prefs.travelMode, routed: routed)
        var pools = feed?.pools ?? []
        if config.onlyFavorites { pools = pools.filter { prefs.favorites.contains($0.id) } }

        let occupancy = await OccupancyStore.shared.current()
        let lane = prefs.minLaneLength
        let planner = SwimPlanner(preferences: prefs)
        let start = Date()
        return (0..<count).map { i in
            let date = start.addingTimeInterval(TimeInterval(i * 5 * 60))
            // Live occupancy only describes "now"; don't carry it into later entries.
            let plans = planner.plans(for: pools, now: date, occupancy: i < 3 ? occupancy : [:],
                                      travelKnown: usesLocation) { table.travel(to: $0) }
            return SwimEntry(date: date, plans: plans, mode: prefs.travelMode, trainingMinutes: prefs.trainingMinutes,
                             dataDate: feed?.generatedAt, usesLocation: usesLocation, lane: lane)
        }
    }

    private func currentOrigin() -> ((lat: Double, lon: Double), Bool) {
        let manager = CLLocationManager()
        // Denied: no travel times at all (even if an old position is stored).
        if [.denied, .restricted].contains(manager.authorizationStatus) { return (Geo.berlinCenter, false) }
        if manager.isAuthorizedForWidgetUpdates, let c = manager.location?.coordinate {
            return ((c.latitude, c.longitude), true)
        }
        if let l = SharedState.lastLocation() { return ((l.lat, l.lon), true) }
        return (Geo.berlinCenter, false)
    }
}

// MARK: - Widget

struct SwimWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SwimWidget", intent: SwimWidgetIntent.self, provider: SwimProvider()) { entry in
            SwimWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WaterBackground(status: entry.plans.first?.status, date: entry.date)
                }
        }
        .configurationDisplayName("Schwimmen gehen")
        .description("Bäder, die jetzt offen und erreichbar sind – mit Restzeit fürs Training.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct BerlinSwimWidgets: WidgetBundle {
    var body: some Widget { SwimWidget() }
}

// MARK: - Views

struct SwimWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SwimEntry

    private var top: [SwimPlan] { entry.plans.filter { $0.status <= .tight } }

    var body: some View {
        switch family {
        case .systemSmall: small
        case .systemMedium: list(limit: 3)
        case .systemLarge: largeList
        default: small
        }
    }

    /// "45 min Training · Anreise mit ÖPNV · 50 m"
    private var headerText: String {
        [String(localized: "\(Fmt.minutes(entry.trainingMinutes)) Training"),
         entry.usesLocation ? entry.mode.arrivalText : nil, entry.lane.map { "\($0) m" }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// Small widget: just the training length, e.g. "45 min Training".
    private var smallHeaderText: String {
        String(localized: "\(Fmt.minutes(entry.trainingMinutes)) Training")
    }

    /// Travel time, lane length (medium/large only) and, if known, occupancy.
    private func facts(_ plan: SwimPlan, lane: Bool = false) -> some View {
        HStack(spacing: 4) {
            if plan.travelKnown { FactChip(text: plan.travelText, symbol: TravelMode.travelSymbol, compact: true) }
            if lane, let l = plan.window?.laneLength ?? plan.pool.laneLength {
                FactChip(text: "\(l) m", compact: true)
            }
            if let o = plan.occupancy {
                FactChip(text: o.shortTitle, symbol: "person.2.fill", tint: o.color, compact: true)
            }
        }
    }

    private func detail(_ plan: SwimPlan) -> String { plan.statusDetail ?? plan.status.title }

    private func timeLines(_ plan: SwimPlan) -> (caption: String, value: String) {
        plan.timeLines(relativeTo: entry.date)
    }

    private func url(_ plan: SwimPlan) -> URL { URL(string: "berlinswim://pool/\(plan.pool.id)")! }

    @ViewBuilder
    private var small: some View {
        if let plan = top.first {
            // Same type scale as the rows of the medium/large widget.
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "figure.pool.swim")
                    Text(smallHeaderText).lineLimit(1)
                }
                .font(.caption.weight(.semibold))
                .opacity(0.9)
                Spacer(minLength: 0)
                Text(plan.pool.compactName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)

                let time = timeLines(plan)
                Text(time.caption)
                    .font(.caption2.weight(.medium)).opacity(0.85)
                Text(time.value)
                    // Weight as a separate modifier: WidgetKit drops `weight:` inside Font.system(...)
                    .font(.headline.monospacedDigit()).fontWeight(.bold)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                facts(plan)
            }
            .foregroundStyle(.white)
            .widgetURL(url(plan))
        } else {
            empty
        }
    }

    /// As many rows as fit the widget's height (it differs per device), spread evenly so no empty band is left.
    /// ViewThatFits takes the first candidate whose minimum height fits; its spacers then share the free space.
    private var largeList: some View {
        ViewThatFits(in: .vertical) {
            spreadList(limit: 7)
            spreadList(limit: 6)
            spreadList(limit: 5)
            spreadList(limit: 4)
            spreadList(limit: 3)
        }
    }

    private func spreadList(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            listHeader
            if top.isEmpty {
                Spacer()
                empty
                Spacer()
            } else {
                ForEach(top.prefix(limit)) { plan in
                    Spacer(minLength: 8).frame(maxHeight: 30)
                    Link(destination: url(plan)) { row(plan) }
                }
                Spacer(minLength: 8)
            }
            if let d = entry.dataDate {
                Text("Quelle: berlinerbaeder.de · Stand \(Fmt.weekdayClock(d, relativeTo: entry.date))")
                    .font(.caption2).opacity(0.6)
            }
        }
        .foregroundStyle(.white)
    }

    private var listHeader: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "figure.pool.swim")
                Text(headerText).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.caption.weight(.semibold))
            Spacer()
            Button(intent: RefreshIntent()) {
                Image(systemName: "arrow.clockwise").font(.caption)
            }
            .buttonStyle(.plain)
        }
        .opacity(0.9)
    }

    private func list(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            listHeader
            if top.isEmpty {
                Spacer()
                empty
                Spacer()
            } else {
                ForEach(top.prefix(limit)) { plan in
                    Link(destination: url(plan)) { row(plan) }
                }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
    }

    /// Two grid rows so left and right share a text baseline:
    /// name ⟷ "schwimmen bis", chips ⟷ "21:30".
    private func row(_ plan: SwimPlan) -> some View {
        let time = timeLines(plan)
        // Left column takes all remaining width (maxWidth: .infinity); the right column is only as
        // wide as its content (no maxWidth) and right-aligned via gridColumnAlignment.
        return Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 0) {
            GridRow(alignment: .firstTextBaseline) {
                Text(plan.pool.compactName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(time.caption)
                    .font(.caption2.weight(.medium)).opacity(0.85)
                    .lineLimit(1)
                    .gridColumnAlignment(.trailing)
            }
            GridRow(alignment: .lastTextBaseline) {
                facts(plan, lane: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(time.value)
                    .font(.headline.monospacedDigit()).fontWeight(.bold)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .fixedSize() // never truncate the time
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .center, spacing: 4) {
            Image(systemName: "moon.zzz.fill").font(.title2)
            Text(entry.plans.isEmpty ? "Keine Daten" : "Heute kein Bad mehr erreichbar")
                .font(.subheadline.weight(.semibold))
            if let next = entry.plans.compactMap({ p in p.nextWindow.map { w in (p, w) } })
                .min(by: { $0.1.start < $1.1.start }) {
                Text("\(next.0.pool.compactName) \(Fmt.weekdayClock(next.1.start, relativeTo: entry.date))")
                    .font(.caption).opacity(0.85)
            }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Previews

#if DEBUG
extension SwimEntry {
    /// Entry from the bundled seed at a fixed time (see `PreviewData`).
    static func preview(hour: Int = 17, minute: Int = 30, lane: Int? = nil, training: Int = 45,
                        location: Bool = true) -> SwimEntry {
        var prefs = SwimPreferences()
        prefs.trainingMinutes = training
        prefs.minLaneLength = lane
        let now = PreviewData.now(hour: hour, minute: minute)
        return SwimEntry(date: now, plans: PreviewData.plans(preferences: prefs, now: now, location: location),
                         mode: prefs.travelMode, trainingMinutes: training, dataDate: PreviewData.feed?.generatedAt,
                         usesLocation: location, lane: lane)
    }
}

// Timeline steps (use the arrows under the canvas):
// 17:30 normal · 19:45 schließt bald ("noch …") · 20:40 knapp ("nur …") · 22:30 alles zu (Leerzustand)

#Preview("Klein", as: .systemSmall) {
    SwimWidget()
} timeline: {
    SwimEntry.preview()
    SwimEntry.preview(hour: 19, minute: 45)
    SwimEntry.preview(hour: 20, minute: 40)
    SwimEntry.preview(hour: 22, minute: 30)
}

#Preview("Mittel", as: .systemMedium) {
    SwimWidget()
} timeline: {
    SwimEntry.preview()
    SwimEntry.preview(location: false)
    SwimEntry.preview(lane: 50)
    SwimEntry.preview(hour: 19, minute: 45)
    SwimEntry.preview(hour: 20, minute: 40)
    SwimEntry.preview(hour: 22, minute: 30)
}

#Preview("Groß", as: .systemLarge) {
    SwimWidget()
} timeline: {
    SwimEntry.preview()
    SwimEntry.preview(hour: 7)
    SwimEntry.preview(hour: 19, minute: 45)
    SwimEntry.preview(hour: 20, minute: 40)
    SwimEntry.preview(hour: 22, minute: 30)
}

#endif
