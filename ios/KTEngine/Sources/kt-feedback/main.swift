import Foundation
import KTEngine

// Reads problem reports made with the app's feedback button.
//
//   swift run kt-feedback                 every report in <repo>/feedback/
//   swift run kt-feedback <file|dir> …    just these
//
// For each report: the note, where the player was, the last events, the screen
// as it was shown, and a replay of the game log on today's rules (with a diff
// when it differs, e.g. after a fix). The screenshot is written beside the
// report as a .jpg, to look at.

let repo: URL = {
    var u = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { u.deleteLastPathComponent() } // main.swift → … → repo root
    return u
}()

func reports(in args: [String]) -> [URL] {
    let fm = FileManager.default
    let targets = args.isEmpty ? [repo.appendingPathComponent("feedback")] : args.map { URL(fileURLWithPath: $0) }
    var out: [URL] = []
    for t in targets {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: t.path, isDirectory: &isDir) else {
            print("not found: \(t.path)")
            continue
        }
        if isDir.boolValue {
            let files = (try? fm.contentsOfDirectory(at: t, includingPropertiesForKeys: nil)) ?? []
            out += files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        } else {
            out.append(t)
        }
    }
    return out
}

func render(_ e: Event) -> String {
    let p = e.p
    let parts: [String?] = [p.id.map { "id=\($0)" }, p.opt.map { "opt=\($0)" }, p.slot.map { "slot=\($0)" },
                            p.d.map { "d=\($0)" }, p.phase.map { "phase=\($0.rawValue)" }, p.ini.map { "ini=\($0.rawValue)" }]
    return ([e.t.rawValue] + parts.compactMap { $0 }).joined(separator: " ")
}

/// Line diff (longest common subsequence): "- " only in `a`, "+ " only in `b`.
func diff(_ a: [String], _ b: [String]) -> [String] {
    let n = a.count, m = b.count
    var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
    for i in stride(from: n - 1, through: 0, by: -1) {
        for j in stride(from: m - 1, through: 0, by: -1) {
            lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
        }
    }
    var out: [String] = []
    var i = 0, j = 0
    while i < n || j < m {
        if i < n, j < m, a[i] == b[j] {
            out.append("  " + a[i]); i += 1; j += 1
        } else if j < m, i == n || lcs[i][j + 1] >= lcs[i + 1][j] {
            out.append("+ " + b[j]); j += 1
        } else {
            out.append("- " + a[i]); i += 1
        }
    }
    return out
}

let core: CoreGlossary
do {
    core = try CoreGlossary.load(from: repo.appendingPathComponent("data/core/glossary.json"))
} catch {
    print("can't load data/core/glossary.json: \(error)")
    exit(1)
}

let files = reports(in: Array(CommandLine.arguments.dropFirst()))
if files.isEmpty { print("No reports. Put the .json files from the phone in \(repo.appendingPathComponent("feedback").path)/") }

for url in files {
    print("━━ \(url.lastPathComponent)")
    let report: FeedbackReport
    do {
        report = try JSONDecoder().decode(FeedbackReport.self, from: Data(contentsOf: url))
    } catch {
        print("not a feedback report: \(error)\n")
        continue
    }
    print("Note:   \(report.note)")
    print("Where:  \(report.screen)")
    print("When:   \(report.created) · app \(report.app.version) (\(report.app.build)) commit \(report.app.commit) · \(report.app.device)")
    print("Game:   \(report.game.team) · \(report.game.events.count) events · rules \(report.rulesVersion ?? "?")")
    if let jpg = report.screenshotData {
        let out = url.deletingPathExtension().appendingPathExtension("jpg")
        do {
            try jpg.write(to: out)
            print("Screenshot: \(out.path)")
        } catch {
            print("Screenshot: couldn't write \(out.path): \(error)")
        }
    }

    let events = report.game.events
    let tail = 25
    print("\n-- Last events" + (events.count > tail ? " (\(tail) of \(events.count))" : ""))
    for (i, e) in events.enumerated().suffix(tail) { print(String(format: "%4d ", i + 1) + render(e)) }

    if let ui = report.ui, !ui.isEmpty {
        print("\n-- View state\n" + ui.sorted { $0.key < $1.key }.map { "\($0.key) = \($0.value)" }.joined(separator: "\n"))
    }
    print("\n-- Shown on the phone\n\(report.shown)")

    let census = repo.appendingPathComponent("data/teams/\(report.game.team).json")
    guard let rules = try? RulesData.load(from: census) else {
        print("\n-- Replay: no census at \(census.path)\n")
        continue
    }
    let engine = Engine(teamId: report.game.team, rules: rules, core: core)
    let now = engine.describe(engine.derive(engine.fold(events), logLength: events.count))
    if now == report.shown {
        print("\n-- Replayed on today's rules and code: the same as shown.\n")
    } else {
        print("\n-- Replayed on today's rules and code: differs (- shown on the phone, + now)")
        print(diff(report.shown.components(separatedBy: "\n"), now.components(separatedBy: "\n"))
            .filter { !$0.hasPrefix("  ") }.joined(separator: "\n") + "\n")
    }
}
