import BadKit
import CoreLocation
import MapKit
import Observation
import SwiftUI
import WidgetKit

import os

private let log = Logger(subsystem: "de.eatbl.BerlinSwim", category: "model")

@MainActor
@Observable
final class AppModel {
    private(set) var feed: PoolsFeed?
    private(set) var plans: [SwimPlan] = []
    /// All pools, ignoring the list filters (features, "Nicht voll") – used by search.
    private(set) var allPlans: [SwimPlan] = []
    private(set) var now = Date()
    private(set) var location: CLLocation?
    /// Live occupancy by pool id (only pools the site reports).
    private(set) var occupancy: [Int: Occupancy] = [:]
    private(set) var locationDenied = false
    private(set) var isRefreshing = false
    var errorMessage: String?
    /// Set by deep links / widget taps.
    var openPoolID: Int?
    /// Navigation path of the "Bäder" tab (deep links push here).
    var poolPath: [Pool] = []

    var preferences: SwimPreferences {
        didSet {
            guard preferences != oldValue else { return }
            guard fixedNow == nil else { recompute(); return } // preview: don't persist or route
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
    /// Frozen clock for previews.
    @ObservationIgnored private var fixedNow: Date?
    /// Previews: fixed origin (`nil` = no location).
    @ObservationIgnored private var previewOrigin: (lat: Double, lon: Double)??

    init() {
        preferences = SharedState.loadPreferences()
    }

    var pools: [Pool] { feed?.pools ?? [] }

    /// Travel times only make sense with a real position: live location, or a stored one
    /// as long as access isn't denied. Otherwise the app works on opening times only.
    var travelKnown: Bool {
        if let previewOrigin { return previewOrigin != nil }
        return !locationDenied && (location != nil || SharedState.lastLocation() != nil)
    }

    var origin: (lat: Double, lon: Double) {
        if let p = previewOrigin, let o = p { return o }
        if let c = location?.coordinate { return (c.latitude, c.longitude) }
        if let l = SharedState.lastLocation() { return (l.lat, l.lon) }
        return Geo.berlinCenter
    }

    var travelTable: TravelTimeTable {
        TravelTimeTable(origin: origin, mode: preferences.travelMode, routed: routed)
    }

    func plan(for pool: Pool) -> SwimPlan {
        plans.first { $0.pool.id == pool.id }
            ?? allPlans.first { $0.pool.id == pool.id }
            ?? SwimPlanner(preferences: preferences).plans(for: [pool], now: now, travelKnown: travelKnown) {
                travelTable.travel(to: $0)
            }.first
            ?? SwimPlanner(preferences: preferences).plan(for: pool, now: now, travel: 0)
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

    /// Starts long-running work in tasks owned by the model, so it survives view re-creation
    /// (a cancelled `.task` must not stop location updates or the occupancy refresh loop).
    func start() async {
        guard !started else { return }
        started = true
        feed = await PoolStore.shared.cached()
        recompute()
        Task { await refreshOccupancy() } // independent of the pools.json fetch
        Task { await refresh() }
        Task { await trackLocation() }
        Task { await tick() }
    }

    func refresh(force: Bool = false) async {
        guard fixedNow == nil else { return } // preview / -previewHour: stay on the bundled seed data
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            feed = try await PoolStore.shared.refresh(maxAge: force ? 0 : 10 * 60)
            errorMessage = nil
        } catch {
            errorMessage = feed == nil
                ? String(localized: "Daten konnten nicht geladen werden.")
                : String(localized: "Offline – zeige Stand von \(Fmt.weekdayClock(feed!.generatedAt)).")
        }
        await refreshOccupancy()
        WidgetCenter.shared.reloadAllTimelines()
        await updateRoutes()
    }

    private func refreshOccupancy() async {
        occupancy = await OccupancyStore.shared.current()
        let err = await OccupancyStore.shared.lastError
        log.notice("occupancy: \(self.occupancy.count, privacy: .public) pools, error: \(String(describing: err), privacy: .public)")
        recompute()
    }

    /// Re-evaluate every 30 s so "noch X min" stays current.
    private func tick() async {
        while true {
            try? await Task.sleep(for: .seconds(30))
            await refreshOccupancy() // cached for 2 min inside the store
        }
    }

    private func recompute() {
        now = fixedNow ?? Date()
        let table = travelTable
        let known = travelKnown
        plans = SwimPlanner(preferences: preferences).plans(for: pools, now: now, occupancy: occupancy, travelKnown: known) {
            table.travel(to: $0)
        }
        var unfiltered = preferences
        unfiltered.requiredFeatures = []
        unfiltered.avoidCrowded = false
        unfiltered.minLaneLength = nil
        unfiltered.showOutOfService = true
        allPlans = SwimPlanner(preferences: unfiltered).plans(for: pools, now: now, occupancy: occupancy, travelKnown: known) {
            table.travel(to: $0)
        }
    }

    // MARK: - Location

    private func trackLocation() async {
        serviceSession = CLServiceSession(authorization: .whenInUse)
        do {
            for try await update in CLLocationUpdate.liveUpdates(.otherNavigation) {
                if update.authorizationDenied || update.authorizationDeniedGlobally {
                    if !locationDenied { locationDenied = true; recompute() } // switch to opening-times mode
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
            recompute()
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

#if DEBUG
extension AppModel {
    /// Model for Xcode previews: bundled seed data, sample occupancy, fixed clock, no network/location.
    static func preview(hour: Int = 17, minute: Int = 30, location: Bool = true,
                        configure: (inout SwimPreferences) -> Void = { _ in }) -> AppModel {
        let m = AppModel()
        m.started = true // never start network/location tasks
        m.previewOrigin = .some(location ? PreviewData.origin : nil)
        m.fixedNow = PreviewData.now(hour: hour, minute: minute)
        m.feed = PreviewData.feed
        m.occupancy = PreviewData.occupancy
        var prefs = SwimPreferences()
        configure(&prefs)
        m.preferences = prefs // triggers recompute
        m.recompute()
        return m
    }
}
#endif
