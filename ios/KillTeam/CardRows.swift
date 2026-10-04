import SwiftUI
import KTEngine

// MARK: - rule info: tap a term or a rule name to read it

/// What an info sheet shows: a glossary term, or a rule's full text by id.
enum InfoRef: Identifiable, Equatable {
    case term(String)
    case rule(String)

    var id: String {
        switch self {
        case .term(let t): return "term:\(t)"
        case .rule(let r): return "rule:\(r)"
        }
    }
}

private struct ShowInfoKey: EnvironmentKey {
    static let defaultValue: (InfoRef) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Opens a term's definition or a rule's full text (set by `.ruleInfo(engine)`).
    var showInfo: (InfoRef) -> Void {
        get { self[ShowInfoKey.self] }
        set { self[ShowInfoKey.self] = newValue }
    }
}

/// Rule text whose terms (Ceaseless, Severe, Poison…) are tappable links.
struct RuleText: View {
    let segments: [Segment]
    var font: Font = .subheadline
    var color: Color = Theme.text2
    @Environment(\.showInfo) private var showInfo

    var body: some View {
        Text(attributed)
            .font(font)
            .foregroundStyle(color)
            .tint(Theme.link)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "ktterm",
                      let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "name" })?.value else { return .systemAction }
                showInfo(.term(name))
                return .handled
            })
    }

    private var attributed: AttributedString {
        var out = AttributedString()
        for seg in segments {
            var part = AttributedString(seg.t)
            if let term = seg.term {
                var c = URLComponents()
                c.scheme = "ktterm"
                c.host = "term"
                c.queryItems = [URLQueryItem(name: "name", value: term)]
                part.link = c.url
                part.underlineStyle = Text.LineStyle(pattern: .dot, color: Theme.link)
            }
            out += part
        }
        return out
    }
}

/// A rule's name that opens its full text when tapped.
struct RuleName: View {
    let id: String
    let name: String
    var font: Font = .headline
    @Environment(\.showInfo) private var showInfo

    var body: some View {
        Button { showInfo(.rule(id)) } label: {
            Text(name).font(font).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the full rule")
    }
}

/// Presents term and rule sheets for everything inside it.
struct RuleInfoSheets: ViewModifier {
    @EnvironmentObject private var store: GameStore
    let engine: Engine
    @State private var ref: InfoRef?

    func body(content: Content) -> some View {
        content
            .environment(\.showInfo, { ref = $0 })
            .sheet(item: $ref) { r in
                InfoSheet(engine: engine, start: r)
                    .environmentObject(store)
                    .presentationDetents([.medium, .large])
            }
    }
}

extension View {
    func ruleInfo(_ engine: Engine) -> some View { modifier(RuleInfoSheets(engine: engine)) }
}

/// The definition or full rule text. Terms inside it are tappable too; they
/// open in the same sheet, with Back to return.
struct InfoSheet: View {
    let engine: Engine
    let start: InfoRef
    @State private var stack: [InfoRef] = []

    private var current: InfoRef { stack.last ?? start }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !stack.isEmpty {
                    Button { stack.removeLast() } label: { Label("Back", systemImage: "chevron.left") }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.link)
                }
                content
                FeedbackButton(title: "Report a problem with this rule").padding(.top, 14)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.raised)
        .environment(\.showInfo, { stack.append($0) })
        .feedback { screenName }
        .preferredColorScheme(.dark)
    }

    /// For a report: which rule or term this sheet is showing.
    private var screenName: String {
        switch current {
        case .term(let name): return "Term: \(name)"
        case .rule(let id): return "Rule: \(engine.ruleInfo(id)?.title ?? id) (\(id))"
        }
    }

    @ViewBuilder private var content: some View {
        switch current {
        case .term(let name):
            let entry = engine.definition(name)
            Text((entry?.kind ?? "rule").uppercased())
                .font(.caption.weight(.semibold)).tracking(0.5).foregroundStyle(Theme.text2)
            Text(name).font(.title2.bold())
            RuleText(segments: engine.segments(entry?.def ?? "No definition recorded for this term.", excluding: name),
                     font: .body, color: Theme.text)
        case .rule(let id):
            if let info = engine.ruleInfo(id) {
                Text(info.kind.uppercased()).font(.caption.weight(.semibold)).tracking(0.5).foregroundStyle(Theme.text2)
                Text(info.title).font(.title2.bold())
                RuleText(segments: info.body, font: .body, color: Theme.text)
                ForEach(Array(info.options.enumerated()), id: \.offset) { _, o in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(o.name).font(.headline)
                        RuleText(segments: o.text)
                    }
                    .padding(.top, 4)
                }
                if let v = info.version {
                    Text("Official rules, \(v)").font(.footnote).foregroundStyle(Theme.muted).padding(.top, 6)
                }
            } else {
                Text("No rule text recorded.").foregroundStyle(Theme.text2)
            }
        }
    }
}

// MARK: - foldable blocks

/// A block with a header that folds it away. Remembered per block.
struct Fold<Content: View>: View {
    let title: String
    var trailing: String?
    var small = false
    var titleColor: Color = Theme.text
    @AppStorage private var open: Bool
    @ViewBuilder var content: Content

    init(_ title: String, key: String, trailing: String? = nil, small: Bool = false, titleColor: Color = Theme.text,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.small = small
        self.titleColor = titleColor
        _open = AppStorage(wrappedValue: true, "fold.\(key)")
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title).font(small ? .footnote.weight(.semibold) : .title3.bold()).foregroundStyle(titleColor)
                    Image(systemName: "chevron.down")
                        .font(.system(size: small ? 10 : 13, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(open ? 0 : -90))
                    Spacer()
                    if let trailing { Text(trailing).font(.subheadline).foregroundStyle(Theme.text2) }
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(open ? "expanded" : "collapsed")")
            if open { content }
        }
    }
}

// MARK: - rows

/// A ploy or piece of equipment you can use now. Tap the price to pay for it;
/// ones with options (Combat Doctrine) open their choices first.
struct UsableRow: View {
    let card: UsableCard
    let onUse: (String?) -> Void
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The price is the button: name and rule text stay outside it so
            // they stay tappable for the full rule and term definitions.
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        RuleName(id: card.id, name: card.name)
                        if card.disputed { Tag(text: "UNVERIFIED", color: Theme.hot) }
                    }
                    RuleText(segments: card.hint)
                }
                Spacer(minLength: 8)
                Button {
                    if !card.options.isEmpty { open.toggle() } else { onUse(nil) }
                } label: {
                    CostPill(text: priceText, locked: !card.afford)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!card.afford && card.options.isEmpty)
                .accessibilityLabel("Use \(card.name), \(priceText)")
                .accessibilityHint(card.options.isEmpty ? "Pays for it" : "Shows its options")
            }

            if let discount = card.discount {
                RuleText(segments: discount, color: Theme.link)
            }
            if !card.cheaperOptions.isEmpty {
                Text("Free: " + card.cheaperOptions.map(\.name).joined(separator: ", "))
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.go)
            }
            ForEach(Array(card.maybe.enumerated()), id: \.offset) { _, m in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Tag(text: "CAN BE FREE", color: Theme.link)
                    Text(maybeText(m)).font(.footnote).foregroundStyle(Theme.text2)
                }
            }
            if open {
                VStack(spacing: 0) {
                    ForEach(Array(card.options.enumerated()), id: \.element.id) { i, o in
                        if i > 0 { Hairline() }
                        Button {
                            open = false
                            onUse(o.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(o.name).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                                    Text(o.condition).font(.footnote).foregroundStyle(Theme.text2)
                                }
                                Spacer()
                                Text(o.cp == 0 ? "Free" : "\(o.cp) \(card.unit)")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.go)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .opacity(card.afford ? 1 : 0.7)
    }

    private var priceText: String {
        let price = card.free ? "Free" : "\(card.cp) \(card.unit)"
        if !card.afford { return "\(price) · short" }
        return card.reduced ? "\(card.costBase) \(card.unit) → \(price)" : price
    }

    private func maybeText(_ m: MaybeRoute) -> String {
        var s = m.from
        if let o = m.options { s += " · " + o.joined(separator: " / ") }
        if let who = m.needsOperative { s += " — select the \(who)" } else if !m.condition.isEmpty { s += " — \(m.condition)" }
        return s
    }
}

/// Something in play for the acting operative.
struct ActiveRow: View {
    let card: ActiveCard
    let onEnd: () -> Void
    let onMarkUsed: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    RuleName(id: card.id, name: card.name, font: .body.weight(.semibold))
                    Text(card.life).font(.caption).foregroundStyle(Theme.muted)
                    if card.disputed { Tag(text: "UNVERIFIED", color: Theme.hot) }
                }
                RuleText(segments: card.hint, color: Color(hex: 0xD1D1D6))
            }
            Spacer(minLength: 4)
            if card.canEnd {
                Button("End", action: onEnd).font(.subheadline).foregroundStyle(Theme.link)
                    .frame(minWidth: 44, minHeight: 44)
            } else if card.canMarkUsed {
                Button("Used", action: onMarkUsed).font(.subheadline).foregroundStyle(Theme.link)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Mark \(card.name) used")
            }
        }
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 11)
    }
}
