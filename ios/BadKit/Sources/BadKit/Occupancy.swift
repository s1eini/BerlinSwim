import Foundation
import SwiftUI

/// Live occupancy from berlinerbaeder.de/traffic/trafficdata.json (the same file the website's map loads).
public struct Occupancy: Sendable, Hashable {
    /// 1 green … 4 red; nil = unknown
    public var level: Int?
    /// Visitors counted right now (automatic counters only).
    public var count: Int?
    /// Threshold of the highest level ≈ capacity.
    public var capacity: Int?
    public var automatic: Bool

    public init(level: Int?, count: Int?, capacity: Int?, automatic: Bool) {
        self.level = level
        self.count = count
        self.capacity = capacity
        self.automatic = automatic
    }

    public var isKnown: Bool { level != nil }

    /// 0…1 when a live counter is available.
    public var fraction: Double? {
        guard let count, let capacity, capacity > 0 else { return nil }
        return min(1, Double(max(0, count)) / Double(capacity))
    }

    /// Level ≥ 3 (orange/red) counts as crowded.
    public var isCrowded: Bool { (level ?? 0) >= 3 }

    public var title: String {
        switch level {
        case 1?: "wenig los"
        case 2?: "mäßig voll"
        case 3?: "voll"
        case 4?: "sehr voll"
        default: "unbekannt"
        }
    }

    public var detail: String {
        if let f = fraction { return "\(title) · ca. \(Int((f * 100).rounded())) %" }
        return title
    }

    public var color: Color {
        switch level {
        case 1?: Color(red: 0.56, green: 0.75, blue: 0.43)
        case 2?: Color(red: 0.98, green: 0.78, blue: 0.31)
        case 3?: Color(red: 0.97, green: 0.59, blue: 0.12)
        case 4?: Color(red: 0.98, green: 0.25, blue: 0.27)
        default: .gray
        }
    }

    // MARK: Decoding

    private struct Row: Decodable {
        struct Threshold: Decodable { var level: Int; var threshold: Int }
        var id: String
        var level: Int?
        var counter: Int?
        var automatic: Bool?
        var thresholds: [Threshold]?
    }

    /// Parses the feed into [poolId: Occupancy]; entries with level -1 are dropped.
    public static func parse(_ data: Data) throws -> [Int: Occupancy] {
        let rows = try JSONDecoder().decode([Row].self, from: data)
        var out: [Int: Occupancy] = [:]
        for r in rows {
            guard let id = Int(r.id), let level = r.level, level > 0 else { continue }
            let automatic = r.automatic ?? false
            out[id] = Occupancy(
                level: min(level, 4),
                count: automatic ? r.counter.map { max(0, $0) } : nil,
                capacity: r.thresholds?.map(\.threshold).max(),
                automatic: automatic)
        }
        return out
    }
}

public actor OccupancyStore {
    public static let shared = OccupancyStore()
    public static let feedURL = URL(string: "https://www.berlinerbaeder.de/traffic/trafficdata.json")!

    private var cache: [Int: Occupancy] = [:]
    private var fetchedAt: Date?

    /// Fetches at most every `maxAge` seconds; on failure keeps the last values.
    public func current(maxAge: TimeInterval = 120) async -> [Int: Occupancy] {
        if let fetchedAt, Date().timeIntervalSince(fetchedAt) < maxAge { return cache }
        var request = URLRequest(url: Self.feedURL)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let (data, response) = try? await URLSession.shared.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let parsed = try? Occupancy.parse(data) {
            cache = parsed
            fetchedAt = Date()
        }
        return cache
    }
}

/// Small horizontal meter used in cards and detail.
public struct OccupancyMeter: View {
    let occupancy: Occupancy
    var compact: Bool

    public init(_ occupancy: Occupancy, compact: Bool = false) {
        self.occupancy = occupancy
        self.compact = compact
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.3.fill").font(.caption2)
            if let f = occupancy.fraction {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25))
                        Capsule().fill(occupancy.color).frame(width: max(4, geo.size.width * f))
                    }
                }
                .frame(width: compact ? 36 : 120, height: 6)
            } else {
                Circle().fill(occupancy.color).frame(width: 8, height: 8)
            }
            Text(compact ? occupancy.title : occupancy.detail)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Auslastung: \(occupancy.detail)")
    }
}
