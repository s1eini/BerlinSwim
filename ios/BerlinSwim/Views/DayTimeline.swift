import BadKit
import SwiftUI

/// Horizontal bars per area for one day: public (bright), limited (striped-ish), restricted/private (dim),
/// with a "now" marker and the user's planned swim window.
struct DayTimeline: View {
    let pool: Pool
    let day: Date
    let now: Date
    let plan: SwimPlan

    private var dayStart: Date { Calendar.berlin.startOfDay(for: day).addingTimeInterval(6 * 3600) }
    private var dayEnd: Date { Calendar.berlin.startOfDay(for: day).addingTimeInterval(23 * 3600) }

    private var areas: [(Area, [Slot])] {
        pool.areas.compactMap { a in
            let s = a.slots.filter { $0.end > dayStart && $0.start < dayEnd }
            return s.isEmpty ? nil : (a, s)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if areas.isEmpty {
                Text(plan.status == .closed ? plan.subline : "Heute keine Öffnungszeiten.")
                    .font(.subheadline).opacity(0.85)
            }
            ForEach(areas, id: \.0.name) { area, slots in
                VStack(alignment: .leading, spacing: 4) {
                    Text(area.name + (area.laneLength.map { " · \($0) m" } ?? ""))
                        .font(.caption.weight(.semibold)).opacity(0.85)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.08))
                            ForEach(slots, id: \.self) { s in
                                Capsule()
                                    .fill(color(for: s.kind))
                                    .frame(width: max(3, width(s.start, s.end, geo.size.width)))
                                    .offset(x: x(s.start, geo.size.width))
                            }
                            if plan.window?.areaName == area.name, let a = plan.swimStart, let b = plan.swimEnd,
                               Calendar.berlin.isDate(a, inSameDayAs: day) {
                                Capsule()
                                    .stroke(.white, lineWidth: 2)
                                    .frame(width: max(3, width(a, b, geo.size.width)), height: 18)
                                    .offset(x: x(a, geo.size.width))
                            }
                            if Calendar.berlin.isDate(now, inSameDayAs: day), now > dayStart, now < dayEnd {
                                Rectangle().fill(.white).frame(width: 2, height: 26)
                                    .offset(x: x(now, geo.size.width))
                            }
                        }
                    }
                    .frame(height: 14)
                    .padding(.vertical, 6)
                    ForEach(slots, id: \.self) { s in
                        HStack {
                            Circle().fill(color(for: s.kind)).frame(width: 8, height: 8)
                            Text("\(Fmt.clock(s.start))–\(Fmt.clock(s.end))").monospacedDigit()
                            Text(s.label).lineLimit(1).opacity(0.8)
                        }
                        .font(.caption)
                    }
                }
            }
            HStack {
                ForEach(["6", "10", "14", "18", "22"], id: \.self) { Text($0).frame(maxWidth: .infinity) }
            }
            .font(.caption2).opacity(0.6)
        }
    }

    private func color(for kind: Slot.Kind) -> Color {
        switch kind {
        case .public: .white.opacity(0.9)
        case .limited: .white.opacity(0.6)
        case .restricted: .cyan.opacity(0.5)
        case .private: .white.opacity(0.18)
        }
    }

    private func frac(_ d: Date) -> CGFloat {
        CGFloat(min(max(d.timeIntervalSince(dayStart) / dayEnd.timeIntervalSince(dayStart), 0), 1))
    }

    private func x(_ d: Date, _ w: CGFloat) -> CGFloat { frac(d) * w }
    private func width(_ a: Date, _ b: Date, _ w: CGFloat) -> CGFloat { (frac(b) - frac(a)) * w }
}
