import Foundation
import Testing
@testable import BadKit

/// 2026-11-24 (Tuesday) at hh:mm Berlin time.
func t(_ hh: Int, _ mm: Int = 0, day: Int = 24) -> Date {
    Calendar.berlin.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hh, minute: mm))!
}

func makePool(id: Int = 1, slots: [Slot], areaKind: Area.Kind = .swim, lane: Int? = 50,
              closures: [Closure] = [], closedNow: Bool = false) -> Pool {
    Pool(id: id, slug: "p\(id)", name: "Pool \(id)", type: "Hallenbad", district: nil, street: nil, zip: nil,
         lat: 52.5, lon: 13.4, url: URL(string: "https://example.com")!, ticketUrl: nil, closedNow: closedNow,
         category: 2, description: nil, laneLength: lane, equipment: lane == 50 ? ["50-m-Becken"] : ["25-m-Becken"],
         accessibility: [], extras: [], transit: nil, waterTempC: nil, waterTemps: [], traffic: nil,
         notices: [], closures: closures, rules: Rules(), areas: [
            Area(name: "Hallenbad", kind: areaKind, laneLength: lane, slots: slots),
         ])
}

func planner(training: Int = 60, change: Int = 15, configure: (inout SwimPreferences) -> Void = { _ in }) -> SwimPlanner {
    var p = SwimPreferences()
    p.trainingMinutes = training
    p.changeMinutes = change
    configure(&p)
    return SwimPlanner(preferences: p)
}

@Suite struct SwimPlannerTests {
    // Public 16:00–22:00 → Badeschluss 21:30, Einlass bis 21:00
    let evening = makePool(slots: [
        Slot(start: t(8), end: t(16), kind: .private, label: "nur Schul-, Vereins-, Kursbetrieb"),
        Slot(start: t(16), end: t(22), kind: .public, label: "öffentl. Schwimmen"),
    ])

    // Stadtbad Neukölln on Mondays: only "Frauenschwimmen" today, public tomorrow.
    let womenToday = makePool(slots: [
        Slot(start: t(12, day: 23), end: t(22, 30, day: 23), kind: .restricted, label: "Frauenschwimmen"),
        Slot(start: t(14), end: t(22, 30), kind: .public, label: "öffentl. Schwimmen"),
    ], lane: 25)

    @Test func womenOnlyIsHintByDefault() {
        let plan = planner().plan(for: womenToday, now: t(16, day: 23), travel: 20 * 60)
        #expect(plan.status == .notToday)
        #expect(plan.womenOnlyToday?.end == t(22, 30, day: 23))
        #expect(plan.womenOnlyText == L("Frauen bis \("22:30")"))
    }

    @Test func womenOnlyCountsWhenEnabled() {
        let plan = planner { $0.includeWomenOnly = true }.plan(for: womenToday, now: t(16, day: 23), travel: 20 * 60)
        #expect(plan.status == .goNow)
        #expect(plan.window?.isWomenOnly == true)
        #expect(plan.womenOnlyToday == nil)
    }

    @Test func outOfServiceHiddenUnlessEnabled() {
        let summer = makePool(id: 2, slots: [], closedNow: true)
        let pools = [evening, summer]
        #expect(planner().plans(for: pools, now: t(18)) { _ in (600, false) }.map(\.pool.id) == [1])
        let all = planner { $0.showOutOfService = true }.plans(for: pools, now: t(18)) { _ in (600, false) }
        #expect(all.count == 2)
    }

    @Test func fiftyMeterFilterHidesShortPools() {
        let short = makePool(id: 3, slots: evening.areas[0].slots, lane: 25)
        let plans = planner { $0.minLaneLength = 50 }.plans(for: [evening, short], now: t(18)) { _ in (600, false) }
        #expect(plans.map(\.pool.id) == [1])
    }

    @Test func oldLane50FeatureMigratesToMinLaneLength() throws {
        let json = #"{"trainingMinutes":60,"requiredFeatures":["lane50","sauna"]}"#
        let prefs = try JSONDecoder().decode(SwimPreferences.self, from: Data(json.utf8))
        #expect(prefs.minLaneLength == 50)
        #expect(prefs.requiredFeatures == [.sauna])
    }

    @Test func closedTodayShowsNextOpenDay() {
        let pool = makePool(slots: [
            Slot(start: t(16, day: 23), end: t(22, day: 23), kind: .public, label: "öffentl. Schwimmen"),
            Slot(start: t(6, 30), end: t(8), kind: .public, label: "öffentl. Schwimmen"),
        ], closures: [Closure(dates: ["2026-11-23"], reason: "Teamtag")])
        let plan = planner().plan(for: pool, now: t(10, day: 23), travel: 600)
        #expect(plan.status == .closed)
        #expect(plan.nextWindow?.start == t(6, 30))
        #expect(plan.statusDetail == L("morgen ab \("06:30")"))
    }

    @Test func englishTranslationsResolve() {
        // Catalog sanity check: look up the English table explicitly (independent of the machine's language).
        guard let path = Bundle.module.path(forResource: "en", ofType: "lproj"), let en = Bundle(path: path) else {
            Issue.record("no en.lproj in BadKit bundle"); return
        }
        #expect(String(localized: "offen bis", bundle: en) == "open until")
        #expect(String(localized: "Frauen bis \("22:30")", bundle: en) == "Women-only until 22:30")
    }

    @Test func goNowWithEnoughTime() {
        let plan = planner().plan(for: evening, now: t(18), travel: 20 * 60)
        #expect(plan.status == .goNow)
        // arrive 18:20, in water 18:35, out 21:30 → 175 min
        #expect(plan.usableMinutes == 175)
        // latest entry = min(21:00, 21:30 - 60 - 15 = 20:15) = 20:15 → leave by 19:55
        #expect(plan.leaveBy == t(19, 55))
    }

    @Test func tightWhenTrainingDoesNotFit() {
        let plan = planner().plan(for: evening, now: t(20, 10), travel: 20 * 60)
        // arrive 20:30, water 20:45 → 45 min until 21:30
        #expect(plan.status == .tight)
        #expect(plan.usableMinutes == 45)
        #expect(plan.leaveBy == nil)
    }

    @Test func entryCutoffMakesItImpossible() {
        // arrive 21:05 > Einlass 21:00
        let plan = planner(training: 10).plan(for: evening, now: t(20, 45), travel: 20 * 60)
        #expect(plan.status == .notToday)
    }

    @Test func laterWhenPublicSwimmingStartsLater() {
        let plan = planner().plan(for: evening, now: t(10), travel: 20 * 60)
        #expect(plan.status == .later)
        #expect(plan.window?.start == t(16))
        #expect(plan.swimStart == t(16, 15))
    }

    @Test func privateSlotsAreIgnored() {
        let pool = makePool(slots: [Slot(start: t(8), end: t(22), kind: .private)])
        #expect(planner().plan(for: pool, now: t(10), travel: 600).status == .notToday)
    }

    @Test func adjacentSlotsAreMerged() {
        let pool = makePool(slots: [
            Slot(start: t(6, 30), end: t(8), kind: .public),
            Slot(start: t(8), end: t(10), kind: .limited),
        ])
        let p = planner()
        #expect(p.windows(for: pool).count == 1)
        let plan = p.plan(for: pool, now: t(7), travel: 600)
        // arrive 7:10, water 7:25, out 9:30 → 125 min
        #expect(plan.status == .goNow)
        #expect(plan.usableMinutes == 125)
        #expect(plan.window?.isLimited == true)
    }

    @Test func limitedCanBeExcluded() {
        let pool = makePool(slots: [Slot(start: t(8), end: t(22), kind: .limited)])
        let p = planner { $0.onlyFullWaterArea = true }
        #expect(p.plan(for: pool, now: t(10), travel: 600).status == .notToday)
    }

    @Test func closureNoticeClosesToday() {
        let pool = makePool(slots: [], closures: [Closure(dates: ["2026-11-24"], reason: "Teamtag")])
        let plan = planner().plan(for: pool, now: t(10), travel: 600)
        #expect(plan.status == .closed)
        #expect(plan.closedReason == "Teamtag")
    }

    @Test func seasonClosed() {
        let pool = makePool(slots: [], closedNow: true)
        #expect(planner().plan(for: pool, now: t(10), travel: 600).status == .closed)
    }

    @Test func minLaneLengthFilters() {
        let p25 = makePool(slots: [Slot(start: t(8), end: t(22), kind: .public)], lane: 25)
        let p = planner { $0.minLaneLength = 50 }
        #expect(p.plan(for: p25, now: t(10), travel: 600).status == .notToday)
    }

    @Test func saunaIsNotSwimming() {
        let sauna = makePool(slots: [Slot(start: t(8), end: t(22), kind: .public)], areaKind: .sauna)
        #expect(planner().plan(for: sauna, now: t(10), travel: 600).status == .notToday)
    }

    @Test func notTodayPointsToTomorrow() {
        let pool = makePool(slots: [
            Slot(start: t(16), end: t(22), kind: .public),
            Slot(start: t(6, 30, day: 25), end: t(8, day: 25), kind: .public),
        ])
        let plan = planner().plan(for: pool, now: t(21, 30), travel: 600)
        #expect(plan.status == .notToday)
        #expect(plan.nextWindow?.start == t(6, 30, day: 25))
    }

    @Test func sortingPrefersGoNowThenTravel() {
        let near = makePool(id: 1, slots: [Slot(start: t(8), end: t(22), kind: .public)])
        let far = makePool(id: 2, slots: [Slot(start: t(8), end: t(22), kind: .public)])
        let later = makePool(id: 3, slots: [Slot(start: t(16), end: t(22), kind: .public)])
        let plans = planner().plans(for: [later, far, near], now: t(10)) { pool in
            (pool.id == 2 ? 1800 : 600, true)
        }
        #expect(plans.map(\.pool.id) == [1, 2, 3])
    }

    @Test func travelEstimateIsPlausible() {
        // 5 km by bike ≈ 25 min
        let s = TravelMode.cycling.estimate(distanceMeters: 5000) / 60
        #expect(s > 20 && s < 30)
    }
}

@Suite struct FeedDecodingTests {
    @Test func decodesScraperOutput() throws {
        let json = """
        {"schemaVersion":1,"generatedAt":"2026-11-23T12:00:00+01:00","source":"x","pools":[{"id":9,"slug":"s",
        "name":"Kombibad Seestraße - Hallenbad","type":"Hallenbad","district":"Mitte","street":"Seestraße 80","zip":"13347",
        "lat":52.55,"lon":13.36,"url":"https://www.berlinerbaeder.de/baeder/detail/s/","ticketUrl":null,"closedNow":false,
        "category":2,"description":null,"laneLength":50,"equipment":["50-m-Becken"],"accessibility":[],"extras":[],
        "transit":null,"waterTempC":27.5,"waterTemps":[{"basin":"Schwimmerbecken","tempC":27.5}],"traffic":null,
        "notices":[{"text":"Teamtag","severity":"warning"}],"closures":[],"rules":{"entryCutoffMin":60,"exitBeforeCloseMin":30},
        "areas":[{"name":"Hallenbad","kind":"swim","laneLength":50,"slots":[{"start":"2026-11-24T16:00:00+01:00",
        "end":"2026-11-24T22:00:00+01:00","kind":"public","label":"öffentl. Schwimmen","period":"Öffnungszeiten"}]}]}]}
        """
        let feed = try PoolsFeed.decode(Data(json.utf8))
        #expect(feed.pools.first?.shortName == "Kombibad Seestraße")
        #expect(feed.pools.first?.areas.first?.slots.first?.start == t(16))
        #expect(feed.pools.first?.has(.lane50) == true)
    }
}

@Suite struct OccupancyTests {
    let feed = """
    [{"id":"12","level":2,"color":"#F9C74F","counter":44,"automatic":true,"thresholds":[{"level":1,"threshold":30},{"level":4,"threshold":100}]},
     {"id":"18","level":1,"counter":-4,"automatic":true,"thresholds":[{"level":4,"threshold":520}]},
     {"id":"28","level":3,"counter":null,"automatic":false,"thresholds":[{"level":4,"threshold":160}]},
     {"id":"17","level":-1,"counter":null,"automatic":false,"thresholds":[]},
     {"id":"35","level":-2,"counter":null,"automatic":false,"thresholds":[]}]
    """

    @Test func parsesLiveAndManualEntries() throws {
        let o = try Occupancy.parse(Data(feed.utf8))
        #expect(o.count == 4)          // level -1 dropped, -2 kept as closure
        #expect(o[35]?.closedReason == L("Wetterbedingt geschlossen"))
        #expect(o[12]?.fraction == 0.44)
        #expect(o[18]?.count == 0)     // negative counter clamped
        #expect(o[28]?.fraction == nil) // manual: level only
        #expect(o[28]?.isCrowded == true)
    }

    @Test func avoidCrowdedFiltersPools() throws {
        let o = try Occupancy.parse(Data(feed.utf8))
        let open = [Slot(start: t(8), end: t(22), kind: .public)]
        let pools = [makePool(id: 12, slots: open), makePool(id: 28, slots: open)]
        let p = planner { $0.avoidCrowded = true }
        let plans = p.plans(for: pools, now: t(10), occupancy: o) { _ in (600, true) }
        #expect(plans.map(\.pool.id) == [12])
        #expect(plans.first?.occupancy?.level == 2)
    }

    @Test func oldPreferencesStillDecode() throws {
        let old = #"{"trainingMinutes":45,"changeMinutes":10,"travelMode":"walking","includeLimited":true,"requiredFeatures":[],"favorites":[79],"minimumUsefulMinutes":20}"#
        let p = try JSONDecoder().decode(SwimPreferences.self, from: Data(old.utf8))
        #expect(p.trainingMinutes == 45 && p.favorites == [79] && p.avoidCrowded == false)
    }

    @Test func oldLimitedSettingIsIgnored() throws {
        // Users who switched limited water area off before still get it counted (new default).
        let old = #"{"includeLimited":false}"#
        let p = try JSONDecoder().decode(SwimPreferences.self, from: Data(old.utf8))
        #expect(p.onlyFullWaterArea == false)
    }

    @Test func weatherClosureClosesPool() throws {
        let o = try Occupancy.parse(Data(feed.utf8))
        let open = [Slot(start: t(8), end: t(22), kind: .public)]
        let plans = planner().plans(for: [makePool(id: 35, slots: open)], now: t(10), occupancy: o) { _ in (600, true) }
        #expect(plans.first?.status == .closed)
        #expect(plans.first?.closedReason == L("Wetterbedingt geschlossen"))
    }
}
