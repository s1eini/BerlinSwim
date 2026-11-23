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
        .ignoresSafeArea(edges: .bottom)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PoolDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let pool: Pool

    private var plan: SwimPlan { model.plan(for: pool) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                hero
                if !pool.notices.isEmpty { noticesCard }
                todayCard
                weekCard
                if !pool.waterTemps.isEmpty { waterCard }
                if !pool.equipment.isEmpty || !pool.extras.isEmpty { equipmentCard }
                if !pool.accessibility.isEmpty { accessibilityCard }
                travelCard
                linksCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
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
            Text(pool.shortName).font(.system(size: 30, weight: .semibold)).multilineTextAlignment(.center)
            Text([pool.type, pool.district].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline).opacity(0.85)
            Text(plan.headline)
                .font(.system(size: 80, weight: .thin))
                .lineLimit(1).minimumScaleFactor(0.5)
            Label(plan.status.title, systemImage: plan.status.symbol)
                .font(.headline)
            Text(plan.subline).font(.subheadline).multilineTextAlignment(.center).opacity(0.9)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.15), radius: 4)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }

    // MARK: Cards

    private var noticesCard: some View {
        GlassCard(title: "Hinweise", symbol: "exclamationmark.triangle.fill") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(pool.notices, id: \.self) { n in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: n.severity == .info ? "info.circle" : "exclamationmark.triangle.fill")
                            .foregroundStyle(n.severity == .info ? .white : .yellow)
                        Text(n.text).font(.subheadline)
                    }
                }
            }
        }
    }

    private var todayCard: some View {
        GlassCard(title: "Heute", symbol: "clock") {
            DayTimeline(pool: pool, day: model.now, now: model.now, plan: plan)
        }
    }

    private var weekCard: some View {
        GlassCard(title: "Nächste Tage – öffentliches Schwimmen", symbol: "calendar") {
            VStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { offset in
                    let day = Calendar.berlin.date(byAdding: .day, value: offset, to: model.now)!
                    let windows = SwimPlanner(preferences: model.preferences).windows(for: pool)
                        .filter { Calendar.berlin.isDate($0.start, inSameDayAs: day) }
                    HStack(alignment: .firstTextBaseline) {
                        Text(offset == 0 ? "Heute" : day.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "de_DE"))))
                            .frame(width: 96, alignment: .leading)
                            .fontWeight(offset == 0 ? .semibold : .regular)
                        if windows.isEmpty {
                            Text("–").opacity(0.6)
                        } else {
                            Text(windows.map { "\(Fmt.clock($0.start))–\(Fmt.clock($0.end))\($0.isLimited ? "*" : "")" }
                                .joined(separator: ", "))
                                .monospacedDigit()
                        }
                        Spacer()
                    }
                    .font(.subheadline)
                    if offset < 6 { Divider().overlay(.white.opacity(0.2)) }
                }
                Text("* teilweise eingeschränkte Wasserfläche. Einlass bis \(pool.rules.entryCutoffMin) min, Badeschluss \(pool.rules.exitBeforeCloseMin) min vor Ende.")
                    .font(.caption).opacity(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var waterCard: some View {
        GlassCard(title: "Wassertemperatur", symbol: "thermometer.medium") {
            HStack(spacing: 12) {
                ForEach(pool.waterTemps, id: \.self) { w in
                    VStack(spacing: 2) {
                        Text(Fmt.temperature(w.tempC)).font(.title2.weight(.light))
                        Text(w.basin).font(.caption).opacity(0.8).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var equipmentCard: some View {
        GlassCard(title: "Ausstattung", symbol: "sparkles") {
            VStack(alignment: .leading, spacing: 10) {
                FlowChips(items: pool.equipment)
                ForEach(pool.extras.prefix(6), id: \.self) { Text("• \($0)").font(.footnote).opacity(0.85) }
                if let c = pool.category { Text("Bad-Kategorie \(c)").font(.footnote).opacity(0.75) }
            }
        }
    }

    private var accessibilityCard: some View {
        GlassCard(title: "Barrierefreiheit", symbol: "figure.roll") {
            FlowChips(items: pool.accessibility)
        }
    }

    private var travelCard: some View {
        GlassCard(title: "Anfahrt", symbol: "location.fill") {
            VStack(alignment: .leading, spacing: 8) {
                Text(pool.address).font(.subheadline)
                Text("\(plan.travelText) \(model.preferences.travelMode.title.lowercased())\(plan.travelIsEstimate ? " (geschätzt)" : "")")
                    .font(.subheadline.weight(.semibold))
                if let t = pool.transit { Text(t).font(.footnote).opacity(0.85) }
                if let level = pool.traffic {
                    Label("Auslastung: \(["niedrig", "gering", "mittel", "hoch", "sehr hoch"][min(level, 4)])",
                          systemImage: "person.3.fill").font(.footnote)
                }
                Button("Route in Karten", systemImage: "arrow.triangle.turn.up.right.diamond.fill") {
                    RoutingService.openDirections(to: pool, mode: model.preferences.travelMode)
                }
                .buttonStyle(.glassProminent)
                .tint(.white.opacity(0.3))
                .padding(.top, 4)
            }
        }
    }

    private var linksCard: some View {
        HStack(spacing: 10) {
            if let t = pool.ticketUrl {
                Button("Ticket", systemImage: "ticket") { openURL(t) }.buttonStyle(.glass)
            }
            Button("Webseite", systemImage: "safari") { openURL(pool.url) }.buttonStyle(.glass)
            ShareLink(item: pool.url) { Label("Teilen", systemImage: "square.and.arrow.up") }
                .buttonStyle(.glass)
        }
        .foregroundStyle(.white)
    }
}

/// Weather-app style module.
struct GlassCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .opacity(0.7)
            Divider().overlay(.white.opacity(0.25))
            content
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.black.opacity(0.08)), in: .rect(cornerRadius: 20))
    }
}

struct FlowChips: View {
    let items: [String]
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.footnote)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(0.15), in: .capsule)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, sv) in subviews.enumerated() {
            let size = sv.sizeThatFits(.unspecified)
            if rows[rows.count - 1].width + size.width > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            rows[rows.count - 1].indices.append(i)
            rows[rows.count - 1].width += size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
