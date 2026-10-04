import Foundation

/// A problem report written on the phone mid-game: the player's note plus the
/// app's state. The whole game log rides along, so the state replays exactly
/// (state is fold(events)); `shown` is everything derived from it as text, `ui`
/// the view state the log doesn't hold, and `screenshot` an optional base64 JPEG.
/// `swift run kt-feedback` reads these on the PC.
public struct FeedbackReport: Codable {
    public static let kindTag = "kt-feedback"

    public var kind: String
    public var format: Int
    public var id: String
    /// ISO 8601.
    public var created: String
    public var note: String
    /// Where the player was: "Game", "Operative sheet: Plague Champion", "Rule: Plague Rounds (pm.…)".
    public var screen: String
    public var app: AppInfo
    public var rulesVersion: String?
    public var game: GameLog
    /// `Engine.describe` of the snapshot on screen when the report was made.
    public var shown: String
    /// View state outside the game log: which blocks are folded, for instance.
    public var ui: [String: String]?
    /// The newest lines of the app's diagnostic log.
    public var log: String?
    public var screenshot: String?

    public struct AppInfo: Codable, Equatable {
        public var version: String
        public var build: String
        /// The git commit CI built the app from ("dev" for a local build).
        public var commit: String
        public var device: String

        public init(version: String, build: String, commit: String, device: String) {
            self.version = version
            self.build = build
            self.commit = commit
            self.device = device
        }
    }

    public init(id: String = UUID().uuidString, created: Date = Date(), note: String, screen: String,
                app: AppInfo, rulesVersion: String?, game: GameLog, shown: String,
                ui: [String: String]? = nil, log: String? = nil, screenshot: Data? = nil) {
        kind = FeedbackReport.kindTag
        format = 1
        self.id = id
        self.created = ISO8601DateFormatter().string(from: created)
        self.note = note
        self.screen = screen
        self.app = app
        self.rulesVersion = rulesVersion
        self.game = game
        self.shown = shown
        self.ui = ui
        self.log = log
        self.screenshot = screenshot?.base64EncodedString()
    }

    public var screenshotData: Data? { screenshot.flatMap { Data(base64Encoded: $0) } }
}

extension Engine {
    /// Everything the game screen and the operative sheet show, as plain text:
    /// the same snapshot always gives the same text, so a report's `shown` can
    /// be compared line by line with a replay on today's rules.
    public func describe(_ s: Snapshot) -> String {
        var out: [String] = []
        func plain(_ segs: [Segment]) -> String { segs.map(\.t).joined() }
        func instName(_ inst: String) -> String {
            let name = operative(inst)?.name ?? inst
            guard let n = inst.split(separator: "#").dropFirst().first else { return name }
            return "\(name) #\(n)"
        }

        out.append("TP \(s.tp) of 4 · \(s.phase.rawValue.capitalized) · \(s.cp) CP")
        if !s.op.isEmpty {
            var acting = "Acting: \(instName(s.op))"
            if s.dead.contains(s.op) { acting += " (incapacitated)" }
            out.append(acting)
        }
        let on = s.statuses.filter(\.on).map(\.name)
        if !on.isEmpty { out.append("Statuses: " + on.joined(separator: ", ")) }
        out.append("Roster (\(s.rosterStatus.total), \(s.rosterStatus.leaders) leader, \(s.rosterStatus.ok ? "legal" : "not legal")): "
                   + s.roster.map { instName($0) + (s.dead.contains($0) ? " (down)" : "")
                                    + ((s.statusNames[$0] ?? []).isEmpty ? "" : " [\(s.statusNames[$0]!.joined(separator: ", "))]") }
                       .joined(separator: ", "))
        if !s.equip.isEmpty {
            out.append("Equipment: " + s.equip.sorted().map { effect($0)?.name ?? $0 }.joined(separator: ", "))
        }
        let tactics = s.tactics.filter { !$0.value.isEmpty }
        if !tactics.isEmpty {
            out.append("Chapter tactics: " + tactics.sorted { $0.key < $1.key }.map { slot, id in
                "\(slot) \(rules.chapterTactics.first { $0.id == id }?.name ?? id)"
            }.joined(separator: ", "))
        }

        out.append("")
        out.append("## Use now")
        if s.use.isEmpty { out.append("(nothing)") }
        for group in s.use {
            out.append("### \(group.when.title)")
            for c in group.cards {
                var line = "- \(c.name) · \(c.kindLabel) · "
                line += c.free ? "free" : "\(c.cp) CP"
                if c.reduced { line += " (was \(c.costBase))" }
                if !c.afford { line += " · can't afford" }
                if c.disputed { line += " · Unverified" }
                if let t = c.trigger { line += " · offered when \(t)" }
                out.append(line)
                out.append("  \(plain(c.hint))")
                if let d = c.discount { out.append("  discount: \(plain(d))") }
                for m in c.maybe {
                    out.append("  can be free: \(m.from)" + (m.options.map { " (\($0.joined(separator: ", ")))" } ?? "")
                               + (m.condition.isEmpty ? "" : " — \(m.condition)"))
                }
                for o in c.options {
                    out.append("  option \(o.name): \(o.cp) CP" + (o.condition.isEmpty ? "" : " — \(o.condition)"))
                }
            }
        }

        out.append("")
        out.append("## Active on \(s.op.isEmpty ? "operative" : instName(s.op))")
        if s.active.isEmpty { out.append("(nothing)") }
        for group in s.active {
            out.append("### \(group.when.title)")
            for c in group.cards {
                var line = "- \(c.name) · \(c.kindLabel) · \(c.life)"
                if c.canEnd { line += " · can end" }
                if c.canMarkUsed { line += " · can mark used" }
                if c.disputed { line += " · Unverified" }
                out.append(line)
                out.append("  \(plain(c.hint))")
            }
        }

        if let op = operative(s.op) {
            out.append("")
            out.append("## Weapons of \(op.name)")
            for w in op.weapons {
                let notes = (s.weaponNotes[w.name] ?? []).map { n in
                    n.rules.map { "+\($0)" }.joined(separator: " ") + " (\(n.from))"
                        + (n.condition.map { " if \($0)" } ?? "")
                }
                out.append("- \(w.name)" + (notes.isEmpty ? "" : ": " + notes.joined(separator: "; ")))
            }
        }

        if !s.elsewhere.isEmpty {
            out.append("")
            out.append("Elsewhere: " + s.elsewhere.map { "\($0.name) (\($0.who))" }.joined(separator: ", "))
        }
        if !s.spent.isEmpty {
            out.append("Used this turning point: " + s.spent.map(\.name).joined(separator: ", "))
        }
        if let sum = s.summary {
            out.append("Recap showing for TP \(sum.tp): " + sum.paid.map { "\($0.name) \($0.cp) CP" }.joined(separator: ", "))
        }
        return out.joined(separator: "\n")
    }
}
