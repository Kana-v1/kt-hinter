import SwiftUI
import UIKit
import KTEngine

/// The look from the design canvas: true-black ground, iOS grouped surfaces,
/// system tints with fixed meanings — green = you can use it, orange = in play
/// now, red = locked or unverified, blue = interactive or a rule term. Colour is
/// never the only signal: every state also has text or an icon.
enum Theme {
    static let bg = Color(hex: 0x000000)
    static let surface = Color(hex: 0x1C1C1E)
    static let raised = Color(hex: 0x2C2C2E)
    static let separator = Color(hex: 0x38383A)
    static let text = Color(hex: 0xF5F5F7)
    static let text2 = Color(hex: 0xA1A1A6)
    static let muted = Color(hex: 0x8E8E93)
    static let go = Color(hex: 0x30D158)
    static let goBg = Color(hex: 0x0F2E17)
    static let live = Color(hex: 0xFF9F0A)
    static let liveBg = Color(hex: 0x3A2A0A)
    static let hot = Color(hex: 0xFF6961)
    static let link = Color(hex: 0x4DA3FF)
    static let selected = Color(hex: 0x636366)

    /// Per-team accent (sickly lime for Plague Marines, cobalt for Angels of Death,
    /// reliquary gold for Celestian Insidiants).
    static func accent(_ team: String) -> Color {
        switch team {
        case "plague_marines": return Color(hex: 0xB5D96B)
        case "aod": return Color(hex: 0x8CB8FF)
        case "celestian_insidiants": return Color(hex: 0xE8C27A)
        case "spectre_squad": return Color(hex: 0xBFA88A)
        default: return Color(hex: 0xE6A94A)
        }
    }

    /// Big numbers (TP, CP, stats) use the rounded face.
    static func number(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// "#RRGGBB" from the census (operative accents).
    init(hexString: String) {
        let clean = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        self.init(hex: UInt32(clean, radix: 16) ?? 0x8FA5B5)
    }
}

extension When {
    /// Heading for the "Use now" groups.
    var useTitle: String {
        switch self {
        case .activation: return "During your activation"
        case .attack: return "When you attack"
        case .defence: return "When you're attacked"
        case .any: return "Any time"
        }
    }
}

// MARK: - building blocks

/// An inset grouped list block: rows separated by hairlines.
struct ListBlock<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 14) }
}

struct SectionTitle: View {
    let text: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.title3.bold())
            Spacer()
            if let trailing { Text(trailing).font(.subheadline).foregroundStyle(Theme.text2) }
        }
        .padding(.horizontal, 4)
    }
}

struct CostPill: View {
    let text: String
    var locked = false

    var body: some View {
        HStack(spacing: 4) {
            if locked { Image(systemName: "lock.fill").font(.system(size: 11, weight: .bold)) }
            Text(text).font(.system(size: 15, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .foregroundStyle(locked ? Theme.hot : Theme.go)
        .background(locked ? Color.clear : Theme.goBg, in: Capsule())
    }
}

struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text).font(.system(size: 11, weight: .bold)).tracking(0.5)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(color)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(color))
    }
}

/// Chips that wrap onto new lines instead of scrolling sideways — a hidden
/// horizontal scroll once cost the user half the controls (CLAUDE.md).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

/// Operative mark: the player's photo when set (on the phone, never bundled),
/// else an SF Symbol chosen per icon key.
struct Glyph: View {
    let operative: Operative
    var photo: UIImage? = nil
    var size: CGFloat = 22

    var body: some View {
        if let photo {
            Image(uiImage: photo).resizable().scaledToFill()
        } else {
            Image(systemName: Glyph.symbol(operative.icon))
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(Color(hexString: operative.accent))
        }
    }

    static func symbol(_ icon: String) -> String {
        switch icon {
        case "laurel": return "crown"
        case "chevron2": return "chevron.up.2"
        case "launcher": return "circle.hexagongrid"
        case "chainsword": return "bolt"
        case "grenade": return "circle.circle"
        case "heavy": return "square.stack.3d.up"
        case "crosshair": return "scope"
        case "beacon": return "dot.radiowaves.left.and.right"
        case "vox": return "antenna.radiowaves.left.and.right"
        case "medic": return "cross.case"
        case "guide": return "binoculars"
        case "flame": return "flame"
        case "loader": return "shippingbox"
        case "stubber": return "circle.grid.3x3"
        default: return "shield"
        }
    }
}
