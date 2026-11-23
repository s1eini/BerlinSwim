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
        case .notToday: "Heute nicht mehr"
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
        case .notToday: Color(white: 0.6)
        case .closed: Color(red: 1.0, green: 0.36, blue: 0.36)
        }
    }
}

public extension SwimPlan {
    /// Big headline value, e.g. "74 min" or "ab 16:00".
    var headline: String {
        switch status {
        case .goNow where usableMinutes >= 180: "bis \(swimEnd.map(Fmt.clock) ?? "–")"
        case .goNow, .tight: Fmt.minutes(usableMinutes)
        case .later: window.map { "ab \(Fmt.clock($0.start))" } ?? "–"
        case .notToday: nextWindow.map { Fmt.weekdayClock($0.start) } ?? "–"
        case .closed: "zu"
        }
    }

    /// One-line explanation under the headline.
    var subline: String {
        switch status {
        case .goNow:
            return closingSoon ? "los bis \(leaveBy.map(Fmt.clock) ?? "–") · noch \(Fmt.minutes(usableMinutes)) Wasserzeit" : ""
        case .later:
            guard let window else { return "" }
            let depart = window.start.addingTimeInterval(-travel)
            var s = "\(Fmt.minutes(usableMinutes)) möglich · los ab \(Fmt.clock(depart))"
            if let leaveBy { s += " (spätestens \(Fmt.clock(leaveBy)))" }
            return s
        case .tight:
            return "nur \(Fmt.minutes(usableMinutes)) bis \(swimEnd.map(Fmt.clock) ?? "–")"
        case .notToday:
            return nextWindow.map { "nächstes öffentl. Schwimmen \(Fmt.weekdayClock($0.start))" } ?? "keine Termine bekannt"
        case .closed:
            return closedReason ?? "geschlossen"
        }
    }

    /// True when you have to leave within the next 90 minutes to still get your training in.
    var closingSoon: Bool {
        guard status == .goNow, let leaveBy else { return false }
        let now = arrival.addingTimeInterval(-travel)
        return leaveBy.timeIntervalSince(now) < 90 * 60
    }

    var travelText: String {
        (travelIsEstimate ? "≈ " : "") + Fmt.travel(travel)
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
                : [Color(red: 0.10, green: 0.52, blue: 0.86), Color(red: 0.16, green: 0.78, blue: 0.80)]
        case .later?, .tight?:
            return night ? [Color(red: 0.05, green: 0.12, blue: 0.30), Color(red: 0.12, green: 0.26, blue: 0.48)]
                : [Color(red: 0.22, green: 0.42, blue: 0.80), Color(red: 0.42, green: 0.62, blue: 0.88)]
        case .closed?, .notToday?:
            return [Color(red: 0.20, green: 0.24, blue: 0.32), Color(red: 0.34, green: 0.40, blue: 0.48)]
        case nil:
            return night ? [Color(red: 0.03, green: 0.10, blue: 0.24), Color(red: 0.05, green: 0.25, blue: 0.40)]
                : [Color(red: 0.12, green: 0.45, blue: 0.85), Color(red: 0.30, green: 0.70, blue: 0.90)]
        }
    }
}
