import BadKit
import SwiftUI

/// Weather-app style list: a hero for the best option, then one card per pool.
struct PoolListScreen: View {
    @Environment(AppModel.self) private var model
    @State private var showAll = false

    private var favorites: [SwimPlan] { model.plans.filter { model.isFavorite($0.pool) } }
    private var reachable: [SwimPlan] {
        model.plans.filter { !model.isFavorite($0.pool) && $0.status <= .tight }
    }
    private var others: [SwimPlan] {
        model.plans.filter { !model.isFavorite($0.pool) && $0.status > .tight }
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.poolPath) {
            ScrollView {
                LazyVStack(spacing: 14) {
                    header
                    FilterBar()
                    if let error = model.errorMessage {
                        Label(error, systemImage: "wifi.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(10)
                            .glassEffect(.regular, in: .capsule)
                    }
                    section("Favoriten", favorites)
                    section(model.travelKnown ? "Erreichbar" : "Jetzt offen", reachable)
                    if noneLeftToday { noneLeftTodayView }
                    if !others.isEmpty {
                        DisclosureGroup(isExpanded: $showAll) {
                            LazyVStack(spacing: 12) { cards(others) }.padding(.top, 8)
                        } label: {
                            Text("Geschlossen")
                                .font(.headline).foregroundStyle(.white)
                        }
                        .tint(.white)
                        .padding(.horizontal, 4)
                    }
                    if model.plans.isEmpty { emptyState }
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: 720) // iPad: readable column instead of full-width cards
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(WaterBackground(status: model.plans.first?.status, date: model.now).ignoresSafeArea())
            .refreshable { await model.refresh(force: true) }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Pool.self) { pool in
                PoolPager(plans: model.plans.contains { $0.pool.id == pool.id } ? model.plans : [model.plan(for: pool)],
                          selected: pool)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("Schwimmen gehen?")
                .font(.largeTitle.bold()) // scales with Dynamic Type
            if model.travelKnown {
                Text("\(Fmt.minutes(model.preferences.trainingMinutes)) Training · \(model.preferences.travelMode.arrivalText)")
                    .font(.subheadline).opacity(0.85)
            } else {
                Text("\(Fmt.minutes(model.preferences.trainingMinutes)) Training · ohne Anreisezeit")
                    .font(.subheadline).opacity(0.85)
                Text("Standort aus – Bäder nach Öffnungszeit sortiert")
                    .font(.caption).opacity(0.9).padding(.top, 4)
                if model.locationDenied {
                    Button("Standort freigeben") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .padding(.top, 4)
                }
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.15), radius: 4)
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, _ plans: [SwimPlan]) -> some View {
        if !plans.isEmpty {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            cards(plans)
        }
    }

    private func cards(_ plans: [SwimPlan]) -> some View {
        ForEach(plans) { plan in
            NavigationLink(value: plan.pool) { PoolCard(plan: plan) }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(model.isFavorite(plan.pool) ? "Aus Favoriten entfernen" : "Zu Favoriten",
                           systemImage: model.isFavorite(plan.pool) ? "star.slash" : "star") {
                        model.toggleFavorite(plan.pool)
                    }
                    Button("Route", systemImage: "arrow.triangle.turn.up.right.diamond") {
                        RoutingService.openDirections(to: plan.pool, mode: model.preferences.travelMode)
                    }
                }
        }
    }

    /// Data is there, but nothing is reachable with enough time anymore today.
    private var noneLeftToday: Bool {
        !model.plans.isEmpty && !model.plans.contains { $0.status <= .tight }
    }

    /// The pool that opens next (any pool in the current filters).
    private var nextUp: (plan: SwimPlan, start: Date)? {
        model.plans.compactMap { p in p.nextWindow.map { (p, $0.start) } }
            .filter { $0.1 > model.now }
            .min { $0.1 < $1.1 }
    }

    /// Centered placeholder like the widget's: moon, message, and the next pool to open (tappable).
    private var noneLeftTodayView: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill")
                .font(.largeTitle)
                .imageScale(.large)
                .padding(.bottom, 4)
            Text(model.travelKnown ? "Heute kein Bad mehr erreichbar" : "Heute kein Bad mehr offen")
                .font(.title3.weight(.semibold))
            if let next = nextUp {
                // Plain text (still tappable): "Stadtbad … / öffnet morgen um 06:00 Uhr"
                NavigationLink(value: next.plan.pool) {
                    VStack(spacing: 2) {
                        Text(next.plan.pool.shortName)
                            .font(.subheadline.weight(.semibold))
                        Text(Fmt.opens(next.start, relativeTo: model.now))
                            .font(.subheadline)
                            .monospacedDigit()
                    }
                    .opacity(0.85)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyState: some View {
        ContentUnavailableView("Keine Bäder", systemImage: "drop",
                               description: Text("Lade Daten oder lockere die Filter."))
            .foregroundStyle(.white)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if let feed = model.feed {
                Text("Daten: berlinerbaeder.de · Stand \(Fmt.weekdayClock(feed.generatedAt))")
            }
            Text("Angaben ohne Gewähr – Hinweise vor Ort beachten.")
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.85))
        .padding(.top, 12)
    }
}

/// List card, like a city row in the Weather app: full name and status on top, facts as chips.
struct PoolCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let plan: SwimPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityHeader // very large text: name on top, time below, nothing truncated
            } else {
                standardHeader
            }
            chips
        }
        .foregroundStyle(.white)
        .padding(16)
        .background {
            WaterBackground(status: plan.status, date: model.now)
                .opacity(0.55)
                .clipShape(.rect(cornerRadius: 22))
        }
        .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }

    private var accessibilityHeader: some View {
        let time = plan.timeLines(relativeTo: model.now)
        return VStack(alignment: .leading, spacing: 4) {
            Text(plan.pool.shortName).font(.title3.weight(.semibold))
            Text([time.caption, time.value].filter { !$0.isEmpty }.joined(separator: " "))
                .font(.title3.monospacedDigit())
                .foregroundStyle(plan.status == .tight ? plan.status.color : .white)
        }
    }

    private var standardHeader: some View {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                // No favourite star: favourites have their own section on the home screen.
                Text(plan.pool.shortName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                // Same two lines as the widget: status icon + caption, value below.
                let time = plan.timeLines(relativeTo: model.now)
                // Each line sits in a box with the name's line height and baseline, so caption and
                // value share the baselines of the name's first and second line.
                VStack(alignment: .trailing, spacing: 0) {
                    nameLine {
                        HStack(spacing: 3) {
                            // Open/tight need no icon ("schwimmen bis", "Schwimmzeit", "nur noch" say it all).
                            if plan.status > .tight {
                                Image(systemName: plan.status.symbol)
                                    .font(.caption2)
                                    .foregroundStyle(.white, plan.status.color)
                            }
                            Text(time.caption)
                                // "nur noch" in the warning color
                                .foregroundStyle(plan.status == .tight ? plan.status.color : .white)
                        }
                        .font(.footnote.weight(.medium))
                    }
                    if !time.value.isEmpty {
                        nameLine {
                            Text(time.value)
                                .font(.title3.monospacedDigit()).fontWeight(.semibold)
                                .contentTransition(.numericText())
                        }
                    }
                }
                .fixedSize()
            }
    }

    private var chips: some View {
            FlowLayout(spacing: 6) {
                if plan.travelKnown { FactChip(text: plan.travelText, symbol: TravelMode.travelSymbol) }
                if let lane = plan.window?.laneLength ?? plan.pool.laneLength { FactChip(text: "\(lane) m") }
                if let t = plan.pool.waterTempC { FactChip(text: Fmt.temperature(t)) }
                if plan.status <= .tight, let o = plan.occupancy { FactChip(text: o.shortTitle, symbol: "person.2.fill", tint: o.color) }
                if let w = plan.womenOnlyText { FactChip(text: w, symbol: "figure.stand.dress") }
                if plan.window?.isWomenOnly == true { FactChip(text: String(localized: "nur Frauen"), symbol: "figure.stand.dress") }
                if !plan.pool.warnings.isEmpty, plan.status != .closed {
                    FactChip(text: String(localized: "Hinweis"), symbol: "exclamationmark.circle")
                }
            }
    }

    /// One line with exactly the height and baseline of a name line (title3 semibold).
    private func nameLine<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: Alignment(horizontal: .trailing, vertical: .firstTextBaseline)) {
            Text(verbatim: "Ag").font(.title3.weight(.semibold)).hidden()
            content()
        }
    }
}

struct FilterBar: View {
    @Environment(AppModel.self) private var model

    private let quick: [Feature] = [.sauna, .accessible]

    var body: some View {
        @Bindable var model = model
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if model.travelKnown { // travel mode is meaningless without a location
                        Menu {
                            Picker("Verkehrsmittel", selection: $model.preferences.travelMode) {
                                ForEach(TravelMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                            }
                        } label: {
                            pickerChip(model.preferences.travelMode.title, model.preferences.travelMode.symbol)
                        }
                    }
                    Menu {
                        Picker("Training", selection: $model.preferences.trainingMinutes) {
                            ForEach([30, 45, 60, 75, 90, 120], id: \.self) { Text(Fmt.minutes($0)).tag($0) }
                        }
                    } label: {
                        pickerChip(Fmt.minutes(model.preferences.trainingMinutes), "timer")
                    }
                    // 50 m = lane-length minimum (same setting the planner uses per pool area)
                    Button {
                        withAnimation(.snappy) {
                            model.preferences.minLaneLength = model.preferences.minLaneLength == 50 ? nil : 50
                        }
                    } label: { chip("50 m", "figure.pool.swim", active: model.preferences.minLaneLength == 50) }
                    .buttonStyle(.plain)
                    ForEach(quick) { f in
                        let on = model.preferences.requiredFeatures.contains(f)
                        Button {
                            withAnimation(.snappy) {
                                if on { model.preferences.requiredFeatures.remove(f) }
                                else { model.preferences.requiredFeatures.insert(f) }
                            }
                        } label: { chip(f.title, f.symbol, active: on) }
                        .buttonStyle(.plain)
                    }
                    Button {
                        withAnimation(.snappy) { model.preferences.avoidCrowded.toggle() }
                    } label: { chip(String(localized: "Nicht voll"), "person.2.slash", active: model.preferences.avoidCrowded) }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    /// Toggle chip: active = solid white with checkmark, inactive = clear glass.
    private func chip(_ title: String, _ symbol: String, active: Bool) -> some View {
        Label(title, systemImage: active ? "checkmark" : symbol)
            .font(.subheadline.weight(active ? .semibold : .medium))
            .foregroundStyle(active ? Color(red: 0.05, green: 0.40, blue: 0.75) : .white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(active ? AnyShapeStyle(.white) : AnyShapeStyle(.clear), in: .capsule)
            .glassEffect(.clear.interactive(), in: .capsule)
            .accessibilityAddTraits(active ? .isSelected : [])
            .padding(.vertical, 4).contentShape(.rect) // ≥ 44 pt tap target without changing the look
    }

    /// Picker chip (travel mode, duration): glass with a chevron.
    private func pickerChip(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(title)
            Image(systemName: "chevron.down").font(.caption2.weight(.bold)).opacity(0.8)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glassEffect(.regular.tint(.black.opacity(0.12)).interactive(), in: .capsule)
    }
}

#if DEBUG
// MARK: - Previews

#Preview("Startseite · 17:30") {
    RootView().environment(AppModel.preview())
        .preferredColorScheme(.dark)
}

#Preview("Startseite · 21:15") {
    RootView().environment(AppModel.preview(hour: 21, minute: 15))
        .preferredColorScheme(.dark)
}

#Preview("Startseite · ohne Standort") {
    RootView().environment(AppModel.preview(location: false))
        .preferredColorScheme(.dark)
}

#Preview("Startseite · alles zu (23:00)") {
    RootView().environment(AppModel.preview(hour: 23, minute: 0))
        .preferredColorScheme(.dark)
}

#Preview("Karten – alle Zustände") {
    let model = AppModel.preview { $0.showOutOfService = true }
    // one card per status, plus a women-only hint and a long name if available
    let byStatus = Dictionary(grouping: model.plans, by: \.status).compactMap { $0.value.first }
        .sorted { $0.status < $1.status }
    let shown = Set(byStatus.map(\.id))
    let extras = model.plans.filter { !shown.contains($0.id) && ($0.womenOnlyToday != nil || $0.pool.shortName.count > 35) }
    ScrollView {
        VStack(spacing: 14) {
            ForEach(byStatus + extras.prefix(2)) { PoolCard(plan: $0) }
        }
        .padding(16)
    }
    .background(WaterBackground(status: .goNow, date: PreviewData.now()).ignoresSafeArea())
    .environment(model)
    .preferredColorScheme(.dark)
}

#Preview("Filterleiste") {
    FilterBar()
        .padding()
        .background(WaterBackground(status: .goNow, date: PreviewData.now()))
        .environment(AppModel.preview { $0.minLaneLength = 50 })
        .preferredColorScheme(.dark)
}
#endif
