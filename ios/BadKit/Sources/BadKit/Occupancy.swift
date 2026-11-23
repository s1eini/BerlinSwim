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
    /// Set when the site reports level -2/-3 (closed for weather / operational reasons).
    public var closedReason: String?

    public init(level: Int?, count: Int?, capacity: Int?, automatic: Bool, closedReason: String? = nil) {
        self.level = level
        self.count = count
        self.capacity = capacity
        self.automatic = automatic
        self.closedReason = closedReason
    }

    public var isKnown: Bool { level != nil }
    public var isClosed: Bool { closedReason != nil }

    /// 0…1 when a live counter is available.
    public var fraction: Double? {
        guard let count, let capacity, capacity > 0 else { return nil }
        return min(1, Double(max(0, count)) / Double(capacity))
    }

    /// Level ≥ 3 (orange/red) counts as crowded.
    public var isCrowded: Bool { (level ?? 0) >= 3 }

    /// Same wording as berlinerbaeder.de.
    public var title: String {
        switch level {
        case 1?: L("Geringe Auslastung")
        case 2?: L("Mittlere Auslastung")
        case 3?: L("Erhöhte Auslastung")
        case 4?: L("Maximale Auslastung")
        default: closedReason ?? L("unbekannt")
        }
    }

    public var shortTitle: String {
        switch level {
        case 1?: L("gering")
        case 2?: L("mittel")
        case 3?: L("erhöht")
        case 4?: L("voll")
        default: "–"
        }
    }

    public var detail: String { title }

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
            guard let id = Int(r.id), let level = r.level else { continue }
            if level == -2 || level == -3 {
                out[id] = Occupancy(level: nil, count: nil, capacity: nil, automatic: false,
                                    closedReason: level == -2 ? L("Wetterbedingt geschlossen") : L("Betriebsbedingt geschlossen"))
                continue
            }
            guard level > 0 else { continue }
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
    /// Last fetch/parse error, for debugging.
    public private(set) var lastError: Error?

    /// Fetches at most every `maxAge` seconds; on failure keeps the last values.
    public func current(maxAge: TimeInterval = 120) async -> [Int: Occupancy] {
        if let fetchedAt, Date().timeIntervalSince(fetchedAt) < maxAge { return cache }
        var request = URLRequest(url: Self.feedURL)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            cache = try Occupancy.parse(data)
            fetchedAt = Date()
        } catch {
            lastError = error
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
            Text(compact ? occupancy.shortTitle : occupancy.detail)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Auslastung: \(occupancy.detail)"))
    }
}
