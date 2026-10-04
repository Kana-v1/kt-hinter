import XCTest
@testable import KTEngine

/// Named game scenarios, ported from the Go engine's tests and adapted to the
/// two-phase model.
final class ScenarioTests: XCTestCase {
    func testBlankState() {
        let e = Repo.engine("aod")
        let s = e.fold([])
        XCTAssertEqual(s.tp, 1)
        XCTAssertEqual(s.cp, 3, "core rules: 2CP + 1 in the first Strategy phase")
        XCTAssertEqual(s.phase, .strategy)
        XCTAssertEqual(s.roster.count, 6)
        XCTAssertEqual(s.op, "captain")
    }

    func testPlagueMarinesDefaultRosterComesFromTheCensus() {
        let s = Repo.engine("plague_marines").fold([])
        XCTAssertEqual(s.roster.count, 6)
        XCTAssertEqual(s.op, "plague_marine_champion")
        XCTAssertFalse(s.roster.contains { typeOf($0) == "captain" })
    }

    func testCombatDoctrineRunsAndAnnotatesWeapons() {
        let e = Repo.engine("aod")
        var log = [ev(.activate, Params(id: "aod.strat.combat_doctrine", opt: "devastator"))]
        var v = e.derive(e.fold(log))
        XCTAssertEqual(e.fold(log).cp, 2)
        XCTAssertFalse(v.usableIds.contains("aod.strat.combat_doctrine"), "active, so not usable again")
        XCTAssertEqual(v.activeGroup(of: "aod.strat.combat_doctrine"), .attack)
        XCTAssertTrue(v.active.flatMap(\.cards).contains { $0.name == "Combat Doctrine · Devastator" })

        log += [ev(.phase, Params(phase: .firefight)), ev(.op, Params(id: "intercessor_gunner"))]
        v = e.derive(e.fold(log))
        let note = v.weaponNotes["Bolt rifle"]?.first
        XCTAssertEqual(note?.rules, ["Balanced"])
        XCTAssertEqual(note?.condition, "target more than 6\" away")
        XCTAssertNil(v.weaponNotes["Fists"], "Devastator is ranged only")
    }

    func testHeroicLeaderMakesFirefightPloysFreeForTheCaptain() {
        let e = Repo.engine("aod")
        let s = e.fold([]) // the Captain is selected
        let q = e.quote(s, e.effect("aod.ff.shock_assault")!, opt: nil)
        XCTAssertEqual(q.price, 0)
        XCTAssertEqual(q.from, "Heroic Leader")
        XCTAssertEqual(e.quote(s, e.effect("core.ff.command_reroll")!, opt: nil).price, 1, "Command Re-roll is excluded")
    }

    func testHeroicLeaderIsOnlyAHintWhenSomeoneElseActs() {
        let e = Repo.engine("aod")
        let s = e.fold([ev(.op, Params(id: "intercessor_gunner")), ev(.phase, Params(phase: .firefight))])
        let card = e.derive(s).useCard("aod.ff.shock_assault")
        XCTAssertEqual(card?.cp, 1)
        XCTAssertEqual(card?.maybe.first?.needsOperative, "Space Marine Captain")
    }

    func testDoctrineWarfarePricesOptionsForTheSergeant() {
        let e = Repo.engine("aod")
        let s = e.fold([ev(.leader, Params(id: "intercessor_sergeant"))])
        let cd = e.derive(s).useCard("aod.strat.combat_doctrine")!
        let price = Dictionary(uniqueKeysWithValues: cd.options.map { ($0.id, $0.cp) })
        XCTAssertEqual(price, ["devastator": 0, "tactical": 0, "assault": 1])
    }

    func testWrathOfVengeanceIsFreeWhenTheCaptainCounteracts() {
        // Heroic Leader: a firefight ploy for 0CP if the Captain is the specified operative.
        let e = Repo.engine("aod")
        let captain = e.derive(e.fold([ev(.phase, Params(phase: .firefight))])).useCard("aod.ff.wrath_of_vengeance")!
        XCTAssertEqual(captain.cp, 0)
        let other = e.derive(e.fold([ev(.phase, Params(phase: .firefight)), ev(.op, Params(id: "intercessor_gunner"))]))
            .useCard("aod.ff.wrath_of_vengeance")!
        XCTAssertEqual(other.cp, 1)
        XCTAssertEqual(other.maybe.first?.needsOperative, "Space Marine Captain")
        // Heroic Leader is once per turning point: after one free ploy, the next costs again.
        let used = e.fold([ev(.phase, Params(phase: .firefight)), ev(.activate, Params(id: "aod.ff.shock_assault"))])
        XCTAssertEqual(used.cp, 3, "Shock Assault was free for the Captain")
        XCTAssertEqual(e.derive(used).useCard("aod.ff.wrath_of_vengeance")?.cp, 1)
    }

    func testReliquariesMakeWrathFreeOnEngage() {
        let e = Repo.engine("aod")
        let s = e.fold([ev(.equip, Params(id: "aod.eq.chapter_reliquaries")), ev(.phase, Params(phase: .firefight)),
                        ev(.op, Params(id: "intercessor_gunner"))])
        let wrath = e.derive(s).useCard("aod.ff.wrath_of_vengeance")!
        XCTAssertEqual(wrath.cp, 0)
        XCTAssertEqual(wrath.discount?.map(\.t).joined(), "Chapter Reliquaries: the operative has an Engage order")
    }

    func testCombatDoctrineIsFreeOnlyWithADoctrineWarfareSergeant() {
        let e = Repo.engine("aod")
        XCTAssertEqual(e.derive(e.fold([])).useCard("aod.strat.combat_doctrine")?.cheaperOptions.map(\.name), [],
                       "the Captain gives no free doctrine")
        let sgt = e.derive(e.fold([ev(.leader, Params(id: "assault_intercessor_sergeant"))])).useCard("aod.strat.combat_doctrine")!
        XCTAssertEqual(sgt.cheaperOptions.map(\.name), ["Tactical", "Assault"])
    }

    func testPoisonousDemiseIsOfferedOnIncapacitation() {
        let e = Repo.engine("plague_marines")
        let v = e.derive(e.fold([ev(.phase, Params(phase: .firefight))]))
        XCTAssertEqual(v.use.flatMap(\.cards).filter { $0.trigger == "incapacitated" }.map(\.id), ["pm.ff.poisonous_demise"])
    }

    func testRuleInfoGivesFullTextForEffectsAndTactics() {
        let aod = Repo.engine("aod")
        let cd = aod.ruleInfo("aod.strat.combat_doctrine")!
        XCTAssertEqual(cd.options.map(\.name), ["Devastator", "Tactical", "Assault"])
        XCTAssertTrue(cd.body.contains { $0.term == "Balanced" })
        XCTAssertEqual(cd.version, "August '26")
        XCTAssertEqual(aod.ruleInfo("tactic.aggressive")?.kind, "Chapter tactic")
        XCTAssertTrue(aod.ruleInfo("tactic.aggressive")!.body.contains { $0.term == "Rending" })
    }

    func testIconOfContagionDiscountFollowsTheIconBearer() {
        let e = Repo.engine("plague_marines")
        let contagion = e.effect("pm.strat.contagion")!
        let q = e.quote(e.fold([]), contagion, opt: nil)
        XCTAssertEqual(q.price, 0)
        XCTAssertEqual(q.from, "Icon of Contagion")
        let without = e.fold([ev(.roster, Params(id: "plague_marine_icon_bearer"))])
        XCTAssertEqual(e.quote(without, contagion, opt: nil).price, 1)
    }

    func testPloysAreOncePerTurningPointExceptCommandReroll() {
        let e = Repo.engine("plague_marines")
        var log = [ev(.phase, Params(phase: .firefight)), ev(.activate, Params(id: "pm.ff.curse_of_rot"))]
        var v = e.derive(e.fold(log))
        XCTAssertFalse(v.usableIds.contains("pm.ff.curse_of_rot"))
        XCTAssertTrue(v.spent.contains { $0.id == "pm.ff.curse_of_rot" })
        log.append(ev(.activate, Params(id: "core.ff.command_reroll")))
        v = e.derive(e.fold(log))
        XCTAssertTrue(v.usableIds.contains("core.ff.command_reroll"))
    }

    func testPhaseDecidesWhatIsUsable() {
        let e = Repo.engine("plague_marines")
        let strategy = e.derive(e.fold([]))
        XCTAssertTrue(strategy.use.flatMap(\.cards).allSatisfy { $0.kind == "strategy_ploy" })
        let firefight = e.derive(e.fold([ev(.phase, Params(phase: .firefight))]))
        XCTAssertFalse(firefight.use.flatMap(\.cards).contains { $0.kind == "strategy_ploy" })
        XCTAssertTrue(firefight.usableIds.contains("pm.ff.curse_of_rot"))
    }

    func testUseNowIsGroupedByWhenItMatters() {
        let e = Repo.engine("plague_marines")
        let v = e.derive(e.fold([ev(.phase, Params(phase: .firefight))]))
        let groups = Dictionary(uniqueKeysWithValues: v.use.map { ($0.when, $0.cards.map(\.id)) })
        XCTAssertEqual(groups[.attack], ["pm.ff.curse_of_rot"])
        XCTAssertEqual(groups[.defence], ["pm.ff.poisonous_demise", "pm.ff.sickening_resilience"])
        XCTAssertNil(groups[.any]?.first { $0 == "pm.ff.poisonous_demise" }, "not an any-time ploy")
        XCTAssertEqual(groups[.activation], ["pm.ff.virulent_poison"])
    }

    func testCommandPointIncomeFollowsInitiative() {
        let e = Repo.engine("aod")
        XCTAssertEqual(e.fold([ev(.tpNext, Params(ini: .us))]).cp, 4)
        XCTAssertEqual(e.fold([ev(.tpNext, Params(ini: .them))]).cp, 5)
    }

    func testEquipmentIsUsableOnlyOnceTaken() {
        let e = Repo.engine("aod")
        var log = [ev(.phase, Params(phase: .firefight))]
        XCTAssertFalse(e.derive(e.fold(log)).usableIds.contains("aod.eq.auspex"))
        log.append(ev(.equip, Params(id: "aod.eq.auspex")))
        XCTAssertTrue(e.derive(e.fold(log)).usableIds.contains("aod.eq.auspex"))
    }

    func testSelectingAnotherOperativeEndsActivationEffects() {
        let e = Repo.engine("aod")
        let log = [ev(.phase, Params(phase: .firefight)), ev(.activate, Params(id: "aod.ff.shock_assault"))]
        XCTAssertNotNil(e.fold(log).active.first { $0.id == "aod.ff.shock_assault" })
        let same = e.fold(log + [ev(.op, Params(id: "captain"))])
        XCTAssertNotNil(same.active.first { $0.id == "aod.ff.shock_assault" }, "re-selecting the same operative isn't a new activation")
        let other = e.fold(log + [ev(.op, Params(id: "intercessor_gunner"))])
        XCTAssertNil(other.active.first { $0.id == "aod.ff.shock_assault" })
    }

    func testStrategyPloysOutliveOperativeChanges() {
        let e = Repo.engine("plague_marines")
        let s = e.fold([ev(.activate, Params(id: "pm.strat.lumbering_death")),
                        ev(.phase, Params(phase: .firefight)),
                        ev(.op, Params(id: "plague_marine_fighter"))])
        XCTAssertNotNil(s.active.first { $0.id == "pm.strat.lumbering_death" })
    }

    func testTurningPointRecapListsWhatWasPaid() {
        let e = Repo.engine("plague_marines")
        let s = e.fold([ev(.activate, Params(id: "pm.strat.contagion")),
                        ev(.activate, Params(id: "pm.strat.lumbering_death")),
                        ev(.tpNext, Params(ini: .us))])
        XCTAssertEqual(s.tp, 2)
        XCTAssertEqual(s.lastSummary?.paid.map(\.name), ["Contagion", "Lumbering Death"])
        XCTAssertEqual(s.lastSummary?.paid.map(\.cp), [0, 1], "Contagion was free via the Icon Bearer")
        XCTAssertTrue(s.active.isEmpty)
        XCTAssertEqual(s.phase, .strategy)
    }

    func testUndoDropsTheLastEvent() {
        let e = Repo.engine("aod")
        var game = GameLog(team: "aod")
        game.append(ev(.cp, Params(d: 1)))
        game.append(ev(.tpNext, Params(ini: .them)))
        XCTAssertEqual(e.fold(game.events).cp, 6)
        game.undo()
        XCTAssertEqual(e.fold(game.events).cp, 4)
        XCTAssertEqual(e.fold(game.events).tp, 1)
    }

    func testGameLogRoundTripsThroughJSON() throws {
        var game = GameLog(team: "plague_marines")
        game.append(ev(.tpNext, Params(ini: .them)))
        game.append(ev(.activate, Params(id: "aod.strat.combat_doctrine", opt: "assault")))
        let back = try JSONDecoder().decode(GameLog.self, from: JSONEncoder().encode(game))
        XCTAssertEqual(back, game)
    }
}
