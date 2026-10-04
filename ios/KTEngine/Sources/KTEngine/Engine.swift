import Foundation

// The event log is the state. Every change is an Event; State is fold(events).
// Undo is "drop the last event and re-fold". Expiry is never an event: an effect
// simply stops being in `active` when the turning point advances or a new
// operative starts acting. Never add subtract-on-expiry logic.

public enum Phase: String, Codable {
    case strategy, firefight
}

public struct Event: Codable, Equatable {
    public var t: Kind
    public var p: Params

    public init(_ t: Kind, _ p: Params = Params()) {
        self.t = t
        self.p = p
    }

    public enum Kind: String, Codable {
        case phase = "PHASE"
        case cp = "CP"
        case tpNext = "TP_NEXT"
        case tpPrev = "TP_PREV"
        case tpReset = "TP_RESET"
        case activate = "ACTIVATE"
        case end = "END"
        case useBattle = "USE_BATTLE"
        case op = "OP"
        case down = "DOWN"
        case leader = "LEADER"
        case roster = "ROSTER"
        case count = "COUNT"
        case equip = "EQUIP"
        case tactic = "TACTIC"
        case clearSummary = "CLEAR_SUMMARY"
        /// Toggle status `opt` on operative instance `id`.
        case status = "STATUS"
        /// Gain (d > 0) or spend (d < 0) the team's resource by hand.
        case res = "RES"
    }
}

public struct Params: Codable, Equatable {
    public var phase: Phase?
    public var d: Int?
    public var id: String?
    public var opt: String?
    public var slot: String?
    /// TP_NEXT: who has initiative for the new turning point.
    public var ini: Initiative?

    public init(phase: Phase? = nil, d: Int? = nil, id: String? = nil, opt: String? = nil,
                slot: String? = nil, ini: Initiative? = nil) {
        self.phase = phase
        self.d = d
        self.id = id
        self.opt = opt
        self.slot = slot
        self.ini = ini
    }
}

public enum Initiative: String, Codable {
    case us, them
}

public struct ActiveEntry: Equatable {
    public var id: String
    public var opt: String?
    public var tp: Int
    public var seq: Int
}

/// Something paid for this turning point, for the end-of-TP recap.
public struct Paid: Equatable {
    public var id: String
    public var name: String
    public var opt: String?
    /// The price, in `unit`.
    public var cp: Int
    /// "CP", or the team resource's short name.
    public var unit = "CP"
}

public struct Summary: Equatable {
    public var tp: Int
    public var paid: [Paid]
}

public struct GameState {
    public var tp = 1
    // Core rules: 2CP at the start, +1 in the first Strategy phase.
    public var cp = 3
    public var phase = Phase.strategy
    public var roster: [String] = []
    public var op = ""
    public var dead: Set<String> = []
    public var equip: Set<String> = []
    public var tactics: [String: String] = [:]
    public var active: [ActiveEntry] = []
    public var used: [String: Int] = [:]
    public var usedBattle: Set<String> = []
    public var usedTp: [String: Int] = [:]
    public var paid: [Paid] = []
    public var lastSummary: Summary?
    public var seq = 0
    /// Operative instance → status ids (INSPIRING, Benedictions).
    public var statuses: [String: Set<String>] = [:]
    /// The team resource gained this turning point, fixed when the Firefight
    /// phase starts. Nil while it still follows the roster (Strategy phase).
    public var resGain: Int?
    /// The resource gained or spent this turning point, by hand or on effects.
    public var resAdj = 0

    public func has(_ inst: String, _ status: String) -> Bool {
        statuses[inst]?.contains(status) ?? false
    }
}

/// Durations that end when a different operative starts acting.
let activationScoped: Set<String> = ["this_activation", "this_sequence", "this_counteraction"]

/// "intercessor_warrior#2" → "intercessor_warrior".
public func typeOf(_ inst: String) -> String {
    inst.split(separator: "#", maxSplits: 1).first.map(String.init) ?? inst
}

public final class Engine {
    public let teamId: String
    public let rules: RulesData
    let byId: [String: Effect]
    let opById: [String: Operative]
    let leaders: Set<String>
    public let defaultRoster: [String]
    public let rosterSize: Int
    let glossary: Glossary

    public init(teamId: String, rules: RulesData, core: CoreGlossary) {
        self.teamId = teamId
        self.rules = rules
        byId = Dictionary(rules.effects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        opById = Dictionary(rules.operatives.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        leaders = Set(rules.operatives.filter(\.leader).map(\.id))
        defaultRoster = Engine.resolveDefaultRoster(rules)
        rosterSize = rules.meta.rosterSize ?? 6
        glossary = Glossary(core: core, rules: rules)
    }

    /// The team's declared starting roster, or its leader plus the first specialists.
    static func resolveDefaultRoster(_ rules: RulesData) -> [String] {
        if let r = rules.meta.defaultRoster, !r.isEmpty { return r }
        let leader = rules.operatives.first(where: \.leader).map { [$0.id] } ?? []
        return Array((leader + rules.operatives.filter { !$0.leader }.map(\.id)).prefix(rules.meta.rosterSize ?? 6))
    }

    public func effect(_ id: String) -> Effect? { byId[id] }
    public func operative(_ inst: String) -> Operative? { opById[typeOf(inst)] }

    /// How many of this operative type a roster may hold.
    public func maxCount(_ type: String) -> Int {
        guard let o = opById[type] else { return 0 }
        if let m = o.max { return m }
        return o.multiple ? rosterSize : 1
    }

    /// Statuses this operative type can have.
    public func statuses(for inst: String) -> [StatusDef] {
        (rules.statuses ?? []).filter { !($0.notFor ?? []).contains(typeOf(inst)) }
    }

    // MARK: fold

    public func blank() -> GameState {
        var s = GameState()
        s.roster = defaultRoster
        s.op = defaultRoster.first ?? ""
        s.tactics = ["primary": "", "secondary": "", "extra": ""]
        return s
    }

    public func fold(_ events: [Event]) -> GameState {
        var s = blank()
        for e in events { apply(&s, e) }
        return s
    }

    /// The only place State changes.
    func apply(_ s: inout GameState, _ ev: Event) {
        let p = ev.p
        switch ev.t {
        case .phase:
            guard let ph = p.phase else { return }
            // the Strategy phase's gain is settled once the firefight starts
            if ph == .firefight, s.resGain == nil, rules.meta.resource != nil { s.resGain = resourceGain(s) }
            s.phase = ph

        case .cp:
            s.cp = max(0, s.cp + (p.d ?? 0))

        case .res:
            s.resAdj += max(p.d ?? 0, -resource(s))

        case .tpNext:
            s.lastSummary = s.paid.isEmpty ? nil : Summary(tp: s.tp, paid: s.paid)
            s.tp += 1
            // Core rules: initiative gains 1CP, the other player gains 2CP.
            s.cp += p.ini == .them ? 2 : 1
            clearTurningPoint(&s)

        case .tpPrev:
            if s.tp > 1 {
                s.tp -= 1
                s.lastSummary = nil
            }

        case .tpReset:
            clearTurningPoint(&s)
            s.lastSummary = nil

        case .activate:
            guard let id = p.id, let e = byId[id] else { return }
            let q = quote(s, e, opt: p.opt)
            if e.usesResource { s.resAdj -= min(q.price, resource(s)) } else { s.cp = max(0, s.cp - q.price) }
            s.used[e.id] = s.tp
            if let key = q.key, q.once == "battle" { s.usedBattle.insert(key) }
            if let key = q.key, q.once == "turning_point" { s.usedTp[key] = s.tp }
            let optName = p.opt.flatMap { o in e.options?.first(where: { $0.id == o })?.name }
            s.paid.append(Paid(id: e.id, name: e.name + (optName.map { " · \($0)" } ?? ""), opt: p.opt, cp: q.price,
                               unit: e.usesResource ? rules.meta.resource?.short ?? "" : "CP"))
            if let target = e.changesOptionOf {
                for i in s.active.indices where s.active[i].id == target { s.active[i].opt = p.opt }
            } else if e.duration != "instant" {
                s.seq += 1
                s.active.append(ActiveEntry(id: e.id, opt: p.opt, tp: s.tp, seq: s.seq))
            }

        case .end:
            s.active.removeAll { $0.id == p.id }

        case .useBattle:
            if let id = p.id { s.usedBattle.insert(id) }

        case .op:
            guard let id = p.id else { return }
            // A different operative acting means a new activation.
            if id != s.op {
                s.active.removeAll { activationScoped.contains(byId[$0.id]?.duration ?? "") }
            }
            s.op = id

        case .down:
            guard let id = p.id else { return }
            if s.dead.contains(id) { s.dead.remove(id) } else { s.dead.insert(id) }

        case .leader:
            guard let id = p.id else { return }
            let had = s.roster.contains { typeOf($0) == id }
            for x in s.roster where leaders.contains(typeOf(x)) { s.dead.remove(x) }
            s.roster.removeAll { leaders.contains(typeOf($0)) }
            if !had { s.roster.insert(id, at: 0) }
            ensureOp(&s)

        case .roster:
            guard let id = p.id else { return }
            if s.roster.contains(id) { s.roster.removeAll { $0 == id } } else { s.roster.append(id) }
            ensureOp(&s)

        case .count:
            guard let id = p.id else { return }
            if (p.d ?? 0) > 0 {
                guard s.roster.filter({ typeOf($0) == id }).count < maxCount(id) else { return }
                var n = 1
                while s.roster.contains("\(id)#\(n)") { n += 1 }
                s.roster.append("\(id)#\(n)")
            } else if let drop = s.roster.last(where: { typeOf($0) == id }) {
                s.roster.removeAll { $0 == drop }
                s.dead.remove(drop)
            }
            ensureOp(&s)

        case .equip:
            guard let id = p.id else { return }
            if s.equip.contains(id) { s.equip.remove(id) } else { s.equip.insert(id) }

        case .tactic:
            guard let id = p.id, let slot = p.slot else { return }
            if s.tactics[slot] == id {
                s.tactics[slot] = ""
            } else {
                s.tactics[slot] = id
                for other in ["primary", "secondary", "extra"] where other != slot && s.tactics[other] == id {
                    s.tactics[other] = ""
                }
            }

        case .clearSummary:
            s.lastSummary = nil

        case .status:
            guard let st = p.opt else { return }
            let inst = p.id ?? s.op
            guard s.roster.contains(inst), statuses(for: inst).contains(where: { $0.id == st }) else { return }
            if s.has(inst, st) { s.statuses[inst]?.remove(st) } else { s.statuses[inst, default: []].insert(st) }
        }
        // A status belongs to an operative on the roster.
        s.statuses = s.statuses.filter { s.roster.contains($0.key) && !$0.value.isEmpty }
    }

    func clearTurningPoint(_ s: inout GameState) {
        s.active = []
        s.used = [:]
        s.usedTp = [:]
        s.paid = []
        s.phase = .strategy
        // the resource is discarded at the end of each turning point
        s.resGain = nil
        s.resAdj = 0
    }

    /// The resource a Strategy phase gives: the base gain, plus the bonus
    /// while its operative is on the roster and not incapacitated.
    func resourceGain(_ s: GameState) -> Int {
        guard let r = rules.meta.resource else { return 0 }
        guard let b = r.bonus, s.roster.contains(where: { typeOf($0) == b.operative && !s.dead.contains($0) }) else { return r.gain }
        return r.gain + b.gain
    }

    /// The team resource on hand now.
    public func resource(_ s: GameState) -> Int {
        guard rules.meta.resource != nil else { return 0 }
        return max(0, (s.resGain ?? resourceGain(s)) + s.resAdj)
    }

    func ensureOp(_ s: inout GameState) {
        if !s.roster.contains(s.op) { s.op = s.roster.first ?? "" }
    }

    // MARK: presence and price

    /// An effect exists only while its operative is on the table and up, and
    /// equipment only if it was taken.
    func present(_ s: GameState, _ e: Effect) -> Bool {
        if e.kind == "equipment" && !s.equip.contains(e.id) { return false }
        guard let who = e.requiresOperative else { return true }
        return s.roster.contains { typeOf($0) == who && !s.dead.contains($0) }
    }

    struct Route {
        var price: Int
        var condition: String?
        var from: String
        var options: [String]?
        var key: String?
        var once: String?
        var disputed: Bool
        var inactive: Bool
        var needs: String?
    }

    struct Quote {
        var price: Int
        var condition: String?
        var from: String?
        var key: String?
        var once: String?
        var maybe: [Route] = []
    }

    /// Every cost override that could apply to `e` right now.
    func routes(_ s: GameState, _ e: Effect, opt: String?) -> [Route] {
        var out: [Route] = []
        for p in rules.effects where present(s, p) {
            if p.kind == "equipment" && s.used[p.id] == s.tp { continue }
            for ov in p.overrides {
                if let target = ov.effect, target != e.id { continue }
                if let k = ov.kind, k != e.kind { continue }
                if ov.excludes?.contains(e.id) == true { continue }
                if let opts = ov.options, let o = opt, !opts.contains(o) { continue }
                let wrongOperative = ov.selectedIs.map { typeOf(s.op) != $0 } ?? false
                // the operative granting it must have the status (if the player hasn't set it, a hint)
                let missingStatus = ov.requiresStatus.map { st in
                    !s.roster.contains { typeOf($0) == p.requiresOperative && !s.dead.contains($0) && s.has($0, st) }
                } ?? false
                // a shared group means one use covers every option of that ability
                let scope = ov.group ?? "\(e.id)|\(ov.options != nil ? (opt ?? "*") : "*")"
                let key = ov.oncePer != nil ? "\(p.id)|\(scope)" : nil
                if let key, ov.oncePer == "battle", s.usedBattle.contains(key) { continue }
                if let key, ov.oncePer == "turning_point", s.usedTp[key] == s.tp { continue }
                out.append(Route(price: ov.price, condition: ov.condition, from: p.name, options: ov.options,
                                 key: key, once: ov.oncePer, disputed: p.disputed ?? false,
                                 inactive: wrongOperative || missingStatus, needs: ov.selectedIs))
            }
        }
        return out
    }

    /// The price to charge and why. Option-specific or wrong-operative routes
    /// don't move the headline; they come back as "can be free" hints.
    func quote(_ s: GameState, _ e: Effect, opt: String?) -> Quote {
        var best = Quote(price: e.price)
        var maybe: [Route] = []
        for r in routes(s, e, opt: opt) {
            let firm = !r.inactive && (r.options == nil || (opt.map { r.options!.contains($0) } ?? false))
            if !firm {
                maybe.append(r)
            } else if r.price < best.price {
                best = Quote(price: r.price, condition: r.condition, from: r.from, key: r.key, once: r.once)
            }
        }
        best.maybe = maybe
        return best
    }
}
