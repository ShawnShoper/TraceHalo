import AppKit
import SwiftUI

enum CalmTheme {
    // MARK: - Semantic palette

    /// The graphite palette is intentionally quieter than the system's default
    /// material stack. Thin borders provide the hierarchy, not card shadows.
    static let canvas = Color(lightHex: "F3F5F7", darkHex: "0E1419")
    static let canvasElevated = Color(lightHex: "F7F8FA", darkHex: "11191F")
    static let sidebar = Color(lightHex: "E9EDF1", darkHex: "1C2429")
    static let surface = Color(lightHex: "FFFFFF", darkHex: "171F25")
    static let surfaceRaised = Color(lightHex: "F3F6F8", darkHex: "1B252C")
    static let controlBackground = Color(lightHex: "E8EDF2", darkHex: "202A31")
    static let sidebarHover = Color(lightHex: "DDE3E8", darkHex: "202830")
    static let selectionBackground = Color(lightHex: "D9E6FB", darkHex: "244C8F")
    static let selectionText = Color(lightHex: "174786", darkHex: "FFFFFF")

    static let primaryText = Color(lightHex: "172028", darkHex: "F1F5F7")
    static let secondaryText = Color(lightHex: "4C5A64", darkHex: "B9C5CD")
    static let tertiaryText = Color(lightHex: "687681", darkHex: "93A1AA")
    static let hairline = Color(nsColor: .separatorColor).opacity(0.72)
    static let strongHairline = Color(nsColor: .separatorColor)

    static let accent = Color(lightHex: "3D72D8", darkHex: "6598F5")
    /// Kept darker than `accent` so white action labels remain above 5:1
    /// contrast in both appearances. Charts can still use the brighter accent.
    static let primaryAction = Color(lightHex: "2F63C0", darkHex: "326AC7")
    static let mint = Color(lightHex: "3B9855", darkHex: "74C98B")
    static let amber = Color(lightHex: "BC7417", darkHex: "E9A94B")
    static let rose = Color(lightHex: "C64F60", darkHex: "E27682")
    static let violet = Color(lightHex: "7954BE", darkHex: "A77BE5")
    static let cyan = Color(lightHex: "248FA6", darkHex: "55C3D5")

    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 9
    static let sidebarRowRadius: CGFloat = 10

    static let pageGradient = LinearGradient(
        colors: [
            canvasElevated,
            Color(lightHex: "F4F7F9", darkHex: "111A20"),
            canvas
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct TraceHaloSystemFocusEffectHiddenKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Testable marker for interface roots that suppress AppKit's default blue
    /// focus effect without removing the underlying keyboard focus semantics.
    var traceHaloSystemFocusEffectIsHidden: Bool {
        get { self[TraceHaloSystemFocusEffectHiddenKey.self] }
        set { self[TraceHaloSystemFocusEffectHiddenKey.self] = newValue }
    }
}

/// A common boundary for every TraceHalo-owned SwiftUI surface.
///
/// `focusEffectDisabled` only changes the system-drawn focus appearance. It
/// intentionally leaves controls focusable so Tab, Return, Space and VoiceOver
/// continue to work. Product selection, toggle and disclosure styling is also
/// unaffected because those states are drawn by their owning controls.
struct TraceHaloFocusAppearanceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .focusEffectDisabled()
            .environment(\.traceHaloSystemFocusEffectIsHidden, true)
    }
}

enum TraceHaloFocusAppearance {
    /// The menu-bar status item is an AppKit button and therefore sits outside
    /// the SwiftUI root hierarchy. Hiding its focus ring must not change its
    /// first-responder eligibility or accessibility behavior.
    @MainActor
    static func configureStatusButton(_ button: NSButton) {
        button.focusRingType = .none
    }
}

extension Color {
    init(hex: String) {
        let normalized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: normalized).scanHexInt64(&value)

        let red: UInt64
        let green: UInt64
        let blue: UInt64
        let alpha: UInt64
        switch normalized.count {
        case 8:
            red = value >> 24
            green = (value >> 16) & 0xff
            blue = (value >> 8) & 0xff
            alpha = value & 0xff
        default:
            red = value >> 16
            green = (value >> 8) & 0xff
            blue = value & 0xff
            alpha = 0xff
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }

    init(lightHex: String, darkHex: String) {
        let lightColor = NSColor(cssHex: lightHex)
        let darkColor = NSColor(cssHex: darkHex)
        let adaptiveColor = NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? darkColor : lightColor
        }
        self.init(nsColor: adaptiveColor)
    }
}

private extension NSColor {
    convenience init(cssHex: String) {
        let normalized = cssHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: normalized).scanHexInt64(&value)
        let red = CGFloat((value >> 16) & 0xff) / 255
        let green = CGFloat((value >> 8) & 0xff) / 255
        let blue = CGFloat(value & 0xff) / 255
        self.init(
            srgbRed: red,
            green: green,
            blue: blue,
            alpha: 1
        )
    }
}

struct CalmCardModifier: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: CalmTheme.cardRadius, style: .continuous)
                    .fill(CalmTheme.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: CalmTheme.cardRadius, style: .continuous)
                    .strokeBorder(CalmTheme.hairline)
            }
    }
}

extension View {
    func traceHaloFocusAppearance() -> some View {
        modifier(TraceHaloFocusAppearanceModifier())
    }

    func calmCard(padding: CGFloat = 18) -> some View {
        modifier(CalmCardModifier(padding: padding))
    }

    func calmPage() -> some View {
        foregroundStyle(CalmTheme.primaryText)
            .background(CalmTheme.pageGradient.ignoresSafeArea())
    }
}

struct CalmButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(prominent ? Color.white : CalmTheme.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: CalmTheme.controlRadius, style: .continuous)
                    .fill(prominent ? CalmTheme.primaryAction : CalmTheme.controlBackground)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CalmTheme.controlRadius, style: .continuous)
                    .strokeBorder(prominent ? CalmTheme.primaryAction : CalmTheme.strongHairline)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
