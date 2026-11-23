import AppIntents
import BadKit
import CoreLocation
import SwiftUI
import WidgetKit

// MARK: - Configuration

enum WidgetTravelMode: String, AppEnum {
    case app, walking, cycling, transit, driving

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Verkehrsmittel"
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

    @Parameter(title: "Verkehrsmittel", default: .app)
    var travelMode: WidgetTravelMode

    @Parameter(title: "Training (min)", description: "Leer = wie in der App", inclusiveRange: (15, 240))
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

        let planner = SwimPlanner(preferences: prefs)
        let start = Date()
        return (0..<count).map { i in
            let date = start.addingTimeInterval(TimeInterval(i * 5 * 60))
            let plans = planner.plans(for: pools, now: date) { table.travel(to: $0) }
            return SwimEntry(date: date, plans: plans, mode: prefs.travelMode, trainingMinutes: prefs.trainingMinutes,
                             dataDate: feed?.generatedAt, usesLocation: usesLocation)
        }
    }

    private func currentOrigin() -> ((lat: Double, lon: Double), Bool) {
        let manager = CLLocationManager()
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryInline, .accessoryCircular])
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
        case .systemLarge: list(limit: 6)
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        case .accessoryCircular: circular
        default: small
        }
    }

    private func url(_ plan: SwimPlan) -> URL { URL(string: "berlinswim://pool/\(plan.pool.id)")! }

    @ViewBuilder
    private var small: some View {
        if let plan = top.first {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: entry.mode.symbol)
                    Text(plan.travelText)
                    Spacer()
                    Image(systemName: plan.status.symbol).foregroundStyle(plan.status.color)
                }
                .font(.caption2.weight(.semibold))
                Spacer(minLength: 0)
                Text(plan.pool.shortName)
                    .font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                Text(plan.headline)
                    .font(.system(size: 34, weight: .light)).lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text(plan.status == .later ? plan.status.title : "Badeschluss \(plan.swimEnd.map(Fmt.clock) ?? "–")")
                    .font(.caption2).opacity(0.85)
            }
            .foregroundStyle(.white)
            .widgetURL(url(plan))
        } else {
            empty
        }
    }

    private func list(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 8 : 5) {
            HStack {
                Label("\(Fmt.minutes(entry.trainingMinutes)) · \(entry.mode.title)", systemImage: "figure.pool.swim")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button(intent: RefreshIntent()) {
                    Image(systemName: "arrow.clockwise").font(.caption)
                }
                .buttonStyle(.plain)
            }
            .opacity(0.9)
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
            if family == .systemLarge, let d = entry.dataDate {
                Text("Stand \(Fmt.weekdayClock(d, relativeTo: entry.date)) · berlinerbaeder.de")
                    .font(.caption2).opacity(0.6)
            }
        }
        .foregroundStyle(.white)
    }

    private func row(_ plan: SwimPlan) -> some View {
        HStack(spacing: 8) {
            Circle().fill(plan.status.color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(plan.pool.shortName).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(plan.travelText) · bis \(plan.swimEnd.map(Fmt.clock) ?? "–")"
                     + (plan.pool.warnings.isEmpty ? "" : " · ⚠︎"))
                    .font(.caption2).opacity(0.85).lineLimit(1)
            }
            Spacer()
            Text(plan.headline).font(.system(.title3, weight: .light)).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder
    private var rectangular: some View {
        if let plan = top.first {
            VStack(alignment: .leading) {
                Label(plan.pool.shortName, systemImage: "figure.pool.swim").font(.headline).lineLimit(1)
                Text("\(plan.headline) · \(plan.travelText)").lineLimit(1)
                Text("Badeschluss \(plan.swimEnd.map(Fmt.clock) ?? "–")").lineLimit(1).opacity(0.8)
            }
            .widgetURL(url(plan))
        } else {
            Label("Heute kein Bad mehr", systemImage: "moon.zzz")
        }
    }

    @ViewBuilder
    private var inline: some View {
        if let plan = top.first {
            Label("\(plan.pool.shortName) · \(plan.headline)", systemImage: "figure.pool.swim")
        } else {
            Label("Kein Bad mehr heute", systemImage: "figure.pool.swim")
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "figure.pool.swim").font(.caption)
                Text(top.first.map { "\($0.usableMinutes)" } ?? "–").font(.headline).monospacedDigit()
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "moon.zzz.fill").font(.title2)
            Text(entry.plans.isEmpty ? "Keine Daten" : "Heute kein Bad mehr erreichbar")
                .font(.subheadline.weight(.semibold))
            if let next = entry.plans.compactMap({ p in p.nextWindow.map { w in (p, w) } })
                .min(by: { $0.1.start < $1.1.start }) {
                Text("\(next.0.pool.shortName) \(Fmt.weekdayClock(next.1.start, relativeTo: entry.date))")
                    .font(.caption).opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
