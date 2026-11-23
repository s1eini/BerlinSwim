import BadKit
import SwiftUI

/// Swipe horizontally between pools, like cities in the Weather app.
struct PoolPager: View {
    let plans: [SwimPlan]
    @State var selected: Pool?

    init(plans: [SwimPlan], selected: Pool) {
        self.plans = plans
        _selected = State(initialValue: selected)
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(plans) { plan in
                    PoolDetailView(pool: plan.pool)
                        .containerRelativeFrame(.horizontal)
                        .id(Optional(plan.pool))
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $selected)
        .scrollIndicators(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

struct PoolDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let pool: Pool

    private var plan: SwimPlan { model.plan(for: pool) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                if !pool.notices.isEmpty {
                    DetailSection(title: "Hinweise") { notices }
                }
                if let o = plan.occupancy {
                    DetailSection(title: "Auslastung") { occupancy(o) }
                }
                DetailSection(title: "Heute") {
                    DayTimeline(pool: pool, day: model.now, now: model.now, plan: plan)
                }
                DetailSection(title: "Öffentliches Schwimmen") { week }
                if !pool.waterTemps.isEmpty {
                    DetailSection(title: "Wassertemperatur") { water }
                }
                if !pool.equipment.isEmpty || !pool.extras.isEmpty {
                    DetailSection(title: "Ausstattung") { FeatureGrid(items: pool.equipment, extras: pool.extras) }
                }
                if !pool.accessibility.isEmpty {
                    DetailSection(title: "Barrierefreiheit") { FeatureGrid(items: pool.accessibility, extras: []) }
                }
                DetailSection(title: "Anfahrt") { directions }
                links
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(WaterBackground(status: plan.status, date: model.now).ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(model.isFavorite(pool) ? "Favorit entfernen" : "Favorit",
                       systemImage: model.isFavorite(pool) ? "star.fill" : "star") {
                    model.toggleFavorite(pool)
                }
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 4) {
            Text(pool.shortName)
                .font(.system(size: 30, weight: .semibold))
                .multilineTextAlignment(.center)
            Text([pool.type, pool.district].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline).opacity(0.85)
            StatusLabel(status: plan.status)
                .font(.headline)
                .padding(.top, 10)
            Text(plan.headline)
                .font(.system(size: 76, weight: .thin))
                .lineLimit(1).minimumScaleFactor(0.5)
            if !plan.subline.isEmpty {
                Text(plan.subline).font(.subheadline).multilineTextAlignment(.center).opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.15), radius: 4)
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    // MARK: Sections

    private var notices: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(pool.notices, id: \.self) { n in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if n.severity != .info {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    }
                    Text(n.text).font(.subheadline)
                }
            }
        }
    }

    private func occupancy(_ o: Occupancy) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            OccupancyMeter(o).font(.subheadline.weight(.medium))
            Text(o.automatic
                 ? "Live-Zähler der Berliner Bäder-Betriebe\(o.count.map { " · \($0) Gäste" } ?? "")"
                 : "Ampel der Berliner Bäder-Betriebe")
                .font(.caption).opacity(0.75)
        }
    }

    private var week: some View {
        let windows = SwimPlanner(preferences: model.preferences).windows(for: pool)
        return VStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { offset in
                let day = Calendar.berlin.date(byAdding: .day, value: offset, to: model.now)!
                let today = windows.filter { Calendar.berlin.isDate($0.start, inSameDayAs: day) }
                HStack(alignment: .firstTextBaseline) {
                    Text(offset == 0 ? "Heute" : day.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "de_DE"))))
                        .fontWeight(offset == 0 ? .semibold : .regular)
                        .frame(width: 100, alignment: .leading)
                    if today.isEmpty {
                        Text("–").opacity(0.5)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(today, id: \.self) { w in
                                Text(Fmt.range(w.start, w.end) + (w.isLimited ? " *" : ""))
                            }
                        }
                    }
                    Spacer()
                }
                .font(.body.monospacedDigit())
                .padding(.vertical, 8)
                if offset < 6 { Divider().overlay(.white.opacity(0.2)) }
            }
            Text("* zeitweise eingeschränkte Wasserfläche · Einlass bis \(pool.rules.entryCutoffMin) min, Badeschluss \(pool.rules.exitBeforeCloseMin) min vor Ende")
                .font(.caption).opacity(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
    }

    private var water: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(pool.waterTemps, id: \.self) { w in
                VStack(spacing: 2) {
                    Text(Fmt.temperature(w.tempC)).font(.title2.weight(.light)).monospacedDigit()
                    Text(w.basin).font(.caption).opacity(0.8).lineLimit(2).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var directions: some View {
        HStack(alignment: .center) {
            Text(pool.address).font(.subheadline)
            Spacer()
            Button("Karten", systemImage: "arrow.triangle.turn.up.right.diamond.fill") {
                RoutingService.openDirections(to: pool, mode: model.preferences.travelMode)
            }
            .buttonStyle(.glass)
        }
    }

    private var links: some View {
        HStack(spacing: 10) {
            if let t = pool.ticketUrl {
                Button("Ticket", systemImage: "ticket") { openURL(t) }.buttonStyle(.glass)
            }
            Button("Webseite", systemImage: "safari") { openURL(pool.url) }.buttonStyle(.glass)
            ShareLink(item: pool.url) { Label("Teilen", systemImage: "square.and.arrow.up") }
                .buttonStyle(.glass)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }
}

/// "✓ Offen" etc.: white text, status-colored icon.
struct StatusLabel: View {
    let status: SwimPlan.Status
    var body: some View {
        Label {
            Text(status.title)
        } icon: {
            Image(systemName: status.symbol).foregroundStyle(.white, status.color)
        }
    }
}

/// Section with the title above the glass card (Weather-app module style, but readable).
struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.leading, 4)
            content
                .foregroundStyle(.white)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular.tint(.black.opacity(0.08)), in: .rect(cornerRadius: 20))
        }
    }
}

/// Two-column list of features plus free-text extras.
struct FeatureGrid: View {
    let items: [String]
    let extras: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !items.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                          alignment: .leading, spacing: 8) {
                    ForEach(items, id: \.self) { Text($0).font(.subheadline) }
                }
            }
            if !extras.isEmpty {
                if !items.isEmpty { Divider().overlay(.white.opacity(0.2)) }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(extras.prefix(6), id: \.self) { Text($0).font(.footnote).opacity(0.8) }
                }
            }
        }
    }
}
