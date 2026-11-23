import BadKit
import CoreLocation
import MapKit
import Observation
import SwiftUI
import WidgetKit

@MainActor
@Observable
final class AppModel {
    private(set) var feed: PoolsFeed?
    private(set) var plans: [SwimPlan] = []
    private(set) var now = Date()
    private(set) var location: CLLocation?
    private(set) var locationDenied = false
    private(set) var isRefreshing = false
    var errorMessage: String?
    /// Set by deep links / widget taps.
    var openPoolID: Int?

    var preferences: SwimPreferences {
        didSet {
            guard preferences != oldValue else { return }
            SharedState.save(preferences)
            if preferences.travelMode != oldValue.travelMode { Task { await updateRoutes() } }
            recompute()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    @ObservationIgnored private var routed: [String: TimeInterval] = SharedState.savedTravelTimes()
    @ObservationIgnored private var routedOrigin: CLLocation?
    @ObservationIgnored private var serviceSession: CLServiceSession?
    @ObservationIgnored private var started = false

    init() {
        preferences = SharedState.loadPreferences()
    }

    var pools: [Pool] { feed?.pools ?? [] }

    var origin: (lat: Double, lon: Double) {
        if let c = location?.coordinate { return (c.latitude, c.longitude) }
        if let l = SharedState.lastLocation() { return (l.lat, l.lon) }
        return Geo.berlinCenter
    }

    var travelTable: TravelTimeTable {
        TravelTimeTable(origin: origin, mode: preferences.travelMode, routed: routed)
    }

    func plan(for pool: Pool) -> SwimPlan {
        plans.first { $0.pool.id == pool.id }
            ?? SwimPlanner(preferences: preferences).plan(for: pool, now: now, travel: travelTable.travel(to: pool).0)
    }

    func isFavorite(_ pool: Pool) -> Bool { preferences.favorites.contains(pool.id) }

    func toggleFavorite(_ pool: Pool) {
        if preferences.favorites.contains(pool.id) {
            preferences.favorites.remove(pool.id)
        } else {
            preferences.favorites.insert(pool.id)
        }
    }

    // MARK: - Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        feed = await PoolStore.shared.cached()
        recompute()
        async let r: Void = refresh()
        async let l: Void = trackLocation()
        async let c: Void = tick()
        _ = await (r, l, c)
    }

    func refresh(force: Bool = false) async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            feed = try await PoolStore.shared.refresh(maxAge: force ? 0 : 10 * 60)
            errorMessage = nil
        } catch {
            errorMessage = feed == nil
                ? "Daten konnten nicht geladen werden."
                : "Offline – zeige Stand von \(Fmt.weekdayClock(feed!.generatedAt))."
        }
        recompute()
        WidgetCenter.shared.reloadAllTimelines()
        await updateRoutes()
    }

    /// Re-evaluate every 30 s so "noch X min" stays current.
    private func tick() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            now = Date()
            recompute()
        }
    }

    private func recompute() {
        now = Date()
        let table = travelTable
        plans = SwimPlanner(preferences: preferences).plans(for: pools, now: now) { table.travel(to: $0) }
    }

    // MARK: - Location

    private func trackLocation() async {
        serviceSession = CLServiceSession(authorization: .whenInUse)
        do {
            for try await update in CLLocationUpdate.liveUpdates(.otherNavigation) {
                if update.authorizationDenied || update.authorizationDeniedGlobally {
                    locationDenied = true
                    continue
                }
                guard let loc = update.location else { continue }
                locationDenied = false
                if let old = location, old.distance(from: loc) < 150 { continue }
                location = loc
                SharedState.saveLocation(.init(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, date: .now))
                recompute()
                if routedOrigin == nil || routedOrigin!.distance(from: loc) > 400 {
                    await updateRoutes()
                }
            }
        } catch {
            locationDenied = true
        }
    }

    // MARK: - Routing (MapKit ETA for the most relevant pools)

    private func updateRoutes() async {
        guard let origin = location else { return }
        let mode = preferences.travelMode
        let table = TravelTimeTable(origin: (origin.coordinate.latitude, origin.coordinate.longitude), mode: mode)
        let planner = SwimPlanner(preferences: preferences)
        // Route the nearest relevant pools (MapKit throttles ETA requests).
        let candidates = pools
            .filter { $0.hasCoordinate && planner.plan(for: $0, now: now, travel: 0).status != .closed }
            .sorted { (table.distance(to: $0) ?? .infinity) < (table.distance(to: $1) ?? .infinity) }
            .prefix(15)

        var fresh: [String: TimeInterval] = routedOrigin.map { $0.distance(from: origin) < 400 } == true ? routed : [:]
        for pool in candidates {
            let key = TravelTimeTable.key(pool.id, mode)
            if fresh[key] != nil { continue }
            if let eta = await RoutingService.eta(from: origin, to: pool, mode: mode) {
                fresh[key] = eta
            }
        }
        routed = fresh
        routedOrigin = origin
        SharedState.saveTravelTimes(fresh, at: .init(lat: origin.coordinate.latitude,
                                                     lon: origin.coordinate.longitude, date: .now))
        recompute()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

enum RoutingService {
    static func transportType(_ mode: TravelMode) -> MKDirectionsTransportType {
        switch mode {
        case .walking: .walking
        case .cycling: .cycling
        case .transit: .transit
        case .driving: .automobile
        }
    }

    @MainActor
    static func eta(from origin: CLLocation, to pool: Pool, mode: TravelMode) async -> TimeInterval? {
        guard let lat = pool.lat, let lon = pool.lon else { return nil }
        let request = MKDirections.Request()
        request.source = MKMapItem(location: origin, address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: lat, longitude: lon), address: nil)
        request.transportType = transportType(mode)
        request.departureDate = .now
        do {
            return try await MKDirections(request: request).calculateETA().expectedTravelTime
        } catch {
            return nil
        }
    }

    @MainActor
    static func openDirections(to pool: Pool, mode: TravelMode) {
        guard let lat = pool.lat, let lon = pool.lon else { return }
        let item = MKMapItem(location: CLLocation(latitude: lat, longitude: lon), address: nil)
        item.name = pool.name
        let launch: String = switch mode {
        case .walking: MKLaunchOptionsDirectionsModeWalking
        case .cycling: MKLaunchOptionsDirectionsModeCycling
        case .transit: MKLaunchOptionsDirectionsModeTransit
        case .driving: MKLaunchOptionsDirectionsModeDriving
        }
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: launch])
    }
}
