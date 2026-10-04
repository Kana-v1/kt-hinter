import XCTest
@testable import KTEngine

/// A report sent from the phone has to replay to exactly what the player saw.
final class FeedbackTests: XCTestCase {
    func game() -> GameLog {
        GameLog(team: "plague_marines", events: [
            ev(.roster, Params(id: "plague_marine_warrior")),
            ev(.phase, Params(phase: .firefight)),
            ev(.op, Params(id: "plague_marine_warrior")),
        ])
    }

    func testReportRoundTripsAndReplaysToWhatWasShown() throws {
        let e = Repo.engine("plague_marines")
        let log = game()
        let shown = e.describe(e.derive(e.fold(log.events), logLength: log.events.count))
        let report = FeedbackReport(note: "Repulsive Fortitude looks wrong", screen: "Game",
                                    app: .init(version: "0.1", build: "1", commit: "dev", device: "test"),
                                    rulesVersion: e.rules.meta.rulesVersion, game: log, shown: shown,
                                    ui: ["fold.use": "open"], screenshot: Data([0xFF, 0xD8, 0xFF]))
        let back = try JSONDecoder().decode(FeedbackReport.self, from: JSONEncoder().encode(report))
        XCTAssertEqual(back.kind, FeedbackReport.kindTag)
        XCTAssertEqual(back.game, log)
        XCTAssertEqual(back.ui, ["fold.use": "open"])
        XCTAssertEqual(back.screenshotData, Data([0xFF, 0xD8, 0xFF]))
        XCTAssertEqual(e.describe(e.derive(e.fold(back.game.events), logLength: back.game.events.count)), shown)
    }

    func testDescribeCoversTheScreen() {
        let e = Repo.engine("plague_marines")
        let text = e.describe(e.derive(e.fold(game().events)))
        XCTAssertTrue(text.hasPrefix("TP 1 of 4 · Firefight · 3 CP"), text)
        XCTAssertTrue(text.contains("Acting: Plague Marine Warrior"), text)
        XCTAssertTrue(text.contains("## Use now"), text)
        XCTAssertTrue(text.contains("Repulsive Fortitude"), text)
        XCTAssertTrue(text.contains("## Weapons of Plague Marine Warrior"), text)
    }
}
