import BadKit
import SwiftUI

/// One track per area for today (06–23 h): segments by slot kind, a "now" tick,
/// and a thin bar under the track for your planned swim.
struct DayTimeline: View {
    let pool: Pool
    let day: Date
    let now: Date
    let plan: SwimPlan

    private let startHour = 6.0, endHour = 23.0
    private let ticks = [6, 10, 14, 18, 22]

    private var dayStart: Date { Calendar.berlin.startOfDay(for: day).addingTimeInterval(startHour * 3600) }
    private var dayEnd: Date { Calendar.berlin.startOfDay(for: day).addingTimeInterval(endHour * 3600) }

    private var areas: [(Area, [Slot])] {
        pool.areas.compactMap { a in
            let s = a.slots.filter { $0.end > dayStart && $0.start < dayEnd }.sorted { $0.start < $1.start }
            return s.isEmpty ? nil : (a, s)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if areas.isEmpty {
                Text("Heute keine Öffnungszeiten.")
                    .font(.subheadline).opacity(0.85)
            }
            ForEach(areas, id: \.0.name) { area, slots in
                VStack(alignment: .leading, spacing: 8) {
                    Text(siteTerm(area.name) + (area.laneLength.map { " · \($0) m" } ?? ""))
                        .font(.subheadline.weight(.semibold))
                    track(area: area, slots: slots)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(slots, id: \.self) { s in
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 2).fill(color(for: s.kind)).frame(width: 10, height: 10)
                                Text(Fmt.range(s.start, s.end)).monospacedDigit()
                                Text(s.shortLabel).opacity(0.8).lineLimit(1)
                            }
                            .font(.footnote)
                        }
                    }
                }
            }
            if !areas.isEmpty { legend }
        }
    }

    private func track(area: Area, slots: [Slot]) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Rectangle().fill(.white.opacity(0.08))
                    ForEach(slots, id: \.self) { s in
                        Rectangle()
                            .fill(color(for: s.kind))
                            .frame(width: max(2, width(s.start, s.end, w) - 1)) // 1 pt gap between segments
                            .offset(x: x(s.start, w))
                    }
                }
                .clipShape(.rect(cornerRadius: 5))
                // "Now" marker: red line with a dot above the track (like Calendar), not to be confused with a gap.
                .overlay(alignment: .leading) {
                    if Calendar.berlin.isDate(now, inSameDayAs: day), now > dayStart, now < dayEnd {
                        VStack(spacing: 0) {
                            Circle().fill(nowColor).frame(width: 8, height: 8)
                            Rectangle().fill(nowColor).frame(width: 2, height: 22)
                        }
                        .shadow(color: .black.opacity(0.3), radius: 1)
                        .offset(x: x(now, w) - 4, y: -4)
                    }
                }
            }
            .frame(height: 18)

            // Planned swim
            GeometryReader { geo in
                if plan.window?.areaName == area.name, let a = plan.swimStart, let b = plan.swimEnd,
                   Calendar.berlin.isDate(a, inSameDayAs: day) {
                    Capsule().fill(plan.status.color)
                        .frame(width: max(4, width(a, b, geo.size.width)), height: 4)
                        .offset(x: x(a, geo.size.width))
                }
            }
            .frame(height: 4)

            // Axis
            GeometryReader { geo in
                ForEach(ticks, id: \.self) { h in
                    Text(String(format: "%02d", h))
                        .font(.caption.monospacedDigit())
                        .opacity(0.6)
                        .fixedSize()
                        .position(x: CGFloat((Double(h) - startHour) / (endHour - startHour)) * geo.size.width, y: 6)
                }
            }
            .frame(height: 12)
        }
    }

    private var legend: some View {
        FlowLayout(spacing: 12) {
            legendItem(.public, "öffentlich")
            legendItem(.limited, "eingeschränkt")
            legendItem(.private, "Vereine")
            if areas.contains(where: { $0.1.contains { $0.kind == .restricted } }) {
                legendItem(.restricted, "Gruppen (z. B. Frauen)")
            }
            HStack(spacing: 4) {
                Circle().fill(nowColor).frame(width: 8, height: 8)
                Text("jetzt")
            }
            if plan.swimStart != nil {
                HStack(spacing: 4) {
                    Capsule().fill(plan.status.color).frame(width: 12, height: 4)
                    Text("Schwimmzeit")
                }
            }
        }
        .font(.caption)
        .opacity(0.8)
    }

    private func legendItem(_ kind: Slot.Kind, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color(for: kind)).frame(width: 10, height: 10)
            Text(title)
        }
        .fixedSize()
    }

    private let nowColor = Color(red: 1.0, green: 0.32, blue: 0.32)

    private func color(for kind: Slot.Kind) -> Color {
        switch kind {
        case .public: .white.opacity(0.92)
        case .limited: .white.opacity(0.55)
        case .restricted: Color(red: 0.55, green: 0.85, blue: 1.0).opacity(0.7)
        case .private: .white.opacity(0.2)
        }
    }

    private func frac(_ d: Date) -> CGFloat {
        CGFloat(min(max(d.timeIntervalSince(dayStart) / dayEnd.timeIntervalSince(dayStart), 0), 1))
    }

    private func x(_ d: Date, _ w: CGFloat) -> CGFloat { frac(d) * w }
    private func width(_ a: Date, _ b: Date, _ w: CGFloat) -> CGFloat { (frac(b) - frac(a)) * w }
}
