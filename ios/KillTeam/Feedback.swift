import SwiftUI
import UIKit
import KTEngine

// Report a problem from any screen, mid-game: a note plus the app's state (the
// whole game log, the screen as text, view state) and optionally a screenshot.
// Reports are saved on the phone the moment they're made and never deleted
// except by the player; Setup → Feedback sends them on. On the PC,
// `swift run kt-feedback` replays them.

/// The app's state, taken when the report button is tapped, before the
/// feedback sheet covers the screen.
struct FeedbackCapture: Identifiable {
    let id = UUID().uuidString
    let created = Date()
    let screen: String
    let game: GameLog
    let shown: String
    let rulesVersion: String?
    let ui: [String: String]
    let log: String
    let screenshot: Data?
    /// "TP 2 · Firefight · 37 events", for the sheet.
    let summary: String

    var fileName: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return "kt-feedback-\(f.string(from: created))-\(game.team)-\(id.prefix(4).lowercased()).json"
    }
}

/// A saved report, as listed in Setup.
struct FeedbackItem: Identifiable, Equatable {
    let url: URL
    let note: String
    let screen: String
    let created: Date
    let sent: Bool
    var id: URL { url }
}

/// Documents/feedback/ holds reports not sent yet; feedback/sent/ the sent
/// ones. Both show in the Files app (On My iPhone → Kill Team → feedback) and
/// are part of the phone's backups.
enum FeedbackFiles {
    static let dir: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("feedback")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let sentDir: URL = {
        let dir = FeedbackFiles.dir.appendingPathComponent("sent")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private struct Header: Decodable {
        let note: String
        let screen: String
        let created: String
    }

    /// Newest first. A file that can't be read is still listed, so it's never hidden.
    static func list() -> [FeedbackItem] {
        let iso = ISO8601DateFormatter()
        func items(in folder: URL, sent: Bool) -> [FeedbackItem] {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            return files.filter { $0.pathExtension == "json" }.map { url in
                let h = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Header.self, from: $0) }
                return FeedbackItem(url: url, note: h?.note ?? "(unreadable report)", screen: h?.screen ?? url.lastPathComponent,
                                    created: h.flatMap { iso.date(from: $0.created) } ?? .distantPast, sent: sent)
            }
        }
        return (items(in: dir, sent: false) + items(in: sentDir, sent: true)).sorted { $0.created > $1.created }
    }

    /// Fold states and other per-screen choices kept in UserDefaults.
    static func viewState() -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where key.hasPrefix("fold.") {
            if let open = value as? Bool { out[key] = open ? "open" : "folded" }
        }
        return out
    }

    static func appInfo() -> FeedbackReport.AppInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        var u = utsname()
        uname(&u)
        let machine = withUnsafeBytes(of: &u.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        let commit = (info["KTCommit"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "dev"
        return .init(version: info["CFBundleShortVersionString"] as? String ?? "?",
                     build: info["CFBundleVersion"] as? String ?? "?",
                     commit: commit, device: "\(machine) · iOS \(UIDevice.current.systemVersion)")
    }
}

enum Screenshot {
    /// The key window as it is now, sheets included, as a JPEG.
    @MainActor static func take() -> Data? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2
        let img = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        return img.jpegData(compressionQuality: 0.6)
    }
}

extension GameStore {
    func captureFeedback(screen: String) -> FeedbackCapture {
        FeedbackCapture(screen: screen, game: game, shown: engine.describe(snapshot),
                        rulesVersion: rules.meta.rulesVersion, ui: FeedbackFiles.viewState(),
                        log: String(Log.read().suffix(12_000)), screenshot: Screenshot.take(),
                        summary: "TP \(snapshot.tp) · \(snapshot.phase == .strategy ? "Strategy" : "Firefight") · \(game.events.count) events")
    }

    /// Writes the report at once. Saving the same capture again (an autosave,
    /// then Save) overwrites its file. Returns an error message on failure.
    @discardableResult
    func saveFeedback(_ c: FeedbackCapture, note: String, screenshot: Bool) -> String? {
        let report = FeedbackReport(id: c.id, created: c.created, note: note, screen: c.screen,
                                    app: FeedbackFiles.appInfo(), rulesVersion: c.rulesVersion, game: c.game,
                                    shown: c.shown, ui: c.ui, log: c.log, screenshot: screenshot ? c.screenshot : nil)
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try enc.encode(report).write(to: FeedbackFiles.dir.appendingPathComponent(c.fileName), options: .atomic)
            Log.write("saved \(c.fileName)", "feedback")
            reloadFeedback()
            return nil
        } catch {
            Log.write("saving \(c.fileName) failed: \(error)", "feedback")
            return error.localizedDescription
        }
    }

    /// Drops a report the player chose to discard (it may have been autosaved).
    func discardFeedback(_ c: FeedbackCapture) {
        try? FileManager.default.removeItem(at: FeedbackFiles.dir.appendingPathComponent(c.fileName))
        reloadFeedback()
    }

    /// Sent reports move to feedback/sent/; they stay on the phone.
    func markFeedbackSent(_ items: [FeedbackItem]) {
        for item in items where !item.sent {
            do {
                try FileManager.default.moveItem(at: item.url, to: FeedbackFiles.sentDir.appendingPathComponent(item.url.lastPathComponent))
            } catch {
                Log.write("marking \(item.url.lastPathComponent) sent failed: \(error)", "feedback")
            }
        }
        reloadFeedback()
    }

    /// Only ever on the player's explicit, confirmed request.
    func deleteFeedback(_ items: [FeedbackItem]) {
        for item in items { try? FileManager.default.removeItem(at: item.url) }
        Log.write("deleted \(items.count) feedback reports", "feedback")
        reloadFeedback()
    }
}

// MARK: - the button, on any screen

private struct ReportProblemKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// Captures the app's state and opens the feedback sheet (set by `.feedback { … }`).
    var reportProblem: () -> Void {
        get { self[ReportProblemKey.self] }
        set { self[ReportProblemKey.self] = newValue }
    }
}

/// Presents the feedback sheet for buttons inside it. `screen` names where the
/// player is ("Operative sheet: Plague Champion").
struct FeedbackSheets: ViewModifier {
    @EnvironmentObject private var store: GameStore
    let screen: () -> String
    @State private var capture: FeedbackCapture?

    func body(content: Content) -> some View {
        content
            .environment(\.reportProblem, { capture = store.captureFeedback(screen: screen()) })
            .sheet(item: $capture) { c in FeedbackSheet(capture: c).environmentObject(store) }
    }
}

extension View {
    func feedback(_ screen: @escaping () -> String) -> some View { modifier(FeedbackSheets(screen: screen)) }
}

/// The toolbar button, with how many reports are waiting to be sent.
struct FeedbackButton: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.reportProblem) private var reportProblem
    /// A text row instead of an icon (rule sheets have no toolbar).
    var title: String?

    var body: some View {
        Button { reportProblem() } label: {
            if let title {
                Label(title, systemImage: "exclamationmark.bubble").font(.footnote.weight(.semibold))
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.bubble")
                    let unsent = store.feedback.filter { !$0.sent }.count
                    if unsent > 0 { Text("\(unsent)").font(.footnote.weight(.semibold).monospacedDigit()) }
                }
            }
        }
        .foregroundStyle(Theme.link)
        .accessibilityLabel("Report a problem")
    }
}

/// Write what's wrong; the state is already captured.
struct FeedbackSheet: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let capture: FeedbackCapture
    @AppStorage("feedback.includeScreenshot") private var includeScreenshot = true
    @State private var note = ""
    @State private var confirmDiscard = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var hasText: Bool { !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What's wrong or misleading?", text: $note, axis: .vertical)
                        .lineLimit(4...12)
                        .focused($focused)
                } footer: {
                    if let error {
                        Text("Couldn't save: \(error)").foregroundStyle(Theme.hot)
                    } else {
                        Text("Saved on this phone with the whole game state, so it can be replayed exactly. Send saved reports from Setup → Feedback.")
                    }
                }

                Section("Attached") {
                    LabeledContent("Where", value: capture.screen)
                    LabeledContent("Game state", value: capture.summary)
                    if capture.screenshot != nil {
                        Toggle("Screenshot", isOn: $includeScreenshot)
                        if includeScreenshot, let data = capture.screenshot, let img = UIImage(data: data) {
                            Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Report a problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasText { confirmDiscard = true } else { discard() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(thenClose: true) }.fontWeight(.semibold)
                }
            }
            .confirmationDialog("Discard this report?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { discard() }
                Button("Keep writing", role: .cancel) {}
            }
        }
        // a swipe can't throw away what's been written
        .interactiveDismissDisabled(hasText)
        .onAppear { focused = true }
        // the phone locked or the app was left mid-report: keep what's written
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && hasText { save(thenClose: false) }
        }
        .preferredColorScheme(.dark)
    }

    private func save(thenClose: Bool) {
        error = store.saveFeedback(capture, note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                                   screenshot: includeScreenshot)
        guard error == nil, thenClose else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func discard() {
        store.discardFeedback(capture)
        dismiss()
    }
}

// MARK: - Setup → Feedback: send and tidy up

/// The list of saved reports. Its share sheet and delete dialog are presented
/// by `.feedbackSending` on the whole form: modifiers on a Section in a Form
/// can be copied onto each of its rows.
struct FeedbackSection: View {
    @EnvironmentObject private var store: GameStore
    @Binding var sharing: [FeedbackItem]?
    @Binding var pendingDelete: [FeedbackItem]?

    private var unsent: [FeedbackItem] { store.feedback.filter { !$0.sent } }
    private var sent: [FeedbackItem] { store.feedback.filter(\.sent) }

    var body: some View {
        Section {
            if store.feedback.isEmpty {
                Text("No reports. Tap \(Image(systemName: "exclamationmark.bubble")) on any screen to report a problem.")
                    .foregroundStyle(Theme.text2)
            }
            ForEach(store.feedback) { item in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.note.isEmpty ? "(no note)" : item.note).lineLimit(2).foregroundStyle(Theme.text)
                        Text("\(item.created.formatted(date: .abbreviated, time: .shortened)) · \(item.screen)")
                            .font(.caption).foregroundStyle(Theme.text2).lineLimit(1)
                    }
                    Spacer()
                    if item.sent {
                        Label("Sent", systemImage: "checkmark").labelStyle(.titleAndIcon)
                            .font(.caption).foregroundStyle(Theme.text2)
                    }
                }
            }
            .onDelete { offsets in pendingDelete = offsets.map { store.feedback[$0] } }

            if !unsent.isEmpty {
                Button { sharing = unsent } label: {
                    Label("Send \(unsent.count) new report\(unsent.count == 1 ? "" : "s")…", systemImage: "square.and.arrow.up")
                }
            } else if !sent.isEmpty {
                Button { sharing = sent } label: { Label("Send all again…", systemImage: "square.and.arrow.up") }
            }
            if !sent.isEmpty {
                Button("Delete sent reports", role: .destructive) { pendingDelete = sent }
            }
        } header: { Text("Feedback") } footer: {
            Text("Reports stay on this phone until you delete them; they're also in the Files app under On My iPhone → Kill Team → feedback. Send them to yourself (Mail, Drive, Files…) and put the .json files in the repo's feedback folder.")
        }
    }
}

struct FeedbackSending: ViewModifier {
    @EnvironmentObject private var store: GameStore
    @Binding var sharing: [FeedbackItem]?
    @Binding var pendingDelete: [FeedbackItem]?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
                if let items = sharing {
                    ShareSheet(items: items.map(\.url)) { completed in
                        // sent ones are only marked, never deleted
                        if completed { store.markFeedbackSent(items) }
                        sharing = nil
                    }
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
                }
            }
            .confirmationDialog(deleteTitle, isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let items = pendingDelete { store.deleteFeedback(items) }
                    pendingDelete = nil
                }
            } message: {
                if pendingDelete?.contains(where: { !$0.sent }) == true { Text("It hasn't been sent yet.") }
            }
    }

    private var deleteTitle: String {
        let n = pendingDelete?.count ?? 0
        return n == 1 ? "Delete this report?" : "Delete \(n) reports?"
    }
}

extension View {
    func feedbackSending(sharing: Binding<[FeedbackItem]?>, pendingDelete: Binding<[FeedbackItem]?>) -> some View {
        modifier(FeedbackSending(sharing: sharing, pendingDelete: pendingDelete))
    }
}

/// The system share sheet, telling us whether the reports went anywhere.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]
    let done: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in done(completed) }
        return vc
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
