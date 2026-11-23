import Foundation

public enum TravelMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case walking, cycling, transit, driving
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .walking: "Zu Fuß"
        case .cycling: "Fahrrad"
        case .transit: "ÖPNV"
        case .driving: "Auto"
        }
    }

    public var symbol: String {
        switch self {
        case .walking: "figure.walk"
        case .cycling: "bicycle"
        case .transit: "tram.fill"
        case .driving: "car.fill"
        }
    }

    /// Rough fallback when no routed ETA is available: (km/h on straight-line distance, fixed overhead minutes).
    var estimateParameters: (speed: Double, overhead: Double) {
        switch self {
        case .walking: (3.8, 0)
        case .cycling: (13, 2)
        case .transit: (14, 8)
        case .driving: (20, 6)
        }
    }

    /// Straight-line based travel time estimate in seconds.
    public func estimate(distanceMeters: Double) -> TimeInterval {
        let p = estimateParameters
        return (distanceMeters / 1000 / p.speed * 60 + p.overhead) * 60
    }
}

public struct SwimPreferences: Codable, Sendable, Equatable {
    public var trainingMinutes: Int = 60
    /// Time from arrival to being in the water (ticket, changing, shower).
    public var changeMinutes: Int = 15
    public var travelMode: TravelMode = .transit
    /// Only areas with at least this lane length (nil = any).
    public var minLaneLength: Int? = nil
    /// Count "öffentl. Schwimmen mit eingeschränkter Wasserfläche" as swimmable.
    public var includeLimited: Bool = true
    public var requiredFeatures: Set<Feature> = []
    public var favorites: Set<Int> = []
    /// Below this many minutes a window isn't shown as "tight" anymore.
    public var minimumUsefulMinutes: Int = 20

    public init() {}
}

public struct SwimPlan: Sendable, Identifiable, Hashable {
    public enum Status: Int, Sendable, Comparable, Hashable {
        /// You can leave now and get your full training in.
        case goNow = 0
        /// Public swimming starts later today and the full training fits.
        case later = 1
        /// Reachable, but less time than the desired training.
        case tight = 2
        /// Nothing usable today.
        case notToday = 3
        /// Closed (season, notice, closure).
        case closed = 4

        public static func < (a: Status, b: Status) -> Bool { a.rawValue < b.rawValue }
    }

    public var id: Int { pool.id }
    public var pool: Pool
    public var status: Status
    public var travel: TimeInterval
    public var travelIsEstimate: Bool
    public var arrival: Date
    /// The (merged) public window the plan refers to.
    public var window: SwimWindow?
    /// When you'd actually be in the water.
    public var swimStart: Date?
    /// Badeschluss (must leave the water).
    public var swimEnd: Date?
    public var usableMinutes: Int
    /// Latest departure that still allows the full training (nil if not possible).
    public var leaveBy: Date?
    /// Next window when nothing fits today.
    public var nextWindow: SwimWindow?
    public var closedReason: String?

    public static func == (a: SwimPlan, b: SwimPlan) -> Bool {
        a.pool.id == b.pool.id && a.status == b.status && a.usableMinutes == b.usableMinutes && a.travel == b.travel
    }
    public func hash(into h: inout Hasher) { h.combine(pool.id) }
}

/// A run of back-to-back public slots in one area.
public struct SwimWindow: Sendable, Hashable {
    public var areaName: String
    public var laneLength: Int?
    public var start: Date
    public var end: Date
    public var kinds: Set<Slot.Kind>
    public var labels: [String]

    public var isLimited: Bool { kinds.contains(.limited) }
}

public struct SwimPlanner: Sendable {
    public var preferences: SwimPreferences
    public var calendar: Calendar

    public init(preferences: SwimPreferences, calendar: Calendar = .berlin) {
        self.preferences = preferences
        self.calendar = calendar
    }

    /// Merged public windows of a pool, sorted by start.
    public func windows(for pool: Pool) -> [SwimWindow] {
        var result: [SwimWindow] = []
        for area in pool.swimAreas {
            if let min = preferences.minLaneLength, (area.laneLength ?? 0) < min { continue }
            let slots = area.slots
                .filter { $0.kind == .public || ($0.kind == .limited && preferences.includeLimited) }
                .sorted { $0.start < $1.start }
            var current: SwimWindow?
            for s in slots {
                if var c = current, s.start <= c.end {
                    c.end = max(c.end, s.end)
                    c.kinds.insert(s.kind)
                    c.labels.append(s.label)
                    current = c
                } else {
                    if let c = current { result.append(c) }
                    current = SwimWindow(areaName: area.name, laneLength: area.laneLength, start: s.start,
                                         end: s.end, kinds: [s.kind], labels: [s.label])
                }
            }
            if let c = current { result.append(c) }
        }
        return result.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    public func plan(for pool: Pool, now: Date, travel: TimeInterval, travelIsEstimate: Bool = false) -> SwimPlan {
        let arrival = now.addingTimeInterval(travel)
        var plan = SwimPlan(pool: pool, status: .notToday, travel: travel, travelIsEstimate: travelIsEstimate,
                            arrival: arrival, usableMinutes: 0)

        let today = calendar.dayString(now)
        if let closure = pool.closures.first(where: { $0.dates.contains(today) }) {
            plan.status = .closed
            plan.closedReason = closure.reason
        }

        let all = windows(for: pool)
        plan.nextWindow = all.first { $0.end > now }
        if plan.status == .closed { return plan }
        if all.isEmpty {
            if pool.closedNow || pool.areas.isEmpty {
                plan.status = .closed
                plan.closedReason = pool.notices.first { $0.severity == .closed }?.text ?? "Aktuell keine Öffnungszeiten"
            }
            return plan
        }

        let training = TimeInterval(preferences.trainingMinutes * 60)
        let change = TimeInterval(preferences.changeMinutes * 60)
        let cutoff = TimeInterval(pool.rules.entryCutoffMin * 60)
        let exitBefore = TimeInterval(pool.rules.exitBeforeCloseMin * 60)
        let endOfToday = calendar.startOfDay(for: now).addingTimeInterval(26 * 3600) // includes late-night slots

        var best: SwimPlan?
        var tight: SwimPlan?
        for w in all where w.end > now && w.start < endOfToday {
            let entryBy = w.end.addingTimeInterval(-cutoff)
            let swimEnd = w.end.addingTimeInterval(-exitBefore)
            let enter = max(arrival, w.start)
            guard enter <= entryBy else { continue }
            let inWater = enter.addingTimeInterval(change)
            let usable = swimEnd.timeIntervalSince(inWater)
            var candidate = plan
            candidate.window = w
            candidate.swimStart = inWater
            candidate.swimEnd = swimEnd
            candidate.usableMinutes = max(0, Int(usable / 60))
            if usable >= training {
                // latest moment you may leave and still get the full training + respect entry cutoff
                let latestEnter = min(entryBy, swimEnd.addingTimeInterval(-training - change))
                candidate.leaveBy = latestEnter.addingTimeInterval(-travel)
                candidate.status = w.start <= arrival ? .goNow : .later
                best = candidate
                break
            } else if usable >= TimeInterval(preferences.minimumUsefulMinutes * 60), tight == nil {
                candidate.status = .tight
                tight = candidate
            }
        }
        if let best { return best }
        if let tight { return tight }
        plan.status = .notToday
        plan.nextWindow = all.first { $0.start >= endOfToday } ?? plan.nextWindow
        return plan
    }

    /// All plans, filtered by required features and sorted: status, then travel time.
    public func plans(for pools: [Pool], now: Date, travel: (Pool) -> (TimeInterval, Bool)) -> [SwimPlan] {
        pools
            .filter { pool in preferences.requiredFeatures.allSatisfy { pool.has($0) } }
            .map { pool in
                let (t, est) = travel(pool)
                return plan(for: pool, now: now, travel: t, travelIsEstimate: est)
            }
            .sorted { a, b in
                if a.status != b.status { return a.status < b.status }
                if a.status == .later, let sa = a.window?.start, let sb = b.window?.start, sa != sb { return sa < sb }
                return a.travel < b.travel
            }
    }
}

public extension Calendar {
    static let berlin: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.locale = Locale(identifier: "de_DE")
        return c
    }()

    func dayString(_ date: Date) -> String {
        let c = dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
