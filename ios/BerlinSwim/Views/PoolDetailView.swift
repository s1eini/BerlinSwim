import BadKit
import MapKit
import SwiftUI

/// Swipe horizontally between pools, like cities in the Weather app. Shown in a sheet.
struct PoolPager: View {
    let plans: [SwimPlan]
    /// Scroll position by pool id (stable across data refreshes).
    @State var selected: Int?

    init(plans: [SwimPlan], selected: Pool) {
        self.plans = plans
        _selected = State(initialValue: selected.id)
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(plans) { plan in
                    PoolDetailView(pool: plan.pool)
                        .containerRelativeFrame(.horizontal)
                        .id(plan.pool.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $selected)
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .bottom)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if let pool = plans.first(where: { $0.pool.id == selected })?.pool {
                ToolbarItem(placement: .topBarTrailing) { FavoriteButton(pool: pool) }
            }
        }
    }
}

struct FavoriteButton: View {
    @Environment(AppModel.self) private var model
    let pool: Pool
    var body: some View {
        Button(model.isFavorite(pool) ? "Favorit entfernen" : "Favorit",
               systemImage: model.isFavorite(pool) ? "star.fill" : "star") {
            model.toggleFavorite(pool)
        }
    }
}

/// Type scale used on this screen (keep it small):
/// .title (name) · .headline (section titles, status) · .subheadline (content) · .footnote (secondary)
struct PoolDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let pool: Pool

    private var plan: SwimPlan { model.plan(for: pool) }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if !pool.notices.isEmpty {
                    DetailSection(title: "Hinweise") { notices }
                }
                if plan.status <= .tight, let o = plan.occupancy {
                    DetailSection(title: "Auslastung") { occupancy(o) }
                }
                if hasSlotsToday {
                    DetailSection(title: "Heute") {
                        DayTimeline(pool: pool, day: model.now, now: model.now, plan: plan)
                    }
                }
                if !weekWindows.isEmpty {
                    DetailSection(title: "Öffentliches Schwimmen") { week }
                }
                if !pool.waterTemps.isEmpty {
                    DetailSection(title: "Wassertemperatur") { water }
                }
                if !pool.equipment.isEmpty || !pool.extras.isEmpty {
                    DetailSection(title: "Ausstattung") { FeatureChips(items: pool.equipment, notes: pool.extras) }
                        .id("equipment")
                }
                if !pool.accessibility.isEmpty {
                    DetailSection(title: "Barrierefreiheit") { FeatureChips(items: pool.accessibility, notes: []) }
                }
                DetailSection(title: "Anfahrt", padded: false) { directions }
                links
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(WaterBackground(status: plan.status, date: model.now).ignoresSafeArea())
        #if DEBUG
        .task {
            // Screenshot aid: launch with `-detailScroll equipment`
            if let anchor = UserDefaults.standard.string(forKey: "detailScroll") {
                try? await Task.sleep(for: .seconds(1))
                proxy.scrollTo(anchor, anchor: .top)
            }
        }
        #endif
        }
    }

    private var hasSlotsToday: Bool {
        pool.areas.contains { $0.slots.contains { Calendar.berlin.isDate($0.start, inSameDayAs: model.now) } }
    }

    private var weekWindows: [SwimWindow] {
        let end = Calendar.berlin.date(byAdding: .day, value: 7, to: Calendar.berlin.startOfDay(for: model.now))!
        var prefs = model.preferences
        prefs.minLaneLength = nil
        return SwimPlanner(preferences: prefs).windows(for: pool)
            .filter { $0.start < end && $0.end > Calendar.berlin.startOfDay(for: model.now) }
    }

    /// Closure reason only if it isn't already one of the notices.
    private var extraClosedReason: String? {
        guard plan.status == .closed, let r = plan.closedReason, !pool.notices.contains(where: { $0.text == r }) else { return nil }
        return r
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 6) {
            Text(pool.shortName)
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)
            Text([pool.type.map(siteTerm), pool.district].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline).opacity(0.85)
            StatusLabel(status: plan.status, title: plan.statusSentence)
                .font(.title3)
                .monospacedDigit()
                .multilineTextAlignment(.center)
            .padding(.top, 8)
            if let hint = plan.hint ?? extraClosedReason {
                Text(hint).font(.subheadline).multilineTextAlignment(.center).opacity(0.85)
            }
            if let w = plan.womenOnlyToday {
                Label("Heute Frauenschwimmen \(w.start > plan.arrival ? "ab \(Fmt.clock(w.start))" : "bis \(Fmt.clock(w.end))")",
                      systemImage: "figure.stand.dress")
                    .font(.subheadline).opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: Sections

    private var notices: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Important ones (closures, restrictions) first, one paragraph each.
            ForEach(pool.notices.sorted { ($0.severity == .info ? 1 : 0) < ($1.severity == .info ? 1 : 0) }, id: \.self) { n in
                Text(n.text).font(.subheadline)
            }
        }
    }

    private func occupancy(_ o: Occupancy) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            OccupancyMeter(o).font(.subheadline)
            Text(o.automatic ? "Live-Zähler der Berliner Bäder-Betriebe" : "Angabe der Berliner Bäder-Betriebe")
                .font(.footnote).opacity(0.75)
        }
    }

    private var week: some View {
        let windows = weekWindows
        return VStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { offset in
                let day = Calendar.berlin.date(byAdding: .day, value: offset, to: model.now)!
                let today = windows.filter { Calendar.berlin.isDate($0.start, inSameDayAs: day) }
                HStack(alignment: .firstTextBaseline) {
                    Text(offset == 0 ? String(localized: "Heute") : day.formatted(.dateTime.weekday(.wide).locale(.autoupdatingCurrent)))
                        .fontWeight(offset == 0 ? .semibold : .regular)
                        .frame(width: 100, alignment: .leading)
                    if today.isEmpty {
                        Text("–").opacity(0.5)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(today, id: \.self) { w in
                                Text(Fmt.rangeUhr(w.start, w.end) + (w.isLimited ? " *" : ""))
                            }
                        }
                    }
                    Spacer()
                }
                .font(.subheadline.monospacedDigit())
                .padding(.vertical, 8)
                if offset < 6 { Divider().overlay(.white.opacity(0.2)) }
            }
            Text("* zeitweise eingeschränkte Wasserfläche · Einlass bis \(pool.rules.entryCutoffMin) min, Badeschluss \(pool.rules.exitBeforeCloseMin) min vor Ende")
                .font(.footnote).opacity(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
    }

    /// One row per basin – scales from one to many basins without squeezing.
    private var water: some View {
        VStack(spacing: 0) {
            ForEach(Array(pool.waterTemps.enumerated()), id: \.offset) { i, w in
                HStack {
                    Text(siteTerm(w.basin))
                    Spacer()
                    Text(Fmt.temperature(w.tempC)).monospacedDigit().fontWeight(.semibold)
                }
                .font(.subheadline)
                .padding(.vertical, 8)
                if i < pool.waterTemps.count - 1 { Divider().overlay(.white.opacity(0.2)) }
            }
        }
    }

    @ViewBuilder
    private var directions: some View {
        let mode = model.preferences.travelMode
        VStack(alignment: .leading, spacing: 0) {
            if let lat = pool.lat, let lon = pool.lon {
                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                Map(initialPosition: .region(MKCoordinateRegion(center: coord, latitudinalMeters: 900, longitudinalMeters: 900)),
                    interactionModes: []) {
                    Marker(pool.shortName, systemImage: "figure.pool.swim", coordinate: coord)
                        .tint(plan.status.color)
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .frame(height: 180)
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        RoutingService.openDirections(to: pool, mode: mode)
                    } label: {
                        if plan.travelKnown {
                            Label("\(plan.travelText)", systemImage: mode.symbol)
                        } else {
                            // no location: Apple Maps routes from the device position itself
                            Label("Route", systemImage: "arrow.triangle.turn.up.right.diamond")
                        }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .padding(10)
                }
            }
            Text(pool.address)
                .font(.subheadline)
                .padding(16)
        }
        .clipShape(.rect(cornerRadius: 20))
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
        .font(.subheadline)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }
}

/// "✓ Offen" etc.: white text, status-colored icon.
struct StatusLabel: View {
    let status: SwimPlan.Status
    /// Override the text (e.g. "Öffnet um 06:00"); defaults to the status title.
    var title: String? = nil
    var body: some View {
        Label {
            Text(title ?? status.title)
        } icon: {
            Image(systemName: status.symbol).foregroundStyle(.white, status.color)
        }
    }
}

/// Section with the title above the glass card.
struct DetailSection<Content: View>: View {
    let title: LocalizedStringKey
    var padded = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.leading, 4)
            content
                .foregroundStyle(.white)
                .padding(padded ? 16 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular.tint(.black.opacity(0.18)), in: .rect(cornerRadius: 20))
        }
    }
}

/// Feature chips, with free-text notes below a divider.
struct FeatureChips: View {
    let items: [String]
    let notes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !items.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(items, id: \.self) { item in
                        Text(siteTerm(item))
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.white.opacity(0.16), in: .capsule)
                    }
                }
            }
            if !notes.isEmpty {
                if !items.isEmpty { Divider().overlay(.white.opacity(0.25)) }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(notes.prefix(6), id: \.self) { Text($0) }
                }
                .font(.footnote)
                .opacity(0.8)
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

// MARK: - Previews

#if DEBUG
/// Detail page for the first pool matching `pick` (falls back to the first pool).
private struct DetailPreview: View {
    let model: AppModel
    let pick: (SwimPlan) -> Bool

    var body: some View {
        let plan = model.allPlans.first(where: pick) ?? model.allPlans.first
        NavigationStack {
            if let plan { PoolPager(plans: [plan], selected: plan.pool) }
        }
        .environment(model)
        .preferredColorScheme(.dark)
    }
}

#Preview("Detail · offen") {
    DetailPreview(model: .preview()) { $0.status == .goNow && $0.occupancy != nil }
}

#Preview("Detail · schließt bald") {
    DetailPreview(model: .preview(hour: 20, minute: 10)) { $0.status == .goNow && $0.closingSoon }
}

#Preview("Detail · später / knapp") {
    DetailPreview(model: .preview(hour: 11)) { $0.status == .later || $0.status == .tight }
}

#Preview("Detail · heute zu (Hinweise)") {
    DetailPreview(model: .preview()) { $0.status == .notToday && !$0.pool.notices.isEmpty }
}

#Preview("Detail · geschlossen") {
    DetailPreview(model: .preview { $0.showOutOfService = true }) { $0.status == .closed }
}

#Preview("Detail · Frauenschwimmen") {
    DetailPreview(model: .preview()) { $0.womenOnlyToday != nil || $0.pool.name.contains("Neukölln") }
}

#Preview("Detail · viele Wassertemperaturen") {
    DetailPreview(model: .preview()) { $0.pool.waterTemps.count >= 4 }
}
#endif
