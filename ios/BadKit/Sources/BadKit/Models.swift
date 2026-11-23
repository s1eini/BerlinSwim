import Foundation

/// Root of `pools.json` as produced by `scraper/scrape.py`.
public struct PoolsFeed: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var source: String
    public var pools: [Pool]

    public init(schemaVersion: Int = 1, generatedAt: Date, source: String = "", pools: [Pool]) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.source = source
        self.pools = pools
    }

    public static func decode(_ data: Data) throws -> PoolsFeed {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PoolsFeed.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

public struct Pool: Codable, Sendable, Identifiable, Hashable {
    public var id: Int
    public var slug: String
    public var name: String
    public var type: String?
    public var district: String?
    public var street: String?
    public var zip: String?
    public var lat: Double?
    public var lon: Double?
    public var url: URL
    public var ticketUrl: URL?
    public var closedNow: Bool
    public var category: Int?
    public var description: String?
    public var laneLength: Int?
    public var equipment: [String]
    public var accessibility: [String]
    public var extras: [String]
    public var transit: String?
    public var waterTempC: Double?
    public var waterTemps: [WaterTemp]
    /// Occupancy level 0...4 from the site's traffic feed (nil = unknown).
    public var traffic: Int?
    public var notices: [Notice]
    public var closures: [Closure]
    public var rules: Rules
    public var areas: [Area]

    public static func == (a: Pool, b: Pool) -> Bool { a.id == b.id }
    public func hash(into h: inout Hasher) { h.combine(id) }

    /// "Kombibad Seestraße - Hallenbad" -> "Kombibad Seestraße"
    public var shortName: String {
        name.replacingOccurrences(of: " - Hallenbad", with: "")
            .replacingOccurrences(of: "Schwimmhalle ", with: "")
            .replacingOccurrences(of: "Stadtbad ", with: "")
    }

    public var address: String {
        [street, [zip, "Berlin"].compactMap { $0 }.joined(separator: " ")]
            .compactMap { $0 }.joined(separator: ", ")
    }

    public var hasCoordinate: Bool { lat != nil && lon != nil }

    public var swimAreas: [Area] { areas.filter { $0.kind == .swim } }

    public var warnings: [Notice] { notices.filter { $0.severity != .info } }

    public func has(_ feature: Feature) -> Bool { feature.matches(self) }
}

public struct WaterTemp: Codable, Sendable, Hashable {
    public var basin: String
    public var tempC: Double
}

public struct Notice: Codable, Sendable, Hashable {
    public enum Severity: String, Codable, Sendable { case closed, warning, info }
    public var text: String
    public var severity: Severity
}

public struct Closure: Codable, Sendable, Hashable {
    public var dates: [String]
    public var reason: String
}

public struct Rules: Codable, Sendable, Hashable {
    public var entryCutoffMin: Int
    public var exitBeforeCloseMin: Int

    public init(entryCutoffMin: Int = 60, exitBeforeCloseMin: Int = 30) {
        self.entryCutoffMin = entryCutoffMin
        self.exitBeforeCloseMin = exitBeforeCloseMin
    }
}

public struct Area: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable { case swim, sauna, therapy }
    public var name: String
    public var kind: Kind
    public var laneLength: Int?
    public var slots: [Slot]
}

public struct Slot: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        /// regular public swimming
        case `public`
        /// public, but with reduced water area (lanes taken by clubs)
        case limited
        /// only for some groups (women, people with disabilities, ...)
        case restricted
        /// schools / clubs / courses only
        case `private`
    }

    public var start: Date
    public var end: Date
    public var kind: Kind
    public var label: String
    public var period: String

    public init(start: Date, end: Date, kind: Kind, label: String = "", period: String = "") {
        self.start = start
        self.end = end
        self.kind = kind
        self.label = label
        self.period = period
    }

    public var isOpenToEveryone: Bool { kind == .public || kind == .limited }
}

// MARK: - Features used for filters and chips

public enum Feature: String, CaseIterable, Codable, Sendable, Identifiable {
    case lane50, lane25, diving, sauna, nonSwimmer, toddler, slide, lawn, beach, food
    case accessible, waterLift

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lane50: "50 m"
        case .lane25: "25 m"
        case .diving: "Sprunganlage"
        case .sauna: "Sauna"
        case .nonSwimmer: "Nichtschwimmer"
        case .toddler: "Planschbecken"
        case .slide: "Rutsche"
        case .lawn: "Liegewiese"
        case .beach: "Sandstrand"
        case .food: "Imbiss"
        case .accessible: "Barrierefrei"
        case .waterLift: "Wasserlift"
        }
    }

    public var symbol: String {
        switch self {
        case .lane50, .lane25: "figure.pool.swim"
        case .diving: "figure.pool.swim.circle"
        case .sauna: "flame"
        case .nonSwimmer: "figure.and.child.holdinghands"
        case .toddler: "figure.2.and.child.holdinghands"
        case .slide: "water.waves.and.arrow.down"
        case .lawn: "leaf"
        case .beach: "beach.umbrella"
        case .food: "fork.knife"
        case .accessible: "figure.roll"
        case .waterLift: "figure.roll.runningpace"
        }
    }

    func matches(_ p: Pool) -> Bool {
        switch self {
        case .lane50: p.equipment.contains("50-m-Becken")
        case .lane25: p.equipment.contains("25-m-Becken")
        case .diving: p.equipment.contains("Sprunganlage")
        case .sauna: p.equipment.contains("Sauna") || p.areas.contains { $0.kind == .sauna }
        case .nonSwimmer: p.equipment.contains("Nichtschwimmerbecken")
        case .toddler: p.equipment.contains("Planschbecken")
        case .slide: p.equipment.contains("Wasserrutsche") || p.equipment.contains("Kinderrutsche")
        case .lawn: p.equipment.contains("Liegewiese")
        case .beach: p.equipment.contains("Sandstrand")
        case .food: p.equipment.contains("Imbiss")
        case .accessible: p.accessibility.contains { $0.hasPrefix("Barrierefreie") || $0.hasPrefix("Rampen") }
        case .waterLift: p.accessibility.contains("Wasserlift")
        }
    }
}
