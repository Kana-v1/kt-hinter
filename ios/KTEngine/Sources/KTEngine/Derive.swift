import Foundation

// derive(state) → View: everything the screen shows, computed from State and
// the rules. Pure: it never changes State.

public struct Snapshot {
    public var team: String
    public var tp: Int
    public var cp: Int
    public var phase: Phase
    public var roster: [String]
    public var op: String
    public var dead: Set<String>
    public var equip: Set<String>
    public var tactics: [String: String]
    public var rosterStatus: RosterStatus
    public var veterans: [String]
    /// Usable now, grouped by when they matter.
    public var use: [CardGroup<UsableCard>]
    /// In play for the selected operative, grouped by when they matter.
    public var active: [CardGroup<ActiveCard>]
    /// In play, but for other operatives (shown dimmed, names only).
    public var elsewhere: [Elsewhere]
    public var spent: [SpentCard]
    /// Weapon-rule notes for the selected operative, keyed by weapon name.
    public var weaponNotes: [String: [WeaponNote]]
    public var summary: Summary?
    /// Statuses the selected operative can have, and whether it has them.
    public var statuses: [StatusChip]
    /// Operative instance → names of the statuses it has, for roster chips.
    public var statusNames: [String: [String]]
    /// The team's second currency, if it has one (Fieldcraft points).
    public var resource: ResourceCounter?
}

public struct ResourceCounter: Equatable {
    public var name: String
    public var short: String
    public var value: Int
    /// How this turning point's gain was made up, and what the app can't check about it.
    public var note: String
}

public struct StatusChip: Equatable {
    public var id: String
    public var name: String
    public var on: Bool
}

public struct CardGroup<Card> {
    public var when: When
    public var cards: [Card]
}

public struct RosterStatus: Equatable {
    public var total: Int
    public var leaders: Int
    public var ok: Bool
}

public struct UsableCard {
    public var id: String
    public var name: String
    public var kind: String
    public var kindLabel: String
    public var hint: [Segment]
    public var costBase: Int
    /// The price, in `unit`.
    public var cp: Int
    /// "CP", or the team resource's short name ("FP").
    public var unit: String
    public var afford: Bool
    /// Why the price is reduced ("Icon of Contagion: if the Icon Bearer is …").
    public var discount: [Segment]?
    /// Discounts that could apply but the app can't confirm (dim "can be free").
    public var maybe: [MaybeRoute]
    public var options: [OptionQuote]
    public var disputed: Bool
    /// Offered when the app sees this moment happen (e.g. "incapacitated").
    public var trigger: String?

    public var reduced: Bool { cp < costBase }
    /// Options cheaper than the base price (Doctrine Warfare's free doctrines).
    public var cheaperOptions: [OptionQuote] { options.filter { $0.cp < costBase } }
    public var free: Bool { cp == 0 }
}

public struct MaybeRoute: Equatable {
    public var from: String
    public var options: [String]?
    public var condition: String
    /// The discount needs a specific operative selected (e.g. the Captain).
    public var needsOperative: String?
}

public struct OptionQuote: Equatable {
    public var id: String
    public var name: String
    public var condition: String
    public var cp: Int
}

public struct ActiveCard {
    public var id: String
    public var name: String
    public var kindLabel: String
    public var hint: [Segment]
    /// "this turning point", "always", "this activation", "once per battle".
    public var life: String
    /// Paid effects can be ended by hand.
    public var canEnd: Bool
    public var canMarkUsed: Bool
    public var disputed: Bool
}

public struct Elsewhere: Equatable {
    public var name: String
    public var who: String
}

public struct SpentCard: Equatable {
    public var id: String
    public var name: String
    public var kindLabel: String
}

public struct WeaponNote: Equatable {
    public var rules: [String]
    public var from: String
    public var condition: String?
}

let kindLabels = [
    "strategy_ploy": "Strategy ploy", "firefight_ploy": "Firefight ploy", "equipment": "Equipment",
    "faction_rule": "Faction rule", "operative_ability": "Ability", "chapter_tactic": "Chapter tactic",
    "status": "Status",
]

extension Engine {
    public func derive(_ s: GameState, logLength: Int = 0) -> Snapshot {
        let activeIds = Set(s.active.map(\.id))
        var usable: [UsableCard] = []
        var spent: [SpentCard] = []
        var inPlay: [InPlay] = []

        for e in rules.effects where present(s, e) {
            if e.isAlwaysOn {
                if e.oncePer == "battle" && s.usedBattle.contains(e.id) { continue }
                inPlay.append(InPlay(effect: e, opt: nil, slot: nil, always: true))
                continue
            }
            if let a = s.active.first(where: { $0.id == e.id }) {
                inPlay.append(InPlay(effect: e, opt: a.opt, slot: nil, always: false))
                continue
            }
            if e.oncePer == "turning_point" && s.used[e.id] == s.tp {
                spent.append(SpentCard(id: e.id, name: e.name, kindLabel: kindLabel(e, slot: nil)))
                continue
            }
            if e.oncePer == "battle" && s.used[e.id] != nil { continue }
            guard usableIn(e, phase: s.phase) else { continue }
            if let need = e.requires?.activeEffect, !activeIds.contains(need) { continue }
            usable.append(usableCard(s, e))
        }

        let vets = veteranInstances(s)
        for slot in ["primary", "secondary", "extra"] {
            guard let id = s.tactics[slot], !id.isEmpty,
                  let t = rules.chapterTactics.first(where: { $0.id == id }) else { continue }
            if slot == "extra" && vets.isEmpty { continue } // no Chapter Veteran on the table
            inPlay.append(InPlay(tactic: t, slot: slot))
        }

        // The selected operative's statuses read like any other rule in play.
        for st in statuses(for: s.op) where s.has(s.op, st.id) {
            inPlay.append(InPlay(status: st))
        }

        // Split what's in play into "for this operative" and "for others".
        var mine: [InPlay] = []
        var elsewhere: [Elsewhere] = []
        for item in inPlay {
            if appliesToSelected(item, s, veterans: vets) {
                mine.append(item)
            } else {
                elsewhere.append(Elsewhere(name: item.name, who: whoFor(item, veterans: vets)))
            }
        }

        usable = usable.filter(\.afford) + usable.filter { !$0.afford }

        return Snapshot(
            team: teamId, tp: s.tp, cp: s.cp, phase: s.phase, roster: s.roster, op: s.op,
            dead: s.dead, equip: s.equip, tactics: s.tactics,
            rosterStatus: rosterStatus(s),
            veterans: vets.compactMap { operative($0)?.name },
            use: grouped(usable, by: { byId[$0.id]?.when ?? .any }),
            active: grouped(mine.map(activeCard), by: { card in mine.first(where: { $0.id == card.id })?.when ?? .any }),
            elsewhere: elsewhere,
            spent: spent,
            weaponNotes: weaponNotes(s, mine),
            summary: s.lastSummary,
            statuses: statuses(for: s.op).map { StatusChip(id: $0.id, name: $0.name, on: s.has(s.op, $0.id)) },
            statusNames: s.statuses.mapValues { set in
                (rules.statuses ?? []).filter { set.contains($0.id) }.map(\.name)
            },
            resource: resourceCounter(s)
        )
    }

    func resourceCounter(_ s: GameState) -> ResourceCounter? {
        guard let r = rules.meta.resource else { return nil }
        var note = "Gained each Strategy phase, discarded at the end of the turning point."
        if let b = r.bonus, (s.resGain ?? resourceGain(s)) > r.gain {
            let who = opById[b.operative]?.name ?? b.operative
            note = "Includes +\(b.gain) for the \(who)" + (b.condition.map { " \($0)" } ?? "") + "."
        }
        return ResourceCounter(name: r.name, short: r.short, value: resource(s), note: note)
    }

    // MARK: use now

    /// Strategy ploys in the Strategy phase; firefight ploys and activatable
    /// equipment in the Firefight phase (core rules: firefight ploys are
    /// spent during the Firefight phase).
    func usableIn(_ e: Effect, phase: Phase) -> Bool {
        switch phase {
        case .strategy: return e.kind == "strategy_ploy"
        case .firefight:
            return e.kind == "firefight_ploy" || (e.kind == "equipment" && !e.isAlwaysOn) || (e.usesResource && !e.isAlwaysOn)
        }
    }

    func usableCard(_ s: GameState, _ e: Effect) -> UsableCard {
        let q = quote(s, e, opt: nil)
        let discount = q.from.map { from in segments("\(from): \(q.condition ?? "")", excluding: e.name) }
        let options = (e.options ?? []).map { o in
            OptionQuote(id: o.id, name: o.name, condition: o.condition ?? "", cp: quote(s, e, opt: o.id).price)
        }
        return UsableCard(
            id: e.id, name: e.name, kind: e.kind, kindLabel: kindLabel(e, slot: nil),
            hint: segments(e.hint ?? e.text, excluding: e.name),
            costBase: e.price, cp: q.price, unit: e.usesResource ? rules.meta.resource?.short ?? "" : "CP",
            afford: (e.usesResource ? resource(s) : s.cp) >= q.price, discount: discount,
            maybe: q.maybe.map { MaybeRoute(from: $0.from, options: $0.options, condition: $0.condition ?? "",
                                             needsOperative: $0.needs.flatMap { opById[$0]?.name }) },
            options: options, disputed: e.disputed ?? false, trigger: e.trigger)
    }

    // MARK: in play

    struct InPlay {
        var id: String
        var name: String
        var kind: String
        var when: When
        var appliesTo: AppliesTo
        var requiresOperative: String?
        var weaponMatch: [String]
        var hint: String
        var grants: [Grant]
        var duration: String
        var always: Bool
        var oncePerBattle: Bool
        var slot: String?
        var disputed: Bool
        var requiresStatus: String?
        var notFor: [String] = []

        init(effect e: Effect, opt: String?, slot: String?, always: Bool) {
            let option = opt.flatMap { o in e.options?.first(where: { $0.id == o }) }
            id = e.id
            name = e.name + (option.map { " · \($0.name)" } ?? "")
            kind = e.kind
            when = e.when ?? .any
            appliesTo = e.appliesTo ?? .team
            requiresOperative = e.requiresOperative
            weaponMatch = e.weaponMatch ?? []
            hint = option?.hint ?? e.hint ?? e.text
            grants = (option?.grantsWeaponRules ?? []) + (e.grantsWeaponRules ?? [])
            duration = e.duration
            self.always = always
            oncePerBattle = e.oncePer == "battle"
            self.slot = slot
            disputed = e.disputed ?? false
            requiresStatus = e.requiresStatus
            notFor = e.notFor ?? []
        }

        init(status st: StatusDef) {
            id = "status.\(st.id)"
            name = st.name
            kind = "status"
            when = .any
            appliesTo = .team // only ever built for the selected operative
            requiresOperative = nil
            weaponMatch = []
            hint = st.hint
            grants = st.grantsWeaponRules ?? []
            duration = "status"
            always = true
            oncePerBattle = false
            slot = nil
            disputed = false
        }

        /// The same item without its status requirement.
        init(copy: InPlay) {
            self = copy
            requiresStatus = nil
        }

        init(tactic t: ChapterTactic, slot: String) {
            id = "tactic.\(t.id)"
            name = t.name
            kind = "chapter_tactic"
            when = t.when ?? .any
            // Primary and secondary tactics are the whole team's; the extra
            // one belongs to the Chapter Veteran who took it.
            appliesTo = slot == "extra" ? .self : .team
            requiresOperative = nil
            weaponMatch = []
            hint = t.hint ?? t.text
            grants = t.grantsWeaponRules ?? []
            duration = "battle"
            always = true
            oncePerBattle = false
            self.slot = slot
            disputed = false
        }
    }

    func appliesToSelected(_ item: InPlay, _ s: GameState, veterans: [String]) -> Bool {
        if let st = item.requiresStatus, !s.has(s.op, st) { return false }
        if item.notFor.contains(typeOf(s.op)) { return false }
        switch item.appliesTo {
        case .team:
            return true
        case .self:
            if item.kind == "chapter_tactic" { return veterans.contains(s.op) }
            return item.requiresOperative.map { typeOf(s.op) == $0 } ?? true
        case .weapons:
            let weapons = operative(s.op)?.weapons ?? []
            return weapons.contains { w in item.weaponMatch.contains { w.name.lowercased().contains($0.lowercased()) } }
        }
    }

    func whoFor(_ item: InPlay, veterans: [String]) -> String {
        if let st = item.requiresStatus {
            let name = rules.statuses?.first(where: { $0.id == st })?.name ?? st
            let base = item.appliesTo == .self ? whoFor(InPlay(copy: item), veterans: veterans) : "operatives"
            return "\(base), while \(name.uppercased())"
        }
        switch item.appliesTo {
        case .self where item.kind == "chapter_tactic":
            return veterans.compactMap { operative($0)?.name }.joined(separator: " / ") + " only"
        case .self:
            return (item.requiresOperative.flatMap { opById[$0]?.name } ?? "its operative") + " only"
        case .weapons:
            return "operatives with a " + item.weaponMatch.joined(separator: " or ")
        case .team:
            let except = item.notFor.compactMap { opById[$0]?.name }
            return except.isEmpty ? "all operatives" : "all operatives except " + except.joined(separator: ", ")
        }
    }

    func activeCard(_ item: InPlay) -> ActiveCard {
        let life: String
        if item.kind == "status" {
            life = "until you clear it"
        } else if item.always {
            life = item.oncePerBattle ? "once per battle" : "always"
        } else {
            switch item.duration {
            case "end_of_turning_point": life = "this turning point"
            case "this_activation", "this_sequence": life = "this activation"
            case "this_counteraction": life = "this counteraction"
            case "battle": life = "all battle"
            default: life = item.duration
            }
        }
        let own = item.name.components(separatedBy: " · ").first
        return ActiveCard(
            id: item.id, name: item.name, kindLabel: kindLabel(kind: item.kind, universal: false, requiresOperative: item.requiresOperative, slot: item.slot),
            hint: segments(item.hint, excluding: own), life: life,
            canEnd: !item.always, canMarkUsed: item.always && item.oncePerBattle, disputed: item.disputed)
    }

    // MARK: weapon notes

    func weaponNotes(_ s: GameState, _ mine: [InPlay]) -> [String: [WeaponNote]] {
        guard let op = operative(s.op) else { return [:] }
        var out: [String: [WeaponNote]] = [:]
        for item in mine {
            for g in item.grants {
                for w in op.weapons where matches(w, g.match) {
                    out[w.name, default: []].append(WeaponNote(rules: g.rules, from: item.name, condition: g.condition))
                }
            }
        }
        return out
    }

    func matches(_ w: Weapon, _ match: [String]) -> Bool {
        match.contains { m in
            switch m {
            case "*": return true
            case "melee": return w.isMelee
            case "ranged": return !w.isMelee
            default: return w.name.lowercased().contains(m.lowercased())
            }
        }
    }

    // MARK: helpers

    func grouped<Card>(_ cards: [Card], by when: (Card) -> When) -> [CardGroup<Card>] {
        When.allCases.compactMap { w in
            let c = cards.filter { when($0) == w }
            return c.isEmpty ? nil : CardGroup(when: w, cards: c)
        }
    }

    func veteranInstances(_ s: GameState) -> [String] {
        s.roster.filter { operative($0)?.chapterVeteran == true && !s.dead.contains($0) }
    }

    func rosterStatus(_ s: GameState) -> RosterStatus {
        let leaderCount = s.roster.filter { leaders.contains(typeOf($0)) }.count
        return RosterStatus(total: s.roster.count, leaders: leaderCount, ok: s.roster.count == rosterSize && leaderCount == 1)
    }

    func kindLabel(_ e: Effect, slot: String?) -> String {
        kindLabel(kind: e.kind, universal: e.universal ?? false, requiresOperative: e.requiresOperative, slot: slot)
    }

    func kindLabel(kind: String, universal: Bool, requiresOperative: String?, slot: String?) -> String {
        var k = kindLabels[kind] ?? kind
        if universal { k = "Universal " + k.lowercased() }
        if let slot { k += " · \(slot)" }
        if let who = requiresOperative, let o = opById[who] { k += " · \(o.name)" }
        return k
    }
}

/// The full text of any rule, for the "tap a name to read it" sheets.
public struct RuleInfo: Equatable {
    public var title: String
    public var kind: String
    public var body: [Segment]
    /// Sub-choices with their conditions (Combat Doctrine's doctrines).
    public var options: [(name: String, text: [Segment])]
    public var version: String?

    public static func == (a: RuleInfo, b: RuleInfo) -> Bool {
        a.title == b.title && a.kind == b.kind && a.body == b.body && a.version == b.version
            && a.options.map(\.name) == b.options.map(\.name)
    }
}

extension Engine {
    /// Full rule text by id: an effect id, or "tactic.<id>" for a chapter tactic.
    public func ruleInfo(_ id: String) -> RuleInfo? {
        let version = rules.meta.rulesVersion
        if id.hasPrefix("tactic."), let t = rules.chapterTactics.first(where: { "tactic.\($0.id)" == id }) {
            return RuleInfo(title: t.name, kind: "Chapter tactic", body: segments(t.text, excluding: t.name),
                            options: [], version: version)
        }
        if id.hasPrefix("status."), let st = rules.statuses?.first(where: { "status.\($0.id)" == id }) {
            return RuleInfo(title: st.name, kind: "Status", body: segments(st.hint, excluding: st.name),
                            options: [], version: version)
        }
        guard let e = byId[id] else { return nil }
        let opts = (e.options ?? []).map { o in
            (name: o.name, text: segments(o.hint ?? o.condition ?? "", excluding: e.name))
        }
        return RuleInfo(title: e.name, kind: kindLabel(e, slot: nil), body: segments(e.text, excluding: e.name),
                        options: opts, version: version)
    }
}
