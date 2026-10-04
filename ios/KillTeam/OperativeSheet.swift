import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import KTEngine

/// The acting operative's datacard (canvas "Operative sheet"): switch who's
/// acting, stats, every weapon with the rules effects add to it, and which of
/// your rules apply to this operative.
struct OperativeSheet: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var pickedItem: PhotosPickerItem?
    @State private var pickingFile = false
    @State private var takingPhoto = false
    /// Ploys to offer the moment an operative is marked incapacitated (Poisonous Demise).
    @State private var deathOffer: UsableCard?

    private var snap: Snapshot { store.snapshot }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    rosterChips
                    if let op = store.engine.operative(snap.op) {
                        identity(op)
                        stats(op)
                        if !snap.statuses.isEmpty { statuses }
                        weapons(op)
                        applies
                        Button {
                            let goingDown = !snap.dead.contains(snap.op)
                            store.send(Event(.down, Params(id: snap.op)))
                            if goingDown {
                                deathOffer = store.snapshot.use.flatMap(\.cards).first { $0.trigger == "incapacitated" && $0.afford }
                            }
                        } label: {
                            Text(snap.dead.contains(snap.op) ? "Back in action" : "Mark incapacitated")
                                .font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .foregroundStyle(snap.dead.contains(snap.op) ? Theme.link : Theme.hot)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.surface)
            .navigationTitle("Operative")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { FeedbackButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .ruleInfo(store.engine)
            .feedback { "Operative sheet: \(store.engine.operative(store.snapshot.op)?.name ?? store.snapshot.op)" }
            .confirmationDialog(deathOffer.map { "Use \($0.name)?" } ?? "",
                                isPresented: Binding(get: { deathOffer != nil }, set: { if !$0 { deathOffer = nil } }),
                                titleVisibility: .visible, presenting: deathOffer) { card in
                Button("\(card.name) — \(card.free ? "free" : "\(card.cp) CP")") {
                    store.send(Event(.activate, Params(id: card.id)))
                }
                Button("Not now", role: .cancel) {}
            } message: { card in
                Text(card.hint.map(\.t).joined())
            }
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                let id = typeOf(snap.op)
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) { store.setPhoto(data, for: id) }
                    pickedItem = nil
                }
            }
            .fullScreenCover(isPresented: $takingPhoto) {
                let id = typeOf(snap.op)
                CameraPicker { img in store.setPhoto(img, for: id) }.ignoresSafeArea()
            }
            .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.image]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) { store.setPhoto(data, for: typeOf(snap.op)) }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var rosterChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(snap.roster, id: \.self) { inst in
                let selected = inst == snap.op
                let down = snap.dead.contains(inst)
                Button {
                    store.send(Event(.op, Params(id: inst)))
                } label: {
                    HStack(spacing: 6) {
                        if let op = store.engine.operative(inst), let img = store.photo(for: op.id) {
                            Image(uiImage: img).resizable().scaledToFill().frame(width: 24, height: 24).clipShape(Circle())
                        }
                        Text(shortName(inst))
                            .font(.subheadline.weight(.semibold))
                            .strikethrough(down)
                        if !(snap.statusNames[inst] ?? []).isEmpty {
                            Image(systemName: "sparkles").font(.caption.weight(.bold))
                                .accessibilityLabel((snap.statusNames[inst] ?? []).joined(separator: ", "))
                        }
                    }
                    .padding(.leading, store.engine.operative(inst).flatMap { store.photo(for: $0.id) } == nil ? 12 : 5)
                    .padding(.trailing, 12).frame(minHeight: 34)
                        .foregroundStyle(selected ? Color.black : (down ? Theme.muted : Theme.text))
                        .background(selected ? Theme.text : Theme.raised, in: Capsule())
                }
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func identity(_ op: Operative) -> some View {
        HStack(spacing: 14) {
            Menu {
                if CameraPicker.isAvailable {
                    Button { takingPhoto = true } label: { Label("Take Photo", systemImage: "camera") }
                }
                PhotosPicker(selection: $pickedItem, matching: .images) {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle")
                }
                Button { pickingFile = true } label: { Label("Choose from Files", systemImage: "folder") }
                if store.photo(for: op.id) != nil {
                    Button(role: .destructive) { store.removePhoto(for: op.id) } label: {
                        Label("Remove photo", systemImage: "trash")
                    }
                }
            } label: {
                Glyph(operative: op, photo: store.photo(for: op.id), size: 34)
                    .frame(width: 64, height: 64)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill").font(.system(size: 10, weight: .bold))
                            .padding(5).background(Theme.selected, in: Circle()).offset(x: 4, y: 4)
                    }
            }
            .accessibilityLabel("Set \(op.name)'s photo")
            VStack(alignment: .leading, spacing: 2) {
                Text(op.name).font(.title2.bold())
                Text(op.role + (snap.dead.contains(snap.op) ? " · incapacitated" : ""))
                    .font(.subheadline).foregroundStyle(Theme.text2)
            }
        }
    }

    /// Statuses the player sets (INSPIRING, Benedictions): the app can't see them happen.
    private var statuses: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Status", trailing: "tap to set or clear")
            FlowLayout(spacing: 8) {
                ForEach(snap.statuses, id: \.id) { st in
                    Button {
                        store.send(Event(.status, Params(id: snap.op, opt: st.id)))
                    } label: {
                        Label(st.name, systemImage: st.on ? "sparkles" : "circle.dashed")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).frame(minHeight: 34)
                            .foregroundStyle(st.on ? Color.black : Theme.text)
                            .background(st.on ? Theme.accent(store.game.team) : Theme.raised, in: Capsule())
                    }
                    .accessibilityAddTraits(st.on ? .isSelected : [])
                }
            }
        }
    }

    private func stats(_ op: Operative) -> some View {
        HStack(spacing: 8) {
            stat("\(op.stats.apl)", "APL")
            stat(op.stats.move, "MOVE")
            stat(op.stats.save, "SAVE")
            stat("\(op.stats.wounds)", "WOUNDS")
        }
    }

    private func stat(_ value: String, _ key: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.number(24))
            Text(key).font(.caption.weight(.semibold)).foregroundStyle(Theme.text2)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func weapons(_ op: Operative) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Weapons", trailing: "tap a rule for its meaning")
            VStack(spacing: 0) {
                ForEach(Array(op.weapons.enumerated()), id: \.offset) { i, w in
                    if i > 0 { Hairline() }
                    weaponRow(w)
                }
            }
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func weaponRow(_ w: Weapon) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: w.isMelee ? "hand.raised" : "scope").font(.footnote).foregroundStyle(Theme.muted)
                Text(w.name).font(.headline)
                Spacer(minLength: 4)
                statLabel("A", "\(w.atk)")
                statLabel(w.isMelee ? "WS" : "BS", w.hit)
                statLabel("D", w.dmg)
            }
            if !["-", "—", ""].contains(w.rules) {
                RuleText(segments: store.engine.segments(w.rules), font: .footnote)
            }
            ForEach(Array((snap.weaponNotes[w.name] ?? []).enumerated()), id: \.offset) { _, note in
                VStack(alignment: .leading, spacing: 2) {
                    RuleText(segments: store.engine.segments(note.rules.map { "+\($0)" }.joined(separator: " ")),
                             font: .subheadline.weight(.bold), color: Theme.accent(store.game.team))
                    Text(note.from + (note.condition.map { " — \($0)" } ?? ""))
                        .font(.footnote).foregroundStyle(Color(hex: 0xD6DDC8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Theme.accent(store.game.team).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private func statLabel(_ key: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(key).font(.caption).foregroundStyle(Theme.text2)
            Text(value).font(.subheadline.weight(.bold).monospacedDigit())
        }
    }

    private var applies: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Affects this operative")
            VStack(spacing: 0) {
                let cards = snap.active.flatMap(\.cards)
                ForEach(Array(cards.enumerated()), id: \.offset) { i, c in
                    if i > 0 { Hairline() }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(Theme.go)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline) {
                                RuleName(id: c.id, name: c.name, font: .body)
                                Spacer(minLength: 6)
                                Text(c.kindLabel.components(separatedBy: " · ").first ?? "")
                                    .font(.footnote).foregroundStyle(Theme.text2)
                            }
                            RuleText(segments: c.hint, font: .footnote)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                }
            }
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if !snap.elsewhere.isEmpty {
                Text("On the table, but not for this operative").font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.text2).padding(.top, 6).padding(.horizontal, 4)
                ForEach(Array(snap.elsewhere.enumerated()), id: \.offset) { _, e in
                    (Text(e.name).foregroundColor(Theme.muted) + Text(" · \(e.who)").foregroundColor(Theme.text2))
                        .font(.subheadline).padding(.horizontal, 4)
                }
            }
        }
    }

    private func shortName(_ inst: String) -> String {
        guard let op = store.engine.operative(inst) else { return inst }
        var n = op.name
        for (long, short) in [("Assault Intercessor", "Asslt Int"), ("Heavy Intercessor", "Hvy Int"),
                              ("Intercessor", "Int"), ("Eliminator", "Elim"), ("Space Marine", "SM"),
                              ("Malignant Plaguecaster", "Plaguecaster"), ("Plague Marine ", ""),
                              ("Insidiant ", "")] {
            n = n.replacingOccurrences(of: long, with: short)
        }
        let same = snap.roster.filter { typeOf($0) == typeOf(inst) }.count
        if same > 1, let num = inst.split(separator: "#").last { n += " \(num)" }
        return n
    }
}
