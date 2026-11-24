import Foundation

public enum TravelMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case walking, cycling, transit, driving
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .walking: L("Zu Fuß")
        case .cycling: L("Fahrrad")
        case .transit: L("ÖPNV")
        case .driving: L("Auto")
        }
    }

    /// "Anreise mit ÖPNV", "Anreise zu Fuß"
    public var arrivalText: String {
        switch self {
        case .walking: L("Anreise zu Fuß")
        case .cycling: L("Anreise mit Rad")
        case .transit: L("Anreise mit ÖPNV")
        case .driving: L("Anreise mit Auto")
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
    /// Ignore "öffentl. Schwimmen mit eingeschränkter Wasserfläche" (default: it counts).
    public var onlyFullWaterArea: Bool = false
    public var requiredFeatures: Set<Feature> = []
    public var favorites: Set<Int> = []
    /// Below this many minutes a window isn't shown as "tight" anymore.
    public var minimumUsefulMinutes: Int = 20
    /// Hide pools whose live occupancy is orange/red.
    public var avoidCrowded: Bool = false
    /// Count women-only sessions ("Frauenschwimmen") as swimmable.
    public var includeWomenOnly: Bool = false
    /// Show pools that are closed for the season / long term.
    public var showOutOfService: Bool = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case trainingMinutes, changeMinutes, travelMode, minLaneLength, onlyFullWaterArea
        case requiredFeatures, favorites, minimumUsefulMinutes, avoidCrowded, includeWomenOnly, showOutOfService
    }

    /// Tolerant decoding: missing keys (older app versions) fall back to defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SwimPreferences()
        trainingMinutes = try c.decodeIfPresent(Int.self, forKey: .trainingMinutes) ?? d.trainingMinutes
        changeMinutes = try c.decodeIfPresent(Int.self, forKey: .changeMinutes) ?? d.changeMinutes
        travelMode = try c.decodeIfPresent(TravelMode.self, forKey: .travelMode) ?? d.travelMode
        minLaneLength = try c.decodeIfPresent(Int.self, forKey: .minLaneLength)
        // New key (old "includeLimited" is ignored on purpose: limited water area counts again by default).
        onlyFullWaterArea = try c.decodeIfPresent(Bool.self, forKey: .onlyFullWaterArea) ?? d.onlyFullWaterArea
        requiredFeatures = try c.decodeIfPresent(Set<Feature>.self, forKey: .requiredFeatures) ?? []
        favorites = try c.decodeIfPresent(Set<Int>.self, forKey: .favorites) ?? []
        minimumUsefulMinutes = try c.decodeIfPresent(Int.self, forKey: .minimumUsefulMinutes) ?? d.minimumUsefulMinutes
        avoidCrowded = try c.decodeIfPresent(Bool.self, forKey: .avoidCrowded) ?? d.avoidCrowded
        includeWomenOnly = try c.decodeIfPresent(Bool.self, forKey: .includeWomenOnly) ?? d.includeWomenOnly
        showOutOfService = try c.decodeIfPresent(Bool.self, forKey: .showOutOfService) ?? d.showOutOfService
        // The "50 m" filter used to be a feature; it's now the lane-length minimum.
        if requiredFeatures.remove(.lane50) != nil { minLaneLength = 50 }
        requiredFeatures.remove(.lane25)
    }
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
    /// Live occupancy, if the site reports one for this pool.
    public var occupancy: Occupancy?
    /// A women-only session still running/coming today that the plan does not count
    /// (because `includeWomenOnly` is off) – shown as a hint.
    public var womenOnlyToday: SwimWindow?
}

/// A run of back-to-back public slots in one area.
public struct SwimWindow: Sendable, Hashable {
    /// Which hall covers which part of the window (several when public swimming continues in another hall).
    public struct Part: Sendable, Hashable {
        public var areaName: String
        public var start: Date
        public var end: Date
    }

    /// First hall of the window.
    public var areaName: String
    public var laneLength: Int?
    public var start: Date
    public var end: Date
    public var kinds: Set<Slot.Kind>
    public var labels: [String]
    public var parts: [Part] = []

    public var isLimited: Bool { kinds.contains(.limited) }
    public var isWomenOnly: Bool { kinds.contains(.restricted) }
}

extension Slot {
    /// "Frauenschwimmen", "Frauen" – women-only sessions.
    var isWomenOnly: Bool { kind == .restricted && label.localizedCaseInsensitiveContains("frauen") }
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
        windows(for: pool) { s in
            s.kind == .public || (s.kind == .limited && !preferences.onlyFullWaterArea)
                || (preferences.includeWomenOnly && s.isWomenOnly)
        }
    }

    /// Merged women-only windows (used for the hint when they're not counted).
    public func womenOnlyWindows(for pool: Pool) -> [SwimWindow] {
        windows(for: pool) { $0.isWomenOnly }
    }

    private func windows(for pool: Pool, where include: (Slot) -> Bool) -> [SwimWindow] {
        var result: [SwimWindow] = []
        for area in pool.swimAreas {
            if let min = preferences.minLaneLength, (area.laneLength ?? 0) < min { continue }
            let slots = area.slots
                .filter(include)
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
        for i in result.indices {
            result[i].parts = [.init(areaName: result[i].areaName, start: result[i].start, end: result[i].end)]
        }
        return mergeAcrossHalls(result.sorted { ($0.start, $0.end) < ($1.start, $1.end) })
    }

    /// Public swimming that continues seamlessly in another hall with the same lane length
    /// (e.g. Seestraße: air dome until 16:00, indoor pool from 16:00) is one window for the swimmer.
    private func mergeAcrossHalls(_ windows: [SwimWindow]) -> [SwimWindow] {
        var merged: [SwimWindow] = []
        for w in windows {
            if var last = merged.last, w.laneLength == last.laneLength, w.start <= last.end {
                last.end = max(last.end, w.end)
                last.kinds.formUnion(w.kinds)
                last.labels += w.labels
                last.parts += w.parts
                merged[merged.count - 1] = last
            } else {
                merged.append(w)
            }
        }
        return merged
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
        if plan.status == .closed {
            // Closed today (Teamtag etc.): point to the next window on a day that isn't closed.
            let closedDays = Set(pool.closures.flatMap(\.dates))
            plan.nextWindow = all.first { $0.start > now && !closedDays.contains(calendar.dayString($0.start)) }
            return plan
        }
        if all.isEmpty {
            if pool.closedNow || pool.areas.isEmpty {
                plan.status = .closed
                plan.closedReason = pool.notices.first { $0.severity == .closed }?.text ?? L("Aktuell keine Öffnungszeiten")
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
        if !preferences.includeWomenOnly {
            plan.womenOnlyToday = womenOnlyWindows(for: pool).first {
                $0.end.addingTimeInterval(-cutoff) > now && calendar.isDate($0.start, inSameDayAs: now)
            }
        }
        plan.status = .notToday
        plan.nextWindow = all.first { $0.start >= endOfToday } ?? plan.nextWindow
        return plan
    }

    /// All plans, filtered by required features (and crowding) and sorted: status, then travel time.
    public func plans(for pools: [Pool], now: Date, occupancy: [Int: Occupancy] = [:],
                      travel: (Pool) -> (TimeInterval, Bool)) -> [SwimPlan] {
        pools
            .filter { pool in preferences.showOutOfService || !pool.isOutOfService }
            .filter { pool in
                guard let min = preferences.minLaneLength else { return true }
                return pool.swimAreas.contains { ($0.laneLength ?? 0) >= min }
            }
            .filter { pool in preferences.requiredFeatures.allSatisfy { pool.has($0) } }
            .filter { pool in !(preferences.avoidCrowded && occupancy[pool.id]?.isCrowded == true) }
            .map { pool in
                let (t, est) = travel(pool)
                var p = plan(for: pool, now: now, travel: t, travelIsEstimate: est)
                if let o = occupancy[pool.id], let reason = o.closedReason {
                    p.status = .closed
                    p.closedReason = reason
                    p.leaveBy = nil
                    // Closed right now (weather / operations): next chance is another day.
                    let tomorrow = calendar.startOfDay(for: now).addingTimeInterval(26 * 3600)
                    p.nextWindow = windows(for: pool).first { $0.start >= calendar.startOfDay(for: tomorrow) }
                } else {
                    p.occupancy = occupancy[pool.id]
                }
                return p
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
