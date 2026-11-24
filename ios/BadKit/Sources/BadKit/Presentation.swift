import Foundation
import SwiftUI

public enum Fmt {
    /// Always "HH:mm" (06:30), so columns of times line up.
    public static func clock(_ d: Date) -> String {
        let c = Calendar.berlin.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    public static func range(_ a: Date, _ b: Date) -> String { "\(clock(a))–\(clock(b))" }

    /// 74 -> "1 h 14 min", 45 -> "45 min"
    public static func minutes(_ m: Int) -> String {
        if m < 60 { return "\(m) min" }
        let h = m / 60, r = m % 60
        return r == 0 ? "\(h) h" : "\(h) h \(r) min"
    }

    public static func travel(_ t: TimeInterval) -> String {
        minutes(max(1, Int((t / 60).rounded())))
    }

    public static func weekdayClock(_ d: Date, relativeTo now: Date = .now) -> String {
        let cal = Calendar.berlin
        if cal.isDate(d, inSameDayAs: now) { return clock(d) }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(d, inSameDayAs: tomorrow) {
            return L("morgen \(clock(d))")
        }
        let wd = d.formatted(Date.FormatStyle(timeZone: cal.timeZone).weekday(.abbreviated).locale(.autoupdatingCurrent))
        return "\(wd) \(clock(d))"
    }

    /// "ab 16:00" today, "morgen ab 06:30", "Di ab 06:30".
    /// "07:45–18:00 Uhr" in German, plain range in English.
    public static func rangeUhr(_ a: Date, _ b: Date) -> String { L("\(range(a, b)) Uhr") }

    /// "öffnet um 18:00 Uhr" today, "öffnet morgen um 06:00 Uhr", "öffnet Donnerstag um 06:00 Uhr".
    public static func opens(_ d: Date, relativeTo now: Date = .now) -> String {
        let cal = Calendar.berlin, time = clock(d)
        if cal.isDate(d, inSameDayAs: now) { return L("öffnet um \(time) Uhr") }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(d, inSameDayAs: tomorrow) {
            return L("öffnet morgen um \(time) Uhr")
        }
        let weekday = d.formatted(Date.FormatStyle(timeZone: cal.timeZone).weekday(.wide).locale(.autoupdatingCurrent))
        return L("öffnet \(weekday) um \(time) Uhr")
    }

    public static func dayFrom(_ d: Date, relativeTo now: Date = .now, clock: (Date) -> String = Fmt.clock) -> String {
        let cal = Calendar.berlin
        if cal.isDate(d, inSameDayAs: now) { return L("ab \(clock(d))") }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(d, inSameDayAs: tomorrow) {
            return L("morgen ab \(clock(d))")
        }
        let wd = d.formatted(Date.FormatStyle(timeZone: cal.timeZone).weekday(.abbreviated).locale(.autoupdatingCurrent))
        return L("\(wd) ab \(clock(d))")
    }

    public static func temperature(_ c: Double) -> String {
        c.formatted(.number.precision(.fractionLength(1)).locale(.autoupdatingCurrent)) + " °C"
    }
}

public extension SwimPlan.Status {
    var title: String {
        switch self {
        case .goNow: L("Offen")
        case .later: L("Später heute")
        case .tight: L("Knapp")
        case .notToday: L("Geschlossen")
        case .closed: L("Geschlossen")
        }
    }

    var symbol: String {
        switch self {
        case .goNow: "checkmark.circle.fill"
        case .later: "clock.fill"
        case .tight: "exclamationmark.circle.fill"
        case .notToday: "moon.zzz.fill"
        case .closed: "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .goNow: Color(red: 0.20, green: 0.78, blue: 0.47)
        case .later: Color(red: 0.25, green: 0.62, blue: 1.0)
        case .tight: Color(red: 1.0, green: 0.72, blue: 0.20)
        case .notToday, .closed: Color(white: 0.6)
        }
    }
}

public extension SwimPlan {
    /// Short value next to / under the status, e.g. "bis 21:30", "noch 45 min", "ab 16:00", "morgen ab 06:30".
    var statusDetail: String? {
        let clock = Fmt.clock
        return switch status {
        case .goNow: closingSoon ? L("noch \(Fmt.minutes(usableMinutes))") : swimEnd.map { L("bis \(clock($0))") }
        case .tight: L("nur \(Fmt.minutes(usableMinutes))")
        case .later: window.map { L("ab \(clock($0.start))") }
        case .notToday, .closed: nextWindow.map { Fmt.dayFrom($0.start, relativeTo: plannedAt) }
        }
    }

    /// Two-line time used by widget rows and list cards: small caption + value,
    /// e.g. "schwimmen bis" / "21:30", "Schwimmzeit" / "45 min", "nur noch" / "20 min", "Geschlossen" / "morgen ab 06:30".
    func timeLines(relativeTo now: Date? = nil) -> (caption: String, value: String) {
        let now = now ?? plannedAt
        return switch status {
        case .goNow where closingSoon: (L("Schwimmzeit"), Fmt.minutes(usableMinutes))
        case .goNow: (L("schwimmen bis"), swimEnd.map(Fmt.clock) ?? "–") // Badeschluss, not closing time
        case .tight: (L("nur noch"), Fmt.minutes(usableMinutes))
        case .later: (L("öffnet"), window.map { Fmt.clock($0.start) } ?? "–")
        case .notToday, .closed: (status.title, nextWindow.map { Fmt.dayFrom($0.start, relativeTo: now) } ?? "")
        }
    }

    /// The status as one natural sentence (detail header, search list), with full-sentence
    /// translations so word order can differ per language:
    /// "Offen bis 21:30 Uhr", "Noch 1 h 15 min geöffnet", "Geschlossen, morgen ab 06:30 Uhr" …
    var statusSentence: String {
        switch status {
        case .goNow where closingSoon:
            return L("Noch \(Fmt.minutes(usableMinutes)) Schwimmzeit")
        case .goNow:
            return swimEnd.map { L("Schwimmen bis \(Fmt.clock($0)) Uhr") } ?? status.title
        case .tight:
            return L("Nur noch \(Fmt.minutes(usableMinutes)) Schwimmzeit")
        case .later:
            return window.map { L("Öffnet um \(Fmt.clock($0.start)) Uhr") } ?? status.title
        case .notToday, .closed:
            guard let next = nextWindow?.start else { return L("Geschlossen") }
            let cal = Calendar.berlin, time = Fmt.clock(next)
            if cal.isDate(next, inSameDayAs: plannedAt) { return L("Geschlossen, ab \(time) Uhr wieder offen") }
            if let tomorrow = cal.date(byAdding: .day, value: 1, to: plannedAt), cal.isDate(next, inSameDayAs: tomorrow) {
                return L("Geschlossen, morgen ab \(time) Uhr")
            }
            let weekday = next.formatted(Date.FormatStyle(timeZone: cal.timeZone).weekday(.wide).locale(.autoupdatingCurrent))
            return L("Geschlossen, \(weekday) ab \(time) Uhr")
        }
    }

    /// Extra advice that isn't already in the status line (detail header only).
    var hint: String? {
        if !travelKnown {
            // No location: no "leave by" advice; only when you must be there at the latest.
            guard status == .goNow, closingSoon, let leaveBy else { return nil }
            return L("Spätestens um \(Fmt.clock(leaveBy)) Uhr dort sein")
        }
        return switch status {
        case .goNow: closingSoon ? leaveBy.map { L("Spätestens \(Fmt.clock($0)) losgehen") } : nil
        case .later:
            window.map { w in
                var s = L("Los ab \(Fmt.clock(w.start.addingTimeInterval(-travel)))")
                if let leaveBy { s += L(", spätestens \(Fmt.clock(leaveBy))") }
                return s
            }
        case .tight: swimEnd.map { L("Badeschluss \(Fmt.clock($0)) – weniger als dein Training") }
        case .notToday, .closed: nil
        }
    }

    /// "Frauen bis 22:30" when a women-only session is the only option today.
    var womenOnlyText: String? {
        guard let w = womenOnlyToday else { return nil }
        return w.start > arrival ? L("Frauen ab \(Fmt.clock(w.start))") : L("Frauen bis \(Fmt.clock(w.end))")
    }

    /// True when you have to leave within the next 90 minutes to still get your training in.
    /// The moment this plan was computed for ("now" of the planner), not the wall clock.
    var plannedAt: Date { arrival.addingTimeInterval(-travel) }

    var closingSoon: Bool {
        guard status == .goNow, let leaveBy else { return false }
        return leaveBy.timeIntervalSince(plannedAt) < 90 * 60
    }

    var travelText: String {
        Fmt.travel(travel)
    }
}

/// Water-ish gradient used as background (weather-app style), depending on status and time of day.
public struct WaterBackground: View {
    var status: SwimPlan.Status?
    var date: Date

    public init(status: SwimPlan.Status?, date: Date = .now) {
        self.status = status
        self.date = date
    }

    public var body: some View {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private var colors: [Color] {
        let hour = Calendar.berlin.component(.hour, from: date)
        let night = hour < 6 || hour >= 20
        switch status {
        case .goNow?:
            return night ? [Color(red: 0.02, green: 0.18, blue: 0.32), Color(red: 0.03, green: 0.38, blue: 0.45)]
                : [Color(red: 0.04, green: 0.31, blue: 0.62), Color(red: 0.02, green: 0.34, blue: 0.46)] // measured ≥ 5:1 for white text (glass lightens)
        case .later?, .tight?:
            return night ? [Color(red: 0.05, green: 0.12, blue: 0.30), Color(red: 0.12, green: 0.26, blue: 0.48)]
                : [Color(red: 0.12, green: 0.25, blue: 0.55), Color(red: 0.18, green: 0.32, blue: 0.56)]
        case .closed?, .notToday?:
            return [Color(red: 0.18, green: 0.21, blue: 0.28), Color(red: 0.27, green: 0.32, blue: 0.39)]
        case nil:
            return night ? [Color(red: 0.03, green: 0.10, blue: 0.24), Color(red: 0.05, green: 0.25, blue: 0.40)]
                : [Color(red: 0.05, green: 0.30, blue: 0.60), Color(red: 0.06, green: 0.36, blue: 0.48)]
        }
    }
}

/// Small capsule for facts (travel time, lane, temperature, occupancy, notice) – used by app cards and widget.
public struct FactChip: View {
    let text: String
    let symbol: String?
    /// Color of the symbol (e.g. occupancy level); white by default.
    let tint: Color?
    /// Smaller variant for widgets.
    let compact: Bool

    public init(text: String, symbol: String? = nil, tint: Color? = nil, compact: Bool = false) {
        self.text = text
        self.symbol = symbol
        self.tint = tint
        self.compact = compact
    }

    public var body: some View {
        HStack(spacing: compact ? 3 : 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small).foregroundStyle(tint ?? .white) }
            Text(text)
        }
        .font((compact ? Font.caption2 : Font.caption).weight(.medium).monospacedDigit())
        .padding(.horizontal, compact ? 6 : 8).padding(.vertical, compact ? 2 : 4)
        .background(.black.opacity(0.18), in: .capsule) // darker than the card keeps white text ≥ 4.5:1
        // Widget chips stay on one line; in the app they may wrap at very large text sizes.
        .lineLimit(compact ? 1 : nil)
        .fixedSize(horizontal: compact, vertical: true)
    }
}
