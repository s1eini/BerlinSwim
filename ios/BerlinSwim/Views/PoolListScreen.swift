import BadKit
import SwiftUI

/// Weather-app style list: a hero for the best option, then one card per pool.
struct PoolListScreen: View {
    @Environment(AppModel.self) private var model
    @State private var showAll = false

    private var favorites: [SwimPlan] { model.plans.filter { model.isFavorite($0.pool) } }
    private var hero: SwimPlan? { model.plans.first.flatMap { $0.status <= .tight ? $0 : nil } }
    private var reachable: [SwimPlan] {
        model.plans.filter { !model.isFavorite($0.pool) && $0.status <= .tight && $0.pool.id != hero?.pool.id }
    }
    private var others: [SwimPlan] {
        model.plans.filter { !model.isFavorite($0.pool) && $0.status > .tight }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    header
                    FilterBar()
                    if let best = hero {
                        NavigationLink(value: best.pool) { HeroCard(plan: best) }
                            .buttonStyle(.plain)
                    }
                    if let error = model.errorMessage {
                        Label(error, systemImage: "wifi.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(10)
                            .glassEffect(.regular, in: .capsule)
                    }
                    section("Favoriten", favorites)
                    section("Erreichbar", reachable)
                    if !others.isEmpty {
                        DisclosureGroup(isExpanded: $showAll) {
                            LazyVStack(spacing: 12) { cards(others) }.padding(.top, 8)
                        } label: {
                            Text("Heute nicht mehr / geschlossen (\(others.count))")
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
            }
            .scrollIndicators(.hidden)
            .background(WaterBackground(status: model.plans.first?.status, date: model.now).ignoresSafeArea())
            .refreshable { await model.refresh(force: true) }
            .navigationDestination(for: Pool.self) { pool in
                PoolPager(plans: model.plans, selected: pool)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text(model.location == nil ? "Berlin" : "Mein Standort")
                .font(.system(size: 15, weight: .semibold)).textCase(.uppercase).opacity(0.85)
            Text("Schwimmen gehen?")
                .font(.system(size: 34, weight: .bold))
            Text("\(Fmt.minutes(model.preferences.trainingMinutes)) Training · \(model.preferences.travelMode.title)")
                .font(.subheadline).opacity(0.85)
            if model.locationDenied {
                Text("Standort nicht freigegeben – rechne ab Alexanderplatz")
                    .font(.caption).opacity(0.8).padding(.top, 4)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.15), radius: 4)
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func section(_ title: String, _ plans: [SwimPlan]) -> some View {
        if !plans.isEmpty {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))
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
        .foregroundStyle(.white.opacity(0.7))
        .padding(.top, 12)
    }
}

/// Big "current location" style card for the top recommendation.
struct HeroCard: View {
    let plan: SwimPlan

    var body: some View {
        VStack(spacing: 6) {
            Label {
                Text(plan.status.title)
            } icon: {
                Image(systemName: plan.status.symbol).foregroundStyle(.white, plan.status.color)
            }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)
            Text(plan.pool.shortName)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(plan.headline)
                .font(.system(size: 64, weight: .thin))
                .contentTransition(.numericText())
            Text(plan.subline)
                .font(.subheadline)
                .multilineTextAlignment(.center)
            HStack(spacing: 14) {
                Label(plan.travelText, systemImage: "location.fill")
                if let lane = plan.window?.laneLength { Label("\(lane) m", systemImage: "figure.pool.swim") }
                if let temp = plan.pool.waterTempC { Label(Fmt.temperature(temp), systemImage: "thermometer.medium") }
            }
            .font(.footnote.weight(.medium))
            .opacity(0.9)
            .padding(.top, 4)
            if let o = plan.occupancy { OccupancyMeter(o).font(.footnote.weight(.medium)).padding(.top, 2) }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .glassEffect(.clear, in: .rect(cornerRadius: 28))
        .accessibilityElement(children: .combine)
    }
}

/// Compact list card, like a city row in the Weather app.
struct PoolCard: View {
    @Environment(AppModel.self) private var model
    let plan: SwimPlan

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(plan.pool.shortName).font(.title3.weight(.semibold)).lineLimit(1)
                    if model.isFavorite(plan.pool) { Image(systemName: "star.fill").font(.caption) }
                }
                Text([plan.pool.district, plan.travelText + " " + model.preferences.travelMode.title.lowercased()]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote).opacity(0.85)
                Spacer(minLength: 6)
                Text(plan.subline).font(.footnote).lineLimit(2).opacity(0.95)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(plan.headline)
                    .font(.system(size: plan.headline.count > 8 ? 24 : 34, weight: .light))
                    .lineLimit(1).minimumScaleFactor(0.6)
                Label {
                    Text(plan.status.title)
                } icon: {
                    Image(systemName: plan.status.symbol).foregroundStyle(.white, plan.status.color)
                }
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    if let lane = plan.pool.laneLength { Text("\(lane) m") }
                    if let t = plan.pool.waterTempC { Text(Fmt.temperature(t)) }
                    if let o = plan.occupancy { OccupancyMeter(o, compact: true) }
                    if !plan.pool.warnings.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    }
                }
                .font(.caption.weight(.medium)).opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(minHeight: 116)
        .background {
            WaterBackground(status: plan.status, date: model.now)
                .opacity(0.55)
                .clipShape(.rect(cornerRadius: 22))
        }
        .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}

struct FilterBar: View {
    @Environment(AppModel.self) private var model

    private let quick: [Feature] = [.lane50, .lane25, .sauna, .diving, .toddler, .accessible]

    var body: some View {
        @Bindable var model = model
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Menu {
                        Picker("Verkehrsmittel", selection: $model.preferences.travelMode) {
                            ForEach(TravelMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                    } label: {
                        pickerChip(model.preferences.travelMode.title, model.preferences.travelMode.symbol)
                    }
                    Menu {
                        Picker("Training", selection: $model.preferences.trainingMinutes) {
                            ForEach([30, 45, 60, 75, 90, 120], id: \.self) { Text(Fmt.minutes($0)).tag($0) }
                        }
                    } label: {
                        pickerChip(Fmt.minutes(model.preferences.trainingMinutes), "timer")
                    }
                    Button {
                        withAnimation(.snappy) { model.preferences.avoidCrowded.toggle() }
                    } label: { chip("Nicht voll", "person.2.slash", active: model.preferences.avoidCrowded) }
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
