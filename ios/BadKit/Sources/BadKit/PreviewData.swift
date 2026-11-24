#if DEBUG
import Foundation

/// Sample data for Xcode canvas previews (app and widget).
/// Uses the bundled `pools-seed.json` and a fixed clock on the seed's day, so previews stay
/// meaningful no matter when you open them.
public enum PreviewData {
    public static let feed: PoolsFeed? = {
        guard let url = Bundle.main.url(forResource: "pools-seed", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? PoolsFeed.decode(data)
    }()

    public static var pools: [Pool] { feed?.pools ?? [] }

    /// The seed's day at `hour:minute` Berlin time (default 17:30 – most indoor pools open).
    public static func now(hour: Int = 17, minute: Int = 30) -> Date {
        let day = Calendar.berlin.startOfDay(for: feed?.generatedAt ?? .now)
        return Calendar.berlin.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    /// Alexanderplatz-ish origin.
    public static let origin = (lat: 52.5219, lon: 13.4132)

    /// Plausible occupancy for a handful of pools so every level shows up somewhere.
    public static var occupancy: [Int: Occupancy] {
        let levels = [1, 2, 3, 1, 4, 2, 1, 3]
        var out: [Int: Occupancy] = [:]
        for (pool, level) in zip(pools.filter { !$0.isOutOfService }, levels) {
            out[pool.id] = Occupancy(level: level, count: nil, capacity: nil, automatic: false)
        }
        return out
    }

    public static func plans(preferences: SwimPreferences = SwimPreferences(),
                             now: Date = PreviewData.now(), location: Bool = true) -> [SwimPlan] {
        let table = TravelTimeTable(origin: origin, mode: preferences.travelMode)
        return SwimPlanner(preferences: preferences).plans(for: pools, now: now, occupancy: occupancy,
                                                           travelKnown: location) {
            table.travel(to: $0)
        }
    }

    /// First plan with the given status (handy to preview a single card / detail state).
    public static func plan(_ status: SwimPlan.Status, preferences: SwimPreferences = SwimPreferences(),
                            now: Date = PreviewData.now()) -> SwimPlan? {
        var prefs = preferences
        prefs.showOutOfService = true
        return plans(preferences: prefs, now: now).first { $0.status == status }
    }
}
#endif
