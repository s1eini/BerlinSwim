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

    @Environment(AppModel.self) private var model
    @State private var sideInsets = EdgeInsets()

    var body: some View {
        // A horizontal ScrollView's viewport runs under the horizontal safe area. On the folded iPhone Duo the
        // system reserves a column on the right there, and the next pool's page peeked out in it. So clip the
        // viewport to the safe area (leading/trailing only; the page backgrounds still fill the screen behind).
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
        .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { sideInsets = $0 }
        .mask {
            Rectangle()
                .padding(.leading, sideInsets.leading)
                .padding(.trailing, sideInsets.trailing)
                .ignoresSafeArea()
        }
        .background(WaterBackground(status: plans.first { $0.pool.id == selected }?.status, date: model.now).ignoresSafeArea())
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Weekday column of the week table, grows with the text size.
    @ScaledMetric(relativeTo: .subheadline) private var dayColumnWidth: CGFloat = 100
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
                if !saunaDays.isEmpty {
                    DetailSection(title: "Sauna") { sauna }
                }
                if !pool.waterTemps.isEmpty {
                    DetailSection(title: "Wassertemperatur") { water }
                }
                if !pool.equipment.isEmpty || !pool.extras.isEmpty || !pool.accessibility.isEmpty {
                    DetailSection(title: "Ausstattung") {
                        FeatureChips(items: pool.equipment, accessibility: pool.accessibility, notes: pool.extras)
                    }
                    .id("equipment")
                }
                DetailSection(title: "Anfahrt", padded: false) { directions }
                if let prices = pool.prices, !prices.isEmpty {
                    DetailSection(title: "Preise") { priceList(prices) }
                        .id("prices")
                }
                links
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: 720) // iPad: readable column
            .frame(maxWidth: .infinity)
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
                // Very large text: weekday above the times instead of a column next to them.
                let rowLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                rowLayout {
                    Text(offset == 0 ? String(localized: "Heute") : day.formatted(.dateTime.weekday(.wide).locale(.autoupdatingCurrent)))
                        .fontWeight(offset == 0 ? .semibold : .regular)
                        .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : dayColumnWidth, alignment: .leading)
                    if today.isEmpty {
                        Text("–").opacity(0.7)
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
                .font(.footnote).opacity(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
    }

    /// One row per basin – scales from one to many basins without squeezing.
    // MARK: Sauna

    /// Sauna slots of the next 7 days (sauna areas only; no closed/private slots).
    private var saunaDays: [(day: Date, slots: [Slot])] {
        let saunaAreas = pool.areas.filter { $0.kind == .sauna }
        guard !saunaAreas.isEmpty else { return [] }
        let cal = Calendar.berlin
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: cal.startOfDay(for: model.now)) }
        let result = days.map { day in
            (day, saunaAreas.flatMap(\.slots)
                .filter { $0.kind != .private && cal.isDate($0.start, inSameDayAs: day) }
                .sorted { $0.start < $1.start })
        }
        return result.contains { !$0.1.isEmpty } ? result : []
    }

    /// Weekly sauna times, same layout as the public swimming table; women-only days are labelled.
    private var sauna: some View {
        VStack(spacing: 0) {
            ForEach(Array(saunaDays.enumerated()), id: \.offset) { offset, entry in
                let rowLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                rowLayout {
                    Text(offset == 0 ? String(localized: "Heute") : entry.day.formatted(.dateTime.weekday(.wide).locale(.autoupdatingCurrent)))
                        .fontWeight(offset == 0 ? .semibold : .regular)
                        .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : dayColumnWidth, alignment: .leading)
                    if entry.slots.isEmpty {
                        Text("–").opacity(0.7)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(entry.slots, id: \.self) { s in
                                Text(Fmt.rangeUhr(s.start, s.end) + (s.kind == .restricted ? " · " + s.shortLabel : ""))
                            }
                        }
                    }
                    Spacer()
                }
                .font(.subheadline.monospacedDigit())
                .padding(.vertical, 8)
                if offset < saunaDays.count - 1 { Divider().overlay(.white.opacity(0.2)) }
            }
        }
    }

    // MARK: Prices

    /// "90-Minuten-Ticket (Kategorie 2)" → "90-Minuten-Ticket" (the category is shown once above).
    private func ticketName(_ title: String) -> String {
        siteTerm(title.replacingOccurrences(of: #"\s*\(Kategorie \d\)"#, with: "", options: .regularExpression))
    }

    /// The tickets most visitors need, shown at first glance (without the fine print).
    private static let highlightTickets = ["90-Minuten-Ticket", "150-Minuten-Ticket", "Tagesticket"]

    /// "Sommerbad: Tagesticket (Kategorie 3)" → "Tagesticket"
    private func isHighlight(_ p: Price) -> Bool {
        let base = p.title
            .replacingOccurrences(of: #"\s*\(Kategorie \d\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[^:]+:\s*"#, with: "", options: .regularExpression)
        return Self.highlightTickets.contains(base)
    }

    private func priceRow(_ p: Price, showNote: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ticketName(p.title))
                if showNote, let note = p.note { Text(note).font(.footnote).opacity(0.85) }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                if let price = p.price { Text(price).fontWeight(.semibold) }
                if let reduced = p.reduced {
                    Text("ermäßigt \(reduced)").font(.footnote).opacity(0.85)
                }
            }
            .monospacedDigit()
        }
        .font(.subheadline)
        .padding(.vertical, 8)
    }

    /// Rows separated by dividers.
    private func priceRows(_ rows: [Price], showNotes: Bool) -> some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { i, p in
            priceRow(p, showNote: showNotes)
            if i < rows.count - 1 { Divider().overlay(.white.opacity(0.2)) }
        }
    }

    /// Rows grouped by tariff group (Badetarif, Saunatarif, Abo-Tarif …), with a heading per group.
    private func groupedPrices(_ prices: [Price]) -> some View {
        let groups = prices.reduce(into: [String?]()) { if !$0.contains($1.group) { $0.append($1.group) } }
        return ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
            VStack(alignment: .leading, spacing: 0) {
                if groups.count > 1, let group { // a lone group needs no heading
                    Text(siteTerm(group)).font(.subheadline.weight(.semibold)).padding(.top, 8).padding(.bottom, 4)
                }
                priceRows(prices.filter { $0.group == group }, showNotes: true)
            }
        }
    }

    /// At first glance: 90 min / 150 min / day ticket. Everything else (other tariffs, fine print) expands.
    private func priceList(_ prices: [Price]) -> some View {
        let highlights = prices.filter(isHighlight)
        let rest = prices.filter { !isHighlight($0) }
        let notes = pool.priceNotes ?? []
        let expandable = !highlights.isEmpty && !rest.isEmpty // the notes then live inside "Alle Preise"
        return VStack(alignment: .leading, spacing: 8) {
            if let category = pool.category {
                Text("Bad-Kategorie \(category)").font(.footnote.weight(.semibold)).opacity(0.85)
            }
            if highlights.isEmpty {
                groupedPrices(prices)
            } else {
                VStack(alignment: .leading, spacing: 0) { priceRows(highlights, showNotes: false) }
                if !rest.isEmpty {
                    Divider().overlay(.white.opacity(0.2))
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 0) { groupedPrices(rest) }
                            ForEach(notes, id: \.self) { Text($0).font(.footnote).opacity(0.85) }
                        }
                    } label: {
                        Text("Alle Preise").font(.subheadline.weight(.semibold))
                    }
                    .tint(.white)
                }
            }
            if !expandable {
                ForEach(notes, id: \.self) { Text($0).font(.footnote).opacity(0.85) }
            }
            if let reducedFor = pool.reducedFor, !reducedFor.isEmpty {
                Divider().overlay(.white.opacity(0.2))
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(reducedFor, id: \.self) { Text("• " + $0) }
                    }
                    .font(.footnote)
                    .opacity(0.9)
                    .padding(.top, 6)
                } label: {
                    Text("Wer zahlt ermäßigt?").font(.subheadline.weight(.semibold))
                }
                .tint(.white)
            }
        }
    }

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
                .foregroundStyle(.white)
                .padding(.leading, 4)
            content
                .foregroundStyle(.white)
                .padding(padded ? 16 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular.tint(.black.opacity(0.18)), in: .rect(cornerRadius: 20))
        }
    }
}

/// Feature chips (equipment and accessibility together, no sub-heading) and free-text notes below a divider.
struct FeatureChips: View {
    let items: [String]
    var accessibility: [String] = []
    let notes: [String]

    private var all: [String] { items + accessibility.filter { !items.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            chips(all)
            if !notes.isEmpty {
                if !all.isEmpty { Divider().overlay(.white.opacity(0.25)) }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(notes.prefix(6), id: \.self) { Text($0) }
                }
                .font(.footnote)
                .opacity(0.9)
            }
        }
    }

    @ViewBuilder
    private func chips(_ items: [String]) -> some View {
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
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    /// Natural size, but never wider than a row: very large text then wraps inside the chip
    /// instead of running off screen.
    private func size(of view: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let ideal = view.sizeThatFits(.unspecified)
        guard ideal.width > maxWidth, maxWidth.isFinite else { return ideal }
        return view.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = size(of: subviews[i], maxWidth: bounds.width)
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
            let size = size(of: sv, maxWidth: width)
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
