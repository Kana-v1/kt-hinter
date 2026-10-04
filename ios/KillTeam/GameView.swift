import SwiftUI
import KTEngine

/// The one in-game screen (canvas boards "Firefight" and "Strategy phase"):
/// turning point and CP, the phase switch, who's acting, what you can use now,
/// and what's in play for the acting operative.
struct GameView: View {
    @EnvironmentObject private var store: GameStore
    @State private var showOperative = false
    @State private var showSetup = false
    @State private var askInitiative = false

    private var snap: Snapshot { store.snapshot }
    private var accent: Color { Theme.accent(store.game.team) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    turnStrip
                    phasePicker
                    actingRow
                    useSection
                    activeSection
                    spentSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.bg)
            .safeAreaInset(edge: .bottom) { toolbar }
            .overlay(alignment: .top) { toastView }
            .navigationTitle(snap.phase == .strategy ? "Strategy" : "Firefight")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 6) {
                        if let symbol = store.teamSymbol(for: store.game.team) {
                            Image(uiImage: symbol).resizable().scaledToFit().frame(width: 22, height: 22)
                        }
                        Text(store.rules.meta.team.uppercased())
                            .font(.footnote.weight(.semibold)).foregroundStyle(accent)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    FeedbackButton()
                    Button { showSetup = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Setup")
                }
            }
            .sheet(isPresented: $showOperative) { OperativeSheet().environmentObject(store) }
            .sheet(isPresented: $showSetup) { SetupView().environmentObject(store) }
            .sheet(isPresented: $askInitiative) {
                InitiativeSheet(nextTP: snap.tp + 1) { ini in
                    askInitiative = false
                    store.send(Event(.tpNext, Params(ini: ini)))
                }
                .presentationDetents([.height(300)])
            }
            .sheet(isPresented: Binding(get: { snap.summary != nil }, set: { if !$0 { store.send(Event(.clearSummary)) } })) {
                if let s = snap.summary {
                    RecapSheet(summary: s, cp: snap.cp) { store.send(Event(.clearSummary)) }
                        .presentationDetents([.medium])
                }
            }
            .ruleInfo(store.engine)
            .feedback { "Game screen" }
        }
    }

    // MARK: sections

    private var turnStrip: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Turning Point").font(.footnote.weight(.semibold)).foregroundStyle(Theme.text2)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(snap.tp)").font(Theme.number(44))
                    Text("of 4").font(.subheadline).foregroundStyle(Theme.text2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Command").font(.footnote.weight(.semibold)).foregroundStyle(Theme.text2)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(snap.cp)").font(Theme.number(44)).foregroundStyle(Theme.link)
                        Text("CP").font(.subheadline).foregroundStyle(Theme.text2)
                    }
                }
                Spacer(minLength: 4)
                VStack(spacing: 6) {
                    stepButton("plus", "Gain a command point") { store.send(Event(.cp, Params(d: 1))) }
                    stepButton("minus", "Spend a command point") { store.send(Event(.cp, Params(d: -1))) }
                }
            }
            .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.top, 4)
    }

    private func stepButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .bold))
                .frame(width: 44, height: 30)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .foregroundStyle(Theme.text)
        .accessibilityLabel(label)
    }

    private var phasePicker: some View {
        Picker("Phase", selection: Binding(get: { snap.phase }, set: { store.send(Event(.phase, Params(phase: $0))) })) {
            Text("Strategy").tag(Phase.strategy)
            Text("Firefight").tag(Phase.firefight)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder private var actingRow: some View {
        if let op = store.engine.operative(snap.op) {
            VStack(alignment: .leading, spacing: 6) {
                Button { showOperative = true } label: {
                    HStack(spacing: 12) {
                        Glyph(operative: op, photo: store.photo(for: op.id), size: 24)
                            .frame(width: 44, height: 44)
                            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Acting").font(.footnote.weight(.semibold)).foregroundStyle(Theme.text2)
                            Text(op.name + (snap.dead.contains(snap.op) ? " · down" : ""))
                                .font(.headline).foregroundStyle(Theme.text)
                            if let names = snap.statusNames[snap.op], !names.isEmpty {
                                Label(names.joined(separator: " · "), systemImage: "sparkles")
                                    .font(.footnote.weight(.semibold)).foregroundStyle(accent)
                            }
                            Text("APL \(op.stats.apl) · Move \(op.stats.move) · Save \(op.stats.save) · \(op.stats.wounds) W")
                                .font(.footnote.monospacedDigit()).foregroundStyle(Theme.text2)
                        }
                        Spacer(minLength: 4)
                        if buffCount > 0 {
                            Text("+\(buffCount) buffs").font(.footnote.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .foregroundStyle(accent)
                                .background(accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                        }
                        Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows this operative's datacard and picks who's acting")
                if snap.phase == .firefight {
                    Text("Pick another operative when its activation starts.")
                        .font(.footnote).foregroundStyle(Theme.text2).padding(.horizontal, 4)
                }
            }
        }
    }

    /// Effects currently adding weapon rules to the acting operative.
    private var buffCount: Int {
        Set(snap.weaponNotes.values.flatMap { $0.map(\.from) }).count
    }

    @ViewBuilder private var useSection: some View {
        Fold("Use now", key: "use", trailing: snap.use.isEmpty ? nil : "\(snap.use.reduce(0) { $0 + $1.cards.count })") {
            if snap.use.isEmpty {
                Text(snap.phase == .strategy ? "No strategy ploys left this turning point." : "Nothing left to use this turning point.")
                    .font(.subheadline).foregroundStyle(Theme.text2).padding(.horizontal, 4)
            }
            ForEach(snap.use, id: \.when) { group in
                Fold(group.when.useTitle, key: "use.\(group.when.rawValue)", small: true, titleColor: Theme.text2) {
                    ListBlock {
                        ForEach(Array(group.cards.enumerated()), id: \.element.id) { i, card in
                            if i > 0 { Hairline() }
                            UsableRow(card: card) { opt in
                                store.send(Event(.activate, Params(id: card.id, opt: opt)))
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder private var activeSection: some View {
        Fold("Active on \(store.engine.operative(snap.op)?.name ?? "operative")", key: "active") {
            if snap.active.isEmpty {
                Text("Nothing in play.").font(.subheadline).foregroundStyle(Theme.text2).padding(.horizontal, 4)
            }
            ForEach(snap.active, id: \.when) { group in
                Fold(group.when.title.uppercased(), key: "active.\(group.when.rawValue)", small: true, titleColor: Theme.live) {
                    ListBlock {
                        ForEach(Array(group.cards.enumerated()), id: \.element.id) { i, card in
                            if i > 0 { Hairline() }
                            ActiveRow(card: card,
                                      onEnd: { store.send(Event(.end, Params(id: card.id))) },
                                      onMarkUsed: { store.send(Event(.useBattle, Params(id: card.id))) })
                        }
                    }
                }
                .padding(.top, 4)
            }
            if !snap.elsewhere.isEmpty {
                Text("On other operatives: " + snap.elsewhere.map(\.name).joined(separator: ", ") + ".")
                    .font(.footnote).foregroundStyle(Theme.text2).padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder private var spentSection: some View {
        if !snap.spent.isEmpty {
            Text("Used this turning point: " + snap.spent.map(\.name).joined(separator: ", ") + ".")
                .font(.footnote).foregroundStyle(Theme.muted).padding(.horizontal, 4)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { store.undo() } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .font(.headline).padding(.horizontal, 16).frame(height: 50)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .foregroundStyle(Theme.text)
            .disabled(!store.game.canUndo)

            Button {
                if snap.phase == .strategy {
                    store.send(Event(.phase, Params(phase: .firefight)))
                } else {
                    askInitiative = true
                }
            } label: {
                Text(snap.phase == .strategy ? "Start firefight" : "Next turning point")
                    .font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                    .background(Theme.text, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(Color.black)
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder private var toastView: some View {
        if let toast = store.toast {
            HStack(spacing: 12) {
                Image(systemName: "clock").foregroundStyle(Theme.live)
                Text(toast).font(.subheadline).foregroundStyle(Theme.text)
                Spacer(minLength: 4)
                Button("Undo") { store.undo() }.font(.subheadline.weight(.semibold)).foregroundStyle(Theme.link)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
            .padding(.horizontal, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                store.toast = nil
            }
        }
    }
}

/// Asked when the turning point ends: initiative decides the CP gain
/// (core rules: +1 with initiative, +2 without).
struct InitiativeSheet: View {
    let nextTP: Int
    let choose: (Initiative) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Turning Point \(nextTP)").font(.title2.bold())
            Text("Who has initiative?").font(.body).foregroundStyle(Theme.text2)
            HStack(spacing: 10) {
                choice("We do", "+1 CP") { choose(.us) }
                choice("They do", "+2 CP") { choose(.them) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        .preferredColorScheme(.dark)
    }

    private func choice(_ title: String, _ gain: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title).font(.headline)
                Text(gain).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.link)
            }
            .frame(maxWidth: .infinity).frame(height: 76)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .foregroundStyle(Theme.text)
    }
}

/// What you paid for in the turning point that just ended (canvas "Turning point recap").
struct RecapSheet: View {
    let summary: Summary
    let cp: Int
    let done: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock").font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.link)
                .frame(width: 56, height: 56).background(Theme.link.opacity(0.15), in: Circle())
            Text("Turning Point \(summary.tp) is over").font(.title3.bold())
            Text("These end now. Did each one get used?").font(.subheadline).foregroundStyle(Theme.text2)
            ListBlock {
                ForEach(Array(summary.paid.enumerated()), id: \.offset) { i, p in
                    if i > 0 { Hairline() }
                    HStack {
                        Text(p.name).font(.body.weight(.semibold))
                        Spacer()
                        Text(p.cp == 0 ? "Free" : "\(p.cp) CP")
                            .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.text2)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                }
            }
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16))
            Text("Now \(cp) CP").font(.subheadline).foregroundStyle(Theme.link)
            Button(action: done) {
                Text("Got it").font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                    .background(Theme.text, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(Color.black)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.surface)
        .preferredColorScheme(.dark)
    }
}
