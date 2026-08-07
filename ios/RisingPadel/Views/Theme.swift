import PadelCore
import SwiftUI
import UIKit

/// Sistema visual de la app, portado del de Liga Pádel para que las dos parezcan un solo
/// producto: fondo crema, tinta azul muy oscura, azul de pista y lima de pelota.
///
/// Los colores se definen con un proveedor dinámico en vez de con literales para que la
/// app funcione en modo oscuro: la identidad se mantiene (mismo azul, misma lima) y solo
/// se invierten fondo y tinta.
enum T {
    // El oscuro es el navy profundo del icono; el claro, papel frío con tinta navy.
    // Así la app y su icono son la misma marca, no dos productos.
    static let fondo = dynamic(light: 0xF2F5F9, dark: 0x0A1626)
    static let superficie = dynamic(light: 0xFFFFFF, dark: 0x13233C)
    static let tinta = dynamic(light: 0x0E2038, dark: 0xEAF0F7)
    static let tintaSuave = dynamic(light: 0x0E2038, dark: 0xEAF0F7, alpha: 0.58)
    static let borde = dynamic(light: 0x0E2038, dark: 0xFFFFFF, alpha: 0.12)

    /// Azul de pista: el color de marca y el de las series principales.
    static let pista = dynamic(light: 0x1E56A8, dark: 0x5B93E8)
    static let pistaTinte = dynamic(light: 0xE4ECF8, dark: 0x1E56A8, alpha: 0.22)

    /// Lima de pelota: el acento de la marca — cifras héroe y momentos clave, nunca
    /// texto largo. En oscuro es el lima neón del icono.
    static let lima = dynamic(light: 0x8FA50F, dark: 0xCDE94F)
    static let limaTinte = dynamic(light: 0x8FA50F, dark: 0xCDE94F, alpha: 0.14)

    /// Alias histórico del lima (la bolita de saque y compañía).
    static let bola = lima

    static let rojo = dynamic(light: 0xD0455B, dark: 0xE8697D)
    static let verde = dynamic(light: 0x1F8A5B, dark: 0x3FBF87)

    private static func dynamic(light: Int, dark: Int, alpha: Double = 1) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light, alpha: alpha)
        })
    }
}

private extension UIColor {
    convenience init(hex: Int, alpha: Double) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

// MARK: Tipografía

extension Font {
    /// Cifras grandes: redondeada y con ancho fijo de dígito, para que un contador que
    /// cambia no "baile".
    static func padelDisplay(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    static func padelTitle(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}

// MARK: Componentes

/// Etiqueta de sección: mayúsculas espaciadas, como en la app de liga.
struct SectionLabel: View {
    let text: String
    var icon: String?

    init(_ text: String, icon: String? = nil) {
        self.text = text
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
            }
            Text(text.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .kerning(1.6)
        }
        .foregroundStyle(T.tintaSuave)
    }
}

/// Tarjeta blanca de radio 16 con borde fino: la unidad de composición de toda la app.
struct PadelCard<Content: View>: View {
    var title: String?
    var icon: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                SectionLabel(title, icon: icon)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(T.superficie, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(T.borde, lineWidth: 1)
        )
    }
}

/// Dato suelto con su etiqueta. El valor manda visualmente; la etiqueta acompaña.
struct StatTile: View {
    let label: String
    let value: String
    var icon: String?
    var tint: Color = T.tinta
    /// Comparación con la media del jugador. Nil = no hay historial suficiente o la
    /// diferencia es despreciable; en los dos casos no se enseña nada, que es mejor que
    /// enseñar un "+0" que parece un dato.
    var contexto: Comparativa?
    /// Decimales del contexto. Los golpeos no llevan; el ritmo, uno.
    var decimales: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                }
                Text(label.uppercased())
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .kerning(0.8)
            }
            .foregroundStyle(T.tintaSuave)

            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let contexto {
                Text(contexto.texto(decimales: decimales))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(contexto.mejor ? T.verde : T.tintaSuave)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Barra de proporción con etiqueta y valor, para desgloses.
struct PadelBar: View {
    let label: String
    let value: String
    let fraction: Float
    var color: Color = T.pista

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(T.tinta)
                Spacer()
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(T.tintaSuave)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(T.borde)
                    Capsule()
                        .fill(color)
                        // Un mínimo visible: una barra de 0 px no comunica "casi nada",
                        // comunica "nada".
                        .frame(width: geometry.size.width * CGFloat(min(max(fraction, 0.02), 1)))
                }
            }
            .frame(height: 7)
        }
    }
}

/// Distintivo de resultado (ganado / perdido / sin terminar).
struct OutcomeBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .kerning(1.2)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color, in: Capsule())
    }
}
