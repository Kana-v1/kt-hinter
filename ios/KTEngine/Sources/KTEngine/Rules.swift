import Foundation

// The rules census for one kill team, decoded from data/teams/<id>.json.
// Reference data only: it says what exists, never what's happening in a game.
// Field meanings are documented in CLAUDE.md ("Data model").

public struct RulesData: Codable {
    public var meta: Meta
    public var vocab: Vocab
    public var effects: [Effect]
    public var operatives: [Operative]
    public var universalEquipment: [Weapon]?
    public var chapterTactics: [ChapterTactic]
    /// Faction terms (Poison, Toxic, …) for the tappable glossary.
    public var glossary: [String: GlossaryEntry]?
    /// Operative states the player sets and the app tracks (INSPIRING, Benedictions).
    public var statuses: [StatusDef]?

    public static func load(from url: URL) throws -> RulesData {
        try JSONDecoder().decode(RulesData.self, from: Data(contentsOf: url))
    }
}

public struct Meta: Codable {
    public var team: String
    public var teamId: String
    public var edition: String?
    public var sourcePdf: String?
    public var rulesVersion: String?
    public var defaultRoster: [String]?
    /// Operatives in a legal roster (6 unless the team says otherwise).
    public var rosterSize: Int?
    public var unresolved: [String]?
    /// A team currency besides CP (Spectre Squad's Fieldcraft points).
    public var resource: Resource?
}

/// A team currency besides CP. Like CP it's a counter the player can nudge;
/// unlike CP it's gained in each Strategy phase and discarded at the end of
/// each turning point.
public struct Resource: Codable, Equatable {
    public var id: String
    /// "Fieldcraft points".
    public var name: String
    /// "FP", beside prices and the counter.
    public var short: String
    /// Gained in each Strategy phase.
    public var gain: Int
    public var bonus: ResourceBonus?
}

/// More gain while an operative is on the roster and not incapacitated
/// (Fieldcraft: +1 with the Vox-Operator).
public struct ResourceBonus: Codable, Equatable {
    public var operative: String
    public var gain: Int
    /// What the app can't check ("if it isn't within control range of enemy operatives").
    public var condition: String?
}

public struct Vocab: Codable {
    public var phases: [String]?
    public var when: [String]?
    public var appliesTo: [String]?
}

public struct Cost: Codable, Equatable {
    public var cp: Int
    /// Priced in the team's resource instead of CP (Elite Fieldcraft: 1FP).
    public var resource: Int?
}

public struct Effect: Codable {
    public var id: String
    public var name: String
    public var kind: String
    public var universal: Bool?
    public var cost: Cost
    public var duration: String
    public var oncePer: String?
    public var text: String
    public var options: [Option]?
    public var requiresOperative: String?
    public var alwaysOn: Bool?
    public var costOverrides: [Override]?
    public var changesOptionOf: String?
    public var requires: Requires?
    public var disputed: Bool?
    public var verify: [String]?
    // iOS model fields (tools/add_ios_model_fields.py)
    public var when: When?
    public var appliesTo: AppliesTo?
    public var weaponMatch: [String]?
    public var hint: String?
    public var grantsWeaponRules: [Grant]?
    /// A moment the app itself sees that should offer this ploy ("incapacitated").
    public var trigger: String?
    /// Only applies while the operative it's for has this status.
    public var requiresStatus: String?
    /// Operative types a team-wide rule doesn't apply to ("excluding VOX-RELAY BEACON").
    public var notFor: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, kind, universal, cost, duration, text, options, requiresOperative, alwaysOn,
             costOverrides, changesOptionOf, requires, disputed, verify,
             when, appliesTo, weaponMatch, hint, grantsWeaponRules, trigger, requiresStatus, notFor
        case oncePer = "once_per"
    }

    public var overrides: [Override] { costOverrides ?? [] }

    public var isAlwaysOn: Bool { alwaysOn ?? false }
    /// Paid in the team's resource rather than CP.
    public var usesResource: Bool { cost.resource != nil }
    /// The base price, in CP or the team's resource.
    public var price: Int { cost.resource ?? cost.cp }
    public var isPloy: Bool { kind == "strategy_ploy" || kind == "firefight_ploy" }
}

public struct Option: Codable {
    public var id: String
    public var name: String
    public var condition: String?
    public var hint: String?
    public var grantsWeaponRules: [Grant]?
}

public struct Override: Codable {
    public var effect: String?
    public var kind: String?
    public var options: [String]?
    public var excludes: [String]?
    /// The new price: `cp` for a CP cost, `resource` for a resource one.
    public var cp: Int?
    public var resource: Int?
    public var oncePer: String?
    public var group: String?
    public var selectedIs: String?
    public var condition: String?
    /// Only while the operative granting the discount has this status.
    public var requiresStatus: String?

    enum CodingKeys: String, CodingKey {
        case effect, kind, options, excludes, cp, resource, group, selectedIs, condition, requiresStatus
        case oncePer = "once_per"
    }

    public var price: Int { resource ?? cp ?? 0 }
}

public struct Requires: Codable {
    public var note: String?
    public var activeEffect: String?
}

/// Rules an effect adds to weapons, shown as notes under the weapon row.
/// `match`: "*" (all), "ranged", "melee", or case-insensitive weapon-name substrings.
public struct Grant: Codable, Equatable {
    public var match: [String]
    public var rules: [String]
    public var condition: String?
}

public struct Operative: Codable {
    public var id: String
    public var name: String
    public var stats: Stats
    public var abilities: [String]
    public var weapons: [Weapon]
    public var icon: String
    public var accent: String
    public var leader: Bool
    public var multiple: Bool
    public var role: String
    public var chapterVeteran: Bool
    /// Most copies allowed in a roster (Cremators: 2). Nil: one, or any for `multiple`.
    public var max: Int?
}

/// A state an operative is in until the player clears it (the app can't see
/// it happen). While set it shows on that operative with its hint and weapon notes.
public struct StatusDef: Codable, Equatable {
    public var id: String
    public var name: String
    public var hint: String
    public var grantsWeaponRules: [Grant]?
    /// Operative types that can't have it (Ardour: not a Superior).
    public var notFor: [String]?
}

public struct Stats: Codable, Equatable {
    public var apl: Int
    public var move: String
    public var save: String
    public var wounds: Int
}

public struct Weapon: Codable, Equatable {
    public var name: String
    public var type: String
    public var atk: Int
    public var hit: String
    public var dmg: String
    public var rules: String

    public var isMelee: Bool { type == "melee" }
}

public struct ChapterTactic: Codable {
    public var id: String
    public var name: String
    public var text: String
    public var when: When?
    public var hint: String?
    public var grantsWeaponRules: [Grant]?
}

public struct GlossaryEntry: Codable, Equatable {
    public var kind: String
    public var def: String
}

/// data/core/glossary.json: core weapon rules, from the official Lite rules.
public struct CoreGlossary: Codable {
    public var terms: [String: GlossaryEntry]
    public var keywordsNotRules: [String]?

    public static func load(from url: URL) throws -> CoreGlossary {
        try JSONDecoder().decode(CoreGlossary.self, from: Data(contentsOf: url))
    }
}

/// Which group a rule shows in during the firefight.
public enum When: String, Codable, CaseIterable {
    case activation, attack, defence, any

    public var title: String {
        switch self {
        case .activation: return "Your activation"
        case .attack: return "Your attacks"
        case .defence: return "When you're attacked"
        case .any: return "Any time"
        }
    }
}

/// Who a rule applies to: every friendly operative, only its own operative,
/// or only operatives carrying a matching weapon.
public enum AppliesTo: String, Codable {
    case team, `self`, weapons
}
