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
        let p = planner { $0.includeLimited = false }
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
