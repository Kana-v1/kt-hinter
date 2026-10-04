import Foundation
import SwiftUI
import UIKit
import KTEngine

struct TeamInfo: Identifiable, Hashable {
    let id: String
    let name: String
}

/// Owns the current game. Every tap is one event: append, re-fold, re-derive,
/// save. There is no server; the rules engine runs on the phone.
@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var game: GameLog
    @Published private(set) var snapshot: Snapshot
    /// "Fighter is acting — Sickening Resilience ended." after a new activation.
    @Published var toast: String?
    /// Bumped when operative photos change, so views re-read them.
    @Published private(set) var photoVersion = 0
    /// Problem reports saved on the phone (Feedback.swift), newest first.
    @Published private(set) var feedback: [FeedbackItem] = []
    private var photoCache: [String: UIImage] = [:]

    let teams: [TeamInfo]
    private let engines: [String: Engine]

    var engine: Engine { engines[game.team]! }
    var rules: RulesData { engine.rules }
    var state: GameState { engine.fold(game.events) }

    private static let saveURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("game.json")
    }()

    init() {
        let (engines, teams) = GameStore.loadRules()
        self.engines = engines
        self.teams = teams
        var game = GameStore.loadGame() ?? GameLog(team: teams.first?.id ?? "aod")
        if engines[game.team] == nil { game = GameLog(team: teams.first?.id ?? "aod") }
        self.game = game
        let engine = engines[game.team]!
        snapshot = engine.derive(engine.fold(game.events), logLength: game.events.count)
        feedback = FeedbackFiles.list()
        Log.write("loaded \(teams.count) teams; game \(game.team) with \(game.events.count) events", "store")
    }

    // MARK: actions

    func send(_ event: Event) {
        let before = state
        game.append(event)
        refresh()
        if event.t == .op, let id = event.p.id, id != before.op {
            announceNewActivation(before: before, now: id)
        }
    }

    func undo() {
        game.undo()
        toast = nil
        refresh()
    }

    func resetGame() {
        game.reset()
        refresh()
    }

    /// A game is bound to one team, so switching team starts a new game.
    func switchTeam(_ team: String) {
        guard team != game.team, engines[team] != nil else { return }
        game = GameLog(team: team)
        refresh()
    }

    private func announceNewActivation(before: GameState, now id: String) {
        let ended = before.active.filter { a in !state.active.contains(where: { $0.id == a.id }) }
            .compactMap { engine.effect($0.id)?.name }
        guard !ended.isEmpty, let op = engine.operative(id) else { return }
        toast = "\(op.name) is acting — \(ended.joined(separator: ", ")) ended."
    }

    func reloadFeedback() { feedback = FeedbackFiles.list() }

    private func refresh() {
        snapshot = engine.derive(state, logLength: game.events.count)
        save()
    }

    // MARK: operative photos
    //
    // The player's own pictures (or crops they made from their rules PDFs),
    // kept on the phone only: Documents/photos/<operative id>.png. Operative ids
    // are unique across teams, so one folder serves every team.

    private static let photosDir: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("photos")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func photo(for operativeId: String) -> UIImage? {
        if let img = photoCache[operativeId] { return img }
        let url = GameStore.photosDir.appendingPathComponent("\(operativeId).png")
        guard let img = UIImage(contentsOfFile: url.path) else { return nil }
        photoCache[operativeId] = img
        return img
    }

    @discardableResult
    func setPhoto(_ data: Data, for operativeId: String, fit: Bool = false) -> Bool {
        guard let img = UIImage(data: data) else {
            Log.write("photo for \(operativeId): not an image", "photos")
            return false
        }
        return setPhoto(img, for: operativeId, fit: fit)
    }

    @discardableResult
    func setPhoto(_ img: UIImage, for operativeId: String, fit: Bool = false) -> Bool {
        guard let png = GameStore.square(img, side: 256, fit: fit).pngData() else {
            Log.write("photo for \(operativeId): not an image", "photos")
            return false
        }
        do {
            try png.write(to: GameStore.photosDir.appendingPathComponent("\(operativeId).png"), options: .atomic)
            photoCache[operativeId] = UIImage(data: png)
            photoVersion += 1
            return true
        } catch {
            Log.write("saving photo for \(operativeId) failed: \(error)", "photos")
            return false
        }
    }

    func removePhoto(for operativeId: String) {
        try? FileManager.default.removeItem(at: GameStore.photosDir.appendingPathComponent("\(operativeId).png"))
        photoCache[operativeId] = nil
        photoVersion += 1
    }

    /// Team symbols live beside the photos as team_<team id>.png, kept square
    /// and transparent (fitted, not cropped).
    func teamSymbol(for team: String) -> UIImage? { photo(for: "team_\(team)") }

    /// Sets the current team's symbol from any image, whatever its file name.
    func setTeamSymbol(_ data: Data) { setPhoto(data, for: "team_\(game.team)", fit: true) }

    func removeTeamSymbol() { removePhoto(for: "team_\(game.team)") }

    /// Imports image files whose names end with an operative id
    /// ("my_champion_plague_marine_champion.png", or just "plague_marine_champion.png",
    /// or the operative's name) or a team id for its symbol ("ci_celestian_insidiants.png").
    /// Returns how many matched.
    @discardableResult
    func importPhotos(from urls: [URL]) -> (matched: Int, unmatched: [String]) {
        var matched = 0
        var unmatched: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let stem = url.deletingPathExtension().lastPathComponent
            guard let id = operativeId(matching: stem), let data = try? Data(contentsOf: url),
                  setPhoto(data, for: id, fit: id.hasPrefix("team_")) else {
                unmatched.append(url.lastPathComponent)
                continue
            }
            matched += 1
        }
        Log.write("imported \(matched) photos; unmatched: \(unmatched)", "photos")
        return (matched, unmatched)
    }

    /// Picks up images dropped into the app's folder (Files app → On My iPhone
    /// → Kill Team), assigns them, and removes the originals.
    func importDroppedPhotos() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let files = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []
        let images = files.filter { ["png", "jpg", "jpeg", "heic", "webp"].contains($0.pathExtension.lowercased()) }
        guard !images.isEmpty else { return }
        let before = photoVersion
        let result = importPhotos(from: images)
        for url in images where operativeId(matching: url.deletingPathExtension().lastPathComponent) != nil {
            try? FileManager.default.removeItem(at: url)
        }
        if photoVersion != before { toast = "Added \(result.matched) operative photo\(result.matched == 1 ? "" : "s")." }
    }

    /// The photo slot a file name points at: an operative id or "team_<id>".
    /// The name must be the id or end with "_<id>"; the longest id wins, so
    /// "…_plague_marine_warrior" isn't taken for a shorter id it ends with.
    private func operativeId(matching stem: String) -> String? {
        let key = GameStore.slug(stem)
        var slots: [(id: String, slot: String)] = []
        for (team, engine) in engines {
            slots.append((team, "team_\(team)"))
            for op in engine.rules.operatives {
                if GameStore.slug(op.name) == key { return op.id }
                slots.append((op.id, op.id))
            }
        }
        return slots.filter { key == $0.id || key.hasSuffix("_" + $0.id) }
            .max { $0.id.count < $1.id.count }?.slot
    }

    private static func slug(_ s: String) -> String {
        s.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" }
            .reduce(into: "") { out, c in if !(c == "_" && out.last == "_") { out.append(c) } }
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    /// Centre-cropped square (or the whole image fitted inside it), `side` points at 1x.
    private static func square(_ img: UIImage, side: CGFloat, fit: Bool = false) -> UIImage {
        let s = fit ? max(img.size.width, img.size.height) : min(img.size.width, img.size.height)
        let scale = side / s
        let drawSize = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            img.draw(in: CGRect(x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2,
                                width: drawSize.width, height: drawSize.height))
        }
    }

    // MARK: persistence (best-effort: never crash over a file)

    private func save() {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(game).write(to: GameStore.saveURL, options: .atomic)
        } catch {
            Log.write("save failed: \(error)", "store")
        }
    }

    private static func loadGame() -> GameLog? {
        guard let data = try? Data(contentsOf: saveURL) else { return nil }
        do {
            return try JSONDecoder().decode(GameLog.self, from: data)
        } catch {
            Log.write("saved game unreadable, starting fresh: \(error)", "store")
            return nil
        }
    }

    /// The censuses ship in the app bundle: teams/<id>.json and core/glossary.json.
    private static func loadRules() -> ([String: Engine], [TeamInfo]) {
        guard let coreURL = Bundle.main.url(forResource: "glossary", withExtension: "json", subdirectory: "core"),
              let core = try? CoreGlossary.load(from: coreURL) else {
            fatalError("core/glossary.json missing from the app bundle")
        }
        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "teams") ?? []
        var engines: [String: Engine] = [:]
        var teams: [TeamInfo] = []
        for url in urls {
            let id = url.deletingPathExtension().lastPathComponent
            do {
                let rules = try RulesData.load(from: url)
                engines[id] = Engine(teamId: id, rules: rules, core: core)
                teams.append(TeamInfo(id: id, name: rules.meta.team))
            } catch {
                Log.write("could not load \(id).json: \(error)", "store")
            }
        }
        precondition(!engines.isEmpty, "no team censuses in the app bundle")
        return (engines, teams.sorted { $0.name < $1.name })
    }
}
