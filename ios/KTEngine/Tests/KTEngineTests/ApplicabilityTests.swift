import XCTest
@testable import KTEngine

/// "Does a unit's improvement show when that unit acts, and only then?"
final class ApplicabilityTests: XCTestCase {
    /// Every operative on the table, all equipment taken, every lasting ploy active.
    func everything(_ e: Engine) -> [Event] {
        var log: [Event] = []
        let roster = e.fold([]).roster
        for op in e.rules.operatives where !roster.contains(where: { typeOf($0) == op.id }) {
            log.append(op.multiple ? ev(.count, Params(d: 1, id: op.id)) : ev(.roster, Params(id: op.id)))
        }
        for eff in e.rules.effects where eff.kind == "equipment" { log.append(ev(.equip, Params(id: eff.id))) }
        for eff in e.rules.effects where eff.kind == "strategy_ploy" && eff.duration != "instant" && eff.changesOptionOf == nil {
            log.append(ev(.activate, Params(id: eff.id, opt: eff.options?.first?.id)))
        }
        log.append(ev(.phase, Params(phase: .firefight)))
        return log
    }

    func testRulesShowOnlyOnTheOperativesTheyApplyTo() {
        for team in Repo.teams {
            let e = Repo.engine(team)
            let base = everything(e)
            let roster = e.fold(base).roster
            for inst in roster {
                let v = e.derive(e.fold(base + [ev(.op, Params(id: inst))]))
                let weapons = e.operative(inst)!.weapons.map { $0.name.lowercased() }
                for eff in e.rules.effects where eff.isAlwaysOn && e.present(e.fold(base), eff) {
                    let shown = v.activeIds.contains(eff.id)
                    if eff.requiresStatus != nil {
                        // nobody has a status in this log, so it shows nowhere yet
                        XCTAssertFalse(shown, "\(team): \(eff.name) needs a status")
                        continue
                    }
                    switch eff.appliesTo ?? .team {
                    case .team:
                        let excluded = (eff.notFor ?? []).contains(typeOf(inst))
                        XCTAssertEqual(shown, !excluded, "\(team): \(eff.name) is team-wide (not for \(eff.notFor ?? [])), shown=\(shown) on \(inst)")
                    case .self:
                        XCTAssertEqual(shown, typeOf(inst) == eff.requiresOperative,
                                       "\(team): \(eff.name) belongs to \(eff.requiresOperative ?? "?"), shown=\(shown) on \(inst)")
                    case .weapons:
                        let carries = weapons.contains { w in eff.weaponMatch!.contains { w.contains($0.lowercased()) } }
                        XCTAssertEqual(shown, carries, "\(team): \(eff.name) on \(inst) (carries match: \(carries))")
                    }
                    if !shown {
                        XCTAssertTrue(v.elsewhere.contains { $0.name == eff.name }, "\(eff.name) should be listed as elsewhere")
                    }
                }
            }
        }
    }

    func testRepulsiveFortitudeShowsOnlyOnTheWarrior() {
        let e = Repo.engine("plague_marines")
        let base = [ev(.roster, Params(id: "plague_marine_warrior")), ev(.phase, Params(phase: .firefight))]
        let warrior = e.derive(e.fold(base + [ev(.op, Params(id: "plague_marine_warrior"))]))
        XCTAssertEqual(warrior.activeGroup(of: "pm.op.repulsive_fortitude"), .defence)
        let champion = e.derive(e.fold(base))
        XCTAssertFalse(champion.activeIds.contains("pm.op.repulsive_fortitude"))
        XCTAssertTrue(champion.elsewhere.contains(Elsewhere(name: "Repulsive Fortitude", who: "Plague Marine Warrior only")))
    }

    func testChapterVeteranTacticReachesOnlyTheVeteran() {
        let e = Repo.engine("aod")
        let base = [ev(.leader, Params(id: "intercessor_sergeant")),
                    ev(.tactic, Params(id: "aggressive", slot: "primary")),
                    ev(.tactic, Params(id: "hardy", slot: "extra"))]
        let sergeant = e.derive(e.fold(base + [ev(.op, Params(id: "intercessor_sergeant"))]))
        XCTAssertTrue(sergeant.activeIds.contains("tactic.hardy"))
        XCTAssertTrue(sergeant.activeIds.contains("tactic.aggressive"))
        let gunner = e.derive(e.fold(base + [ev(.op, Params(id: "intercessor_gunner"))]))
        XCTAssertFalse(gunner.activeIds.contains("tactic.hardy"))
        XCTAssertTrue(gunner.activeIds.contains("tactic.aggressive"), "primary tactic is the whole team's")
        XCTAssertTrue(gunner.elsewhere.contains { $0.name == "Hardy" })
    }

    func testLeaderSwapsChangeAbilities() {
        let e = Repo.engine("aod")
        let captain = e.derive(e.fold([]))
        XCTAssertTrue(captain.activeIds.contains("aod.op.heroic_leader"))
        let sergeant = e.derive(e.fold([ev(.leader, Params(id: "intercessor_sergeant"))]))
        XCTAssertFalse(sergeant.activeIds.contains("aod.op.heroic_leader"))
        XCTAssertFalse(sergeant.elsewhere.contains { $0.name == "Iron Halo" }, "the Captain left the roster entirely")
        XCTAssertTrue(sergeant.activeIds.contains("aod.op.doctrine_warfare_intsgt"))
    }

    func testIncapacitatedOperativesTakeTheirRulesWithThem() {
        let e = Repo.engine("plague_marines")
        let down = e.derive(e.fold([ev(.down, Params(id: "plague_marine_champion")),
                                    ev(.op, Params(id: "plague_marine_fighter"))]))
        XCTAssertFalse(down.activeIds.contains("pm.op.grandfathers_blessing"))
        XCTAssertFalse(down.elsewhere.contains { $0.name == "Grandfather's Blessing" })

        let aod = Repo.engine("aod")
        let s = aod.fold([ev(.down, Params(id: "captain"))])
        XCTAssertEqual(aod.quote(s, aod.effect("aod.ff.shock_assault")!, opt: nil).price, 1, "Heroic Leader is gone with the Captain")
    }

    func testWeaponNotesLandOnMatchingWeaponsOnly() {
        let e = Repo.engine("plague_marines")
        let base = [ev(.equip, Params(id: "pm.eq.plague_rounds")),
                    ev(.activate, Params(id: "pm.strat.lumbering_death")),
                    ev(.phase, Params(phase: .firefight))]
        let gunner = e.derive(e.fold(base + [ev(.op, Params(id: "plague_marine_heavy_gunner"))]))
        XCTAssertEqual(gunner.weaponNotes["Bolt pistol"]?.map(\.rules), [["Ceaseless"], ["Poison", "Severe"]])
        XCTAssertEqual(gunner.weaponNotes["Plague spewer"]?.map(\.rules), [["Ceaseless"]])
        XCTAssertEqual(gunner.weaponNotes["Plague spewer"]?.first?.from, "Lumbering Death")

        let champion = e.derive(e.fold(base))
        XCTAssertNil(champion.weaponNotes["Plasma pistol (standard)"]?.first { $0.from == "Plague Rounds" })
        XCTAssertTrue(champion.elsewhere.contains { $0.name == "Plague Rounds" })

        let nextTP = e.derive(e.fold(base + [ev(.op, Params(id: "plague_marine_heavy_gunner")), ev(.tpNext, Params(ini: .us))]))
        XCTAssertEqual(nextTP.weaponNotes["Plague spewer"] ?? [], [], "Lumbering Death ended with the turning point")
        XCTAssertEqual(nextTP.weaponNotes["Bolt pistol"]?.map(\.from), ["Plague Rounds"])
    }

    /// A table you can read: for each operative, what's active on it during a
    /// firefight with every rule in play. Committed as a golden file — any rules
    /// change that moves a cell fails here until the file is regenerated
    /// (KT_UPDATE_GOLDEN=1 swift test) and the diff reviewed.
    func testApplicabilityMatrixMatchesGolden() throws {
        for team in Repo.teams {
            let e = Repo.engine(team)
            let base = everything(e)
            var md = "# Applicability — \(e.rules.meta.team)\n\n"
            md += "Firefight, every operative on the table, all equipment taken, every lasting strategy ploy active.\n\n"
            for inst in e.fold(base).roster {
                let v = e.derive(e.fold(base + [ev(.op, Params(id: inst))]))
                md += "## \(e.operative(inst)!.name)\n\n"
                for g in v.active {
                    md += "- **\(g.when.title):** " + g.cards.map(\.name).joined(separator: " · ") + "\n"
                }
                for w in e.operative(inst)!.weapons {
                    if let notes = v.weaponNotes[w.name] {
                        md += "- *\(w.name):* " + notes.map { "+\($0.rules.joined(separator: " +")) (\($0.from))" }.joined(separator: ", ") + "\n"
                    }
                }
                md += "- elsewhere: " + v.elsewhere.map { "\($0.name) (\($0.who))" }.joined(separator: " · ") + "\n\n"
            }
            let url = Repo.root.appendingPathComponent("ios/KTEngine/Tests/KTEngineTests/Golden/\(team).applicability.md")
            let update = ProcessInfo.processInfo.environment["KT_UPDATE_GOLDEN"] == "1"
            if update || !FileManager.default.fileExists(atPath: url.path) {
                try md.write(to: url, atomically: true, encoding: .utf8)
                continue
            }
            XCTAssertEqual(md, try String(contentsOf: url, encoding: .utf8),
                           "\(team) applicability changed — review, then regenerate with KT_UPDATE_GOLDEN=1")
        }
    }
}
