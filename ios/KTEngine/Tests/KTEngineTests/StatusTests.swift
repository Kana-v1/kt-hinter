import XCTest
@testable import KTEngine

/// Celestian Insidiants: a 9-operative roster and operative statuses
/// (INSPIRING, Benedictions) the player sets.
final class StatusTests: XCTestCase {
    let e = Repo.engine("celestian_insidiants")

    func testRosterIsNineWithTheSuperiorLeading() {
        let s = e.fold([])
        XCTAssertEqual(s.roster.count, 9)
        XCTAssertEqual(s.op, "insidiant_superior")
        XCTAssertTrue(e.derive(s).rosterStatus.ok)
    }

    func testCrematorsAreCappedAtTwo() {
        var log = [ev(.count, Params(d: 1, id: "insidiant_cremator")), ev(.count, Params(d: 1, id: "insidiant_cremator"))]
        XCTAssertEqual(e.fold(log).roster.filter { typeOf($0) == "insidiant_cremator" }.count, 2)
        log.append(ev(.count, Params(d: 1, id: "insidiant_warrior")))
        XCTAssertEqual(e.fold(log).roster.filter { typeOf($0) == "insidiant_warrior" }.count, 3, "Warriors repeat")
        XCTAssertEqual(e.maxCount("insidiant_cremator"), 2)
        XCTAssertEqual(e.maxCount("insidiant_censor"), 1)
    }

    func testInspiringAddsSevereAndCanBeCleared() {
        let on = [ev(.op, Params(id: "insidiant_warrior#1")), ev(.status, Params(opt: "inspiring"))]
        var v = e.derive(e.fold(on))
        XCTAssertTrue(v.statuses.first { $0.id == "inspiring" }!.on)
        XCTAssertTrue(v.activeIds.contains("status.inspiring"))
        XCTAssertEqual(v.weaponNotes["Null mace"]?.flatMap(\.rules).contains("Severe"), true)
        XCTAssertTrue(v.activeIds.contains("ci.op.inspired_strikes"), "Inspired Strikes needs INSPIRING")
        XCTAssertEqual(v.statusNames["insidiant_warrior#1"], ["Inspiring"])

        v = e.derive(e.fold(on + [ev(.status, Params(opt: "inspiring"))]))
        XCTAssertFalse(v.activeIds.contains("status.inspiring"))
        XCTAssertFalse(v.activeIds.contains("ci.op.inspired_strikes"))
        XCTAssertTrue(v.elsewhere.contains { $0.name == "Inspired Strikes" && $0.who.contains("INSPIRING") })
    }

    func testStatusBelongsToItsOperative() {
        let s = e.fold([ev(.status, Params(id: "insidiant_warrior#2", opt: "wrath")),
                        ev(.op, Params(id: "insidiant_warrior#1"))])
        XCTAssertFalse(e.derive(s).activeIds.contains("status.wrath"))
        let other = e.derive(e.fold([ev(.status, Params(id: "insidiant_warrior#2", opt: "wrath")),
                                     ev(.op, Params(id: "insidiant_warrior#2"))]))
        XCTAssertEqual(other.weaponNotes["Bolt pistol"]?.flatMap(\.rules), ["Ceaseless"])
        // removing the operative drops its status
        let gone = e.fold([ev(.status, Params(id: "insidiant_warrior#2", opt: "wrath")),
                           ev(.count, Params(d: -1, id: "insidiant_warrior"))])
        XCTAssertTrue(gone.statuses.isEmpty)
    }

    func testArdourIsNotForTheSuperior() {
        XCTAssertFalse(e.statuses(for: "insidiant_superior").contains { $0.id == "ardour" })
        let s = e.fold([ev(.status, Params(id: "insidiant_superior", opt: "ardour"))])
        XCTAssertTrue(s.statuses.isEmpty)
    }

    func testHolyExampleNeedsAnInspiringSuperior() {
        let ploy = e.effect("ci.ff.faith_and_fury")!
        var s = e.fold([ev(.phase, Params(phase: .firefight))])
        var q = e.quote(s, ploy, opt: nil)
        XCTAssertEqual(q.price, 1, "not INSPIRING yet")
        XCTAssertEqual(q.maybe.first?.from, "Holy Example")

        s = e.fold([ev(.phase, Params(phase: .firefight)), ev(.status, Params(opt: "inspiring"))])
        q = e.quote(s, ploy, opt: nil)
        XCTAssertEqual(q.price, 0)
        XCTAssertEqual(e.quote(s, e.effect("core.ff.command_reroll")!, opt: nil).price, 0, "Command Re-roll included")

        // once per turning point
        s = e.fold([ev(.phase, Params(phase: .firefight)), ev(.status, Params(opt: "inspiring")),
                    ev(.activate, Params(id: "ci.ff.faith_and_fury"))])
        XCTAssertEqual(s.cp, 3)
        XCTAssertEqual(e.quote(s, e.effect("ci.ff.fervent_hate")!, opt: nil).price, 1)
    }

    func testAccusingExorcistNeedsAnInspiringDenuncia() {
        let ploy = e.effect("ci.strat.suspect_and_eliminate")!
        XCTAssertEqual(e.quote(e.fold([]), ploy, opt: nil).price, 1)
        let s = e.fold([ev(.status, Params(id: "insidiant_denuncia", opt: "inspiring"))])
        XCTAssertEqual(e.quote(s, ploy, opt: nil).price, 0)
        let down = e.fold([ev(.status, Params(id: "insidiant_denuncia", opt: "inspiring")),
                           ev(.down, Params(id: "insidiant_denuncia"))])
        XCTAssertEqual(e.quote(down, ploy, opt: nil).price, 1)
    }

    func testTeamsWithoutStatusesHaveNone() {
        let aod = Repo.engine("aod")
        XCTAssertTrue(aod.derive(aod.fold([ev(.status, Params(opt: "inspiring"))])).statuses.isEmpty)
    }
}
