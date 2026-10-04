import SwiftUI
import UIKit

// Tokens de la dirección de arte. Ver docs/DISENO.md.

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// Color que se invierte en modo claro (tinta ↔ papel).
    static func dynamic(dark: UIColor, light: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .light ? light : dark }
    }
}

enum Palette {
    static let inkHex: UInt32 = 0x0B0D10
    static let paperHex: UInt32 = 0xF2F0EA
    static let signalHex: UInt32 = 0xFF5A1F

    static let ink = UIColor(hex: inkHex)
    static let paper = UIColor(hex: paperHex)
    static let signal = UIColor(hex: signalHex)
}

extension Color {
    /// Fondo: tinta en oscuro, papel en claro.
    static let planoBackground = Color(UIColor.dynamic(dark: Palette.ink, light: Palette.paper))
    /// Texto y líneas principales.
    static let planoForeground = Color(UIColor.dynamic(dark: Palette.paper, light: Palette.ink))
    /// Línea de plano al 90 %.
    static let planoLine = Color(UIColor.dynamic(dark: Palette.paper.withAlphaComponent(0.9),
                                                 light: Palette.ink.withAlphaComponent(0.9)))
    static let planoSecondary = Color(UIColor.dynamic(dark: Palette.paper.withAlphaComponent(0.55),
                                                      light: Palette.ink.withAlphaComponent(0.55)))
    static let planoHairline = Color(UIColor.dynamic(dark: Palette.paper.withAlphaComponent(0.14),
                                                     light: Palette.ink.withAlphaComponent(0.14)))
    static let signal = Color(Palette.signal)
    /// Malla de escaneo: acento al 40 %.
    static let scanMesh = Color(Palette.signal.withAlphaComponent(0.4))
}

// MARK: - Tipografía

enum TypeScale {
    static let display: CGFloat = 64
    static let title: CGFloat = 32
    static let body: CGFloat = 17
    static let caption: CGFloat = 13
}

enum PlanoFont {
    private static let groteskName = "SpaceGrotesk-Light" // instancia por defecto de la fuente variable
    private static let monoName = "JetBrainsMono-Regular"
    private static let wghtAxis = 0x77676874 // 'wght'

    private static func variable(_ name: String, size: CGFloat, weight: CGFloat) -> UIFont? {
        guard let base = UIFont(name: name, size: size) else { return nil }
        let key = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let descriptor = base.fontDescriptor.addingAttributes([key: [wghtAxis: weight]])
        return UIFont(descriptor: descriptor, size: size)
    }

    /// Space Grotesk. Usar con `.tracking(TypeScale.tracking(size))` y texto en mayúsculas.
    static func grotesk(_ size: CGFloat, weight: CGFloat = 600) -> Font {
        if let font = variable(groteskName, size: size, weight: weight) { return Font(font as CTFont) }
        return .system(size: size, weight: weight >= 600 ? .bold : .regular)
    }

    /// JetBrains Mono para cotas y datos.
    static func mono(_ size: CGFloat, weight: CGFloat = 400) -> Font {
        if let font = variable(monoName, size: size, weight: weight) { return Font(font as CTFont) }
        return .system(size: size, weight: weight >= 600 ? .semibold : .regular, design: .monospaced)
    }
}

extension TypeScale {
    /// Tracking −2 %.
    static func tracking(_ size: CGFloat) -> CGFloat { -0.02 * size }
}

extension View {
    func planoTitle(_ size: CGFloat = TypeScale.title) -> some View {
        font(PlanoFont.grotesk(size)).tracking(TypeScale.tracking(size)).textCase(.uppercase)
    }

    func planoMono(_ size: CGFloat = TypeScale.caption) -> some View {
        font(PlanoFont.mono(size)).monospacedDigit()
    }
}

// MARK: - Rejilla

enum Grid {
    static let unit: CGFloat = 8
    static let margin: CGFloat = 20
    static func u(_ n: CGFloat) -> CGFloat { n * unit }
}

// MARK: - Movimiento

enum Motion {
    static let enterDuration = 0.48
    static let exitDuration = 0.24
    static let stagger = 0.06
    static let reducedDuration = 0.15

    /// Entrada: cubic-bezier(0.22, 1, 0.36, 1), 480 ms.
    static let enter = Animation.timingCurve(0.22, 1, 0.36, 1, duration: enterDuration)
    /// Salida: cubic-bezier(0.64, 0, 0.78, 0), 240 ms.
    static let exit = Animation.timingCurve(0.64, 0, 0.78, 0, duration: exitDuration)
    /// Muelle de botones.
    static let button = Animation.spring(response: 0.45, dampingFraction: 0.82)
    /// Sustituto cuando "Reducir movimiento" está activo.
    static let reduced = Animation.easeInOut(duration: reducedDuration)

    static func staggered(_ index: Int) -> Animation { enter.delay(Double(index) * stagger) }

    /// Curva de entrada con otra duración (p. ej. 900 ms para dibujar muros).
    static func enterCurve(_ duration: Double) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: duration) }

    static func curve(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : animation
    }
}

/// Botón con muelle (respuesta 0,45, amortiguación 0,82).
struct PlanoButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PlanoFont.grotesk(TypeScale.body))
            .tracking(TypeScale.tracking(TypeScale.body))
            .textCase(.uppercase)
            .padding(.vertical, Grid.u(2))
            .padding(.horizontal, Grid.u(3))
            .frame(maxWidth: .infinity)
            .foregroundStyle(prominent ? Color(Palette.ink) : Color.planoForeground)
            .background(prominent ? Color.signal : Color.clear)
            .overlay(Rectangle().stroke(prominent ? Color.clear : Color.planoForeground, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.button, value: configuration.isPressed)
    }
}
