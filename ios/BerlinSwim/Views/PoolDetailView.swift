import BadKit
import MapKit
import SwiftUI

/// Swipe horizontally between pools, like cities in the Weather app. Shown in a sheet.
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
    }
}

/// Type scale used on this screen (keep it small):
/// .title (name) · .headline (section titles, status) · .subheadline (content) · .footnote (secondary)
struct PoolDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
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

    // MARK: Header

    private var header: some View {
        VStack(spacing: 4) {
            HStack {
                Button("Schließen", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                Spacer()
                Button(model.isFavorite(pool) ? "Favorit entfernen" : "Favorit",
                       systemImage: model.isFavorite(pool) ? "star.fill" : "star") {
                    model.toggleFavorite(pool)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
            .font(.headline)
            Text(pool.shortName)
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)
            Text([pool.type, pool.district].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline).opacity(0.85)
            StatusLabel(status: plan.status)
                .font(.headline)
                .padding(.top, 10)
            Text(plan.headline)
                .font(.system(size: 72, weight: .thin))
                .lineLimit(1).minimumScaleFactor(0.5)
            if !plan.subline.isEmpty {
                Text(plan.subline).font(.subheadline).multilineTextAlignment(.center).opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: Sections

    private var notices: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(pool.notices, id: \.self) { n in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if n.severity != .info {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    }
                    Text(n.text)
                }
                .font(.subheadline)
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

    private var water: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(pool.waterTemps, id: \.self) { w in
                VStack(spacing: 2) {
                    Text(Fmt.temperature(w.tempC)).font(.headline.monospacedDigit())
                    Text(w.basin).font(.footnote).opacity(0.8).lineLimit(2).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
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
                        Label("\(mode.title) · \(plan.travelText)", systemImage: mode.symbol)
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.glassProminent)
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
    var body: some View {
        Label {
            Text(status.title)
        } icon: {
            Image(systemName: status.symbol).foregroundStyle(.white, status.color)
        }
    }
}

/// Section with the title above the glass card.
struct DetailSection<Content: View>: View {
    let title: String
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
                .glassEffect(.regular.tint(.black.opacity(0.08)), in: .rect(cornerRadius: 20))
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
                        Text(item)
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
