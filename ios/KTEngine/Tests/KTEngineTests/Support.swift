import Foundation
import XCTest
@testable import KTEngine

/// Tests read the real census files from the repo, so a data edit that breaks
/// a rule fails here.
enum Repo {
    static let root: URL = {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() } // Support.swift → … → repo root
        return u
    }()
    static let teams = ["aod", "plague_marines", "celestian_insidiants", "spectre_squad"]
    static let core = try! CoreGlossary.load(from: root.appendingPathComponent("data/core/glossary.json"))

    static func rules(_ team: String) -> RulesData {
        try! RulesData.load(from: root.appendingPathComponent("data/teams/\(team).json"))
    }

    static func engine(_ team: String) -> Engine {
        Engine(teamId: team, rules: rules(team), core: core)
    }
}

func ev(_ t: Event.Kind, _ p: Params = Params()) -> Event { Event(t, p) }

extension Snapshot {
    var usableIds: [String] { use.flatMap { $0.cards.map(\.id) } }
    var activeIds: [String] { active.flatMap { $0.cards.map(\.id) } }
    func activeGroup(of id: String) -> When? { active.first { $0.cards.contains { $0.id == id } }?.when }
    func useCard(_ id: String) -> UsableCard? { use.flatMap(\.cards).first { $0.id == id } }
}
