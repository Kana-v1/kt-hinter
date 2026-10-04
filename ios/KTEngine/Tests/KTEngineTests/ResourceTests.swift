import XCTest
@testable import KTEngine

/// Spectre Squad's Fieldcraft points: a second currency, gained in each
/// Strategy phase (more with the Vox-Operator), spent on Elite Fieldcraft and
/// discarded at the end of the turning point.
final class ResourceTests: XCTestCase {
    let e = Repo.engine("spectre_squad")
    let vox = "spectre_vox_operator"
    let fieldcraft = "ss.rule.elite_fieldcraft"
    let firefight = ev(.phase, Params(phase: .firefight))

    func fp(_ log: [Event]) -> Int { e.resource(e.fold(log)) }

    func testGainIsTwoWithTheVoxOperatorAndOneWithout() {
        XCTAssertEqual(fp([]), 2, "the default roster has the Vox-Operator")
        XCTAssertEqual(fp([ev(.roster, Params(id: vox))]), 1, "without it")
        XCTAssertEqual(fp([ev(.down, Params(id: vox))]), 1, "incapacitated isn't in the killzone")
        XCTAssertEqual(e.derive(e.fold([])).resource?.short, "FP")
        XCTAssertNil(Repo.engine("aod").derive(Repo.engine("aod").fold([])).resource, "other teams have none")
    }

    func testGainIsSettledWhenTheFirefightStarts() {
        XCTAssertEqual(fp([firefight, ev(.down, Params(id: vox))]), 2, "losing the Vox-Operator later doesn't take it back")
    }

    func testEliteFieldcraftCostsOneFieldcraftPointNotCP() {
        XCTAssertNil(e.derive(e.fold([])).useCard(fieldcraft), "interrupts happen in the firefight")
        let card = e.derive(e.fold([firefight])).useCard(fieldcraft)
        XCTAssertEqual(card?.cp, 1)
        XCTAssertEqual(card?.unit, "FP")
        let after = e.fold([firefight, ev(.activate, Params(id: fieldcraft))])
        XCTAssertEqual(e.resource(after), 1)
        XCTAssertEqual(after.cp, 3, "CP untouched")
        XCTAssertEqual(after.paid.last?.unit, "FP")
        let empty = [firefight, ev(.activate, Params(id: fieldcraft)), ev(.activate, Params(id: fieldcraft))]
        XCTAssertEqual(fp(empty), 0)
        XCTAssertEqual(e.derive(e.fold(empty)).useCard(fieldcraft)?.afford, false)
    }

    func testCoolHeadedMakesOneTrooperInterruptFreeEachTurningPoint() {
        let trooper = [ev(.count, Params(d: 1, id: "spectre_trooper")), firefight, ev(.op, Params(id: "spectre_trooper#1"))]
        XCTAssertEqual(e.derive(e.fold(trooper)).useCard(fieldcraft)?.cp, 0)
        let used = trooper + [ev(.activate, Params(id: fieldcraft))]
        XCTAssertEqual(fp(used), 2, "free")
        XCTAssertEqual(e.derive(e.fold(used)).useCard(fieldcraft)?.cp, 1, "once per turning point")
        let other = [ev(.count, Params(d: 1, id: "spectre_trooper")), firefight]
        let card = e.derive(e.fold(other)).useCard(fieldcraft)
        XCTAssertEqual(card?.cp, 1, "the Sergeant is acting, not a Trooper")
        XCTAssertEqual(card?.maybe.first?.from, "Cool-Headed")
    }

    func testDiscardedAtTheEndOfTheTurningPoint() {
        let log = [firefight, ev(.res, Params(d: 1)), ev(.tpNext, Params(ini: .us))]
        XCTAssertEqual(fp(log), 2, "a fresh gain, nothing carried over")
    }

    func testAdjustingByHandNeverGoesBelowZero() {
        XCTAssertEqual(fp([ev(.res, Params(d: 1))]), 3)
        XCTAssertEqual(fp([ev(.res, Params(d: -1)), ev(.res, Params(d: -1)), ev(.res, Params(d: -1))]), 0)
        XCTAssertEqual(fp([ev(.res, Params(d: -1)), ev(.res, Params(d: -1)), ev(.res, Params(d: -1)), ev(.res, Params(d: 1))]), 1)
    }

    func testTheBeaconOnlySeesItsOwnRules() {
        let v = e.derive(e.fold([firefight, ev(.op, Params(id: "spectre_vox_relay_beacon"))]))
        XCTAssertEqual(Set(v.activeIds), ["ss.op.signal_beacon", "ss.op.pre_deploy", "ss.op.expendable"])
    }
}
