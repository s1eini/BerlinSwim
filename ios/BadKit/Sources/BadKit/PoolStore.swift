import Foundation

/// Shared between app and widget via the App Group container.
public enum SharedConfig {
    public static let appGroup = "group.de.eatbl.berlinswim"
    /// Overridable in Info.plist with key `PoolsFeedURL`.
    public static let defaultFeedURL = URL(string: "https://s1eini.github.io/BerlinSwim/pools.json")!

    public static var feedURL: URL {
        if let s = Bundle.main.object(forInfoDictionaryKey: "PoolsFeedURL") as? String,
           let url = URL(string: s), !s.isEmpty {
            return url
        }
        return defaultFeedURL
    }

    public static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return url
        }
        // Unsigned simulator builds have no app group: fall back to caches.
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }
}

/// Loads `pools.json` from network, caches it, and falls back to cache / bundled seed.
public actor PoolStore {
    public static let shared = PoolStore()

    private let cacheFile: URL
    private let session: URLSession
    private var memory: PoolsFeed?

    public init(cacheDirectory: URL = SharedConfig.containerURL, session: URLSession = .shared) {
        self.cacheFile = cacheDirectory.appendingPathComponent("pools.json")
        self.session = session
    }

    /// Cached feed (memory → disk → bundled seed), no network.
    public func cached() -> PoolsFeed? {
        if let memory { return memory }
        if let data = try? Data(contentsOf: cacheFile), let feed = try? PoolsFeed.decode(data) {
            memory = feed
            return feed
        }
        if let url = Bundle.main.url(forResource: "pools-seed", withExtension: "json"),
           let data = try? Data(contentsOf: url), let feed = try? PoolsFeed.decode(data) {
            memory = feed
            return feed
        }
        return nil
    }

    /// Fetches when the cache is older than `maxAge`; returns the best available feed.
    @discardableResult
    public func refresh(maxAge: TimeInterval = 15 * 60, from url: URL = SharedConfig.feedURL) async throws -> PoolsFeed {
        if let c = cached(), Date().timeIntervalSince(c.generatedAt) < maxAge {
            return c
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let feed = try PoolsFeed.decode(data)
            memory = feed
            try? data.write(to: cacheFile, options: .atomic)
            return feed
        } catch {
            if let c = cached() { return c }
            throw error
        }
    }
}

/// Small persistence helper for preferences and the last known location (for the widget).
public enum SharedState {
    private static let prefsKey = "swimPreferences"
    private static let locationKey = "lastLocation"

    public static func loadPreferences() -> SwimPreferences {
        guard let data = SharedConfig.defaults.data(forKey: prefsKey),
              let p = try? JSONDecoder().decode(SwimPreferences.self, from: data) else { return SwimPreferences() }
        return p
    }

    public static func save(_ p: SwimPreferences) {
        if let data = try? JSONEncoder().encode(p) { SharedConfig.defaults.set(data, forKey: prefsKey) }
    }

    public struct StoredLocation: Codable, Sendable {
        public var lat: Double
        public var lon: Double
        public var date: Date
        public init(lat: Double, lon: Double, date: Date) { self.lat = lat; self.lon = lon; self.date = date }
    }

    public static func lastLocation() -> StoredLocation? {
        guard let data = SharedConfig.defaults.data(forKey: locationKey) else { return nil }
        return try? JSONDecoder().decode(StoredLocation.self, from: data)
    }

    public static func saveLocation(_ l: StoredLocation) {
        if let data = try? JSONEncoder().encode(l) { SharedConfig.defaults.set(data, forKey: locationKey) }
    }

    /// Routed travel times computed by the app: key "<poolId>-<mode>".
    public static func savedTravelTimes() -> [String: TimeInterval] {
        SharedConfig.defaults.dictionary(forKey: "travelTimes") as? [String: TimeInterval] ?? [:]
    }

    public static func saveTravelTimes(_ t: [String: TimeInterval], at location: StoredLocation) {
        SharedConfig.defaults.set(t, forKey: "travelTimes")
        if let data = try? JSONEncoder().encode(location) { SharedConfig.defaults.set(data, forKey: "travelTimesOrigin") }
    }

    public static func travelTimesOrigin() -> StoredLocation? {
        guard let data = SharedConfig.defaults.data(forKey: "travelTimesOrigin") else { return nil }
        return try? JSONDecoder().decode(StoredLocation.self, from: data)
    }
}

public enum Geo {
    /// Haversine distance in meters.
    public static func distance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180, dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Berlin Alexanderplatz – default when no location is available.
    public static let berlinCenter = (lat: 52.5219, lon: 13.4132)
}

/// Travel time lookup combining routed ETAs (if fresh & from nearby origin) with straight-line estimates.
public struct TravelTimeTable: Sendable {
    public var origin: (lat: Double, lon: Double)
    public var mode: TravelMode
    public var routed: [String: TimeInterval]

    public init(origin: (lat: Double, lon: Double), mode: TravelMode, routed: [String: TimeInterval] = [:]) {
        self.origin = origin
        self.mode = mode
        self.routed = routed
    }

    public static func key(_ poolId: Int, _ mode: TravelMode) -> String { "\(poolId)-\(mode.rawValue)" }

    public func distance(to pool: Pool) -> Double? {
        guard let lat = pool.lat, let lon = pool.lon else { return nil }
        return Geo.distance(lat1: origin.lat, lon1: origin.lon, lat2: lat, lon2: lon)
    }

    /// (seconds, isEstimate)
    public func travel(to pool: Pool) -> (TimeInterval, Bool) {
        if let t = routed[Self.key(pool.id, mode)] { return (t, false) }
        guard let d = distance(to: pool) else { return (3600, true) }
        return (mode.estimate(distanceMeters: d), true)
    }
}
