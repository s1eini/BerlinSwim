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
            return "morgen \(clock(d))"
        }
        let wd = d.formatted(Date.FormatStyle(timeZone: cal.timeZone).weekday(.abbreviated).locale(Locale(identifier: "de_DE")))
        return "\(wd) \(clock(d))"
    }

    /// "ab 16:00" today, "morgen ab 06:30", "Di ab 06:30".
    public static func dayFrom(_ d: Date, relativeTo now: Date = .now) -> String {
        let cal = Calendar.berlin
        if cal.isDate(d, inSameDayAs: now) { return "ab \(clock(d))" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(d, inSameDayAs: tomorrow) {
            return "morgen ab \(clock(d))"
        }
        let wd = d.formatted(Date.FormatStyle(timeZone: cal.timeZone).weekday(.abbreviated).locale(Locale(identifier: "de_DE")))
        return "\(wd) ab \(clock(d))"
    }

    public static func temperature(_ c: Double) -> String {
        String(format: "%.1f °C", c).replacingOccurrences(of: ".", with: ",")
    }
}

public extension SwimPlan.Status {
    var title: String {
        switch self {
        case .goNow: "Offen"
        case .later: "Später heute"
        case .tight: "Knapp"
        case .notToday: "Geschlossen"
        case .closed: "Geschlossen"
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
        switch status {
        case .goNow: closingSoon ? "noch \(Fmt.minutes(usableMinutes))" : swimEnd.map { "bis \(Fmt.clock($0))" }
        case .tight: "nur \(Fmt.minutes(usableMinutes))"
        case .later: window.map { "ab \(Fmt.clock($0.start))" }
        case .notToday, .closed: nextWindow.map { Fmt.dayFrom($0.start) }
        }
    }

    /// Two-line time used by widget rows and list cards: small caption + value,
    /// e.g. "offen bis" / "21:30", "noch" / "45 min", "nur noch" / "20 min", "Geschlossen" / "morgen ab 06:30".
    func timeLines(relativeTo now: Date = .now) -> (caption: String, value: String) {
        switch status {
        case .goNow where closingSoon: ("noch", Fmt.minutes(usableMinutes))
        case .goNow: ("offen bis", swimEnd.map(Fmt.clock) ?? "–")
        case .tight: ("nur noch", Fmt.minutes(usableMinutes))
        case .later: ("ab", window.map { Fmt.clock($0.start) } ?? "–")
        case .notToday, .closed: (status.title, nextWindow.map { Fmt.dayFrom($0.start, relativeTo: now) } ?? "")
        }
    }

    /// "Offen bis 21:30" – status and detail in one line.
    var statusLine: String {
        [status.title, statusDetail].compactMap { $0 }.joined(separator: " · ")
    }

    /// Extra advice that isn't already in the status line (detail header only).
    var hint: String? {
        switch status {
        case .goNow: closingSoon ? leaveBy.map { "Spätestens \(Fmt.clock($0)) losgehen" } : nil
        case .later:
            window.map { w in
                var s = "Los ab \(Fmt.clock(w.start.addingTimeInterval(-travel)))"
                if let leaveBy { s += ", spätestens \(Fmt.clock(leaveBy))" }
                return s
            }
        case .tight: swimEnd.map { "Badeschluss \(Fmt.clock($0)) – weniger als dein Training" }
        case .notToday, .closed: nil
        }
    }

    /// "Frauen bis 22:30" when a women-only session is the only option today.
    var womenOnlyText: String? {
        guard let w = womenOnlyToday else { return nil }
        return w.start > arrival ? "Frauen ab \(Fmt.clock(w.start))" : "Frauen bis \(Fmt.clock(w.end))"
    }

    /// True when you have to leave within the next 90 minutes to still get your training in.
    var closingSoon: Bool {
        guard status == .goNow, let leaveBy else { return false }
        let now = arrival.addingTimeInterval(-travel)
        return leaveBy.timeIntervalSince(now) < 90 * 60
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
                : [Color(red: 0.06, green: 0.40, blue: 0.74), Color(red: 0.05, green: 0.52, blue: 0.62)]
        case .later?, .tight?:
            return night ? [Color(red: 0.05, green: 0.12, blue: 0.30), Color(red: 0.12, green: 0.26, blue: 0.48)]
                : [Color(red: 0.16, green: 0.32, blue: 0.66), Color(red: 0.26, green: 0.44, blue: 0.70)]
        case .closed?, .notToday?:
            return [Color(red: 0.20, green: 0.24, blue: 0.32), Color(red: 0.34, green: 0.40, blue: 0.48)]
        case nil:
            return night ? [Color(red: 0.03, green: 0.10, blue: 0.24), Color(red: 0.05, green: 0.25, blue: 0.40)]
                : [Color(red: 0.08, green: 0.38, blue: 0.72), Color(red: 0.12, green: 0.50, blue: 0.66)]
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
        .background(.white.opacity(0.16), in: .capsule)
        .lineLimit(1)
        .fixedSize()
    }
}
