import Foundation

/// Resultado de medir un objetivo contra los golpeos de la sesión.
public struct ObjectiveMeasurement: Equatable, Sendable {
    /// El número que pide el objetivo.
    public let target: Int
    /// Lo que el reloj contó.
    public let actual: Int
    /// Si se cumplió, respetando la dirección (mínimo/máximo).
    public let met: Bool

    public init(target: Int, actual: Int, met: Bool) {
        self.target = target
        self.actual = actual
        self.met = met
    }
}

/// Un objetivo medible con su progreso, para pintarlo en vivo.
public struct ObjectiveProgress: Equatable, Sendable, Identifiable {
    public let text: String
    public let measurement: ObjectiveMeasurement

    public var id: String { text }
    /// Etiqueta corta para la muñeca: "11/15".
    public var label: String { "\(measurement.actual)/\(measurement.target)" }

    public init(text: String, measurement: ObjectiveMeasurement) {
        self.text = text
        self.measurement = measurement
    }
}

/// Mide objetivos de partido escritos en texto libre contra lo que el reloj contó.
///
/// "Hacer 15 bandejas" es medible: el reloj sabe cuántas bandejas hubo. "Ganar 2 puntos
/// con bandeja" no lo es: el reloj cuenta golpeos, no sabe quién ganó el punto. La regla
/// que gobierna el evaluador es la de los insights — **antes en silencio que inventado**:
/// un objetivo solo se mide si habla de una cantidad de golpeos de un tipo que el reloj
/// detecta y no menciona nada que el reloj no ve (puntos, fallos, colocación, juegos).
/// Todo lo demás devuelve nil y se marca a mano, como siempre.
///
/// El espejo exacto de `ObjectiveEvaluator.kt`; los tests viven en el core Kotlin.
public enum ObjectiveEvaluator {

    /// Palabras que delatan que el objetivo habla de algo que el reloj no ve. Con una
    /// de estas, mejor no medir: "ganar 2 puntos con bandeja" contarían bandejas y
    /// mentiría.
    private static let fueraDeAlcance = [
        "punto", "fallo", "error", "gan", "pierd", "perder", "red", "blanco",
        "juego", "set", "pared", "dejada", "chiquita", "globo", "resto",
        "a la t", "%", "racha", "calent", "molestia", "protest", "comunic",
    ]

    /// Palabras de cada tipo de golpe que el reloj sabe contar.
    private static let golpes: [(String, [ShotType])] = [
        ("bandeja", [.bandeja]),
        ("vibora", [.vibora]),
        ("remate", [.smash]),
        ("smash", [.smash]),
        ("saque", [.serve]),
        ("derecha", [.forehand]),
        ("reves", [.backhand]),
        ("volea", [.forehandVolley, .backhandVolley]),
    ]

    // Se compara contra el texto ya normalizado (sin tildes).
    private static let maximo = ["menos de", "maximo", "como mucho", "no mas de"]

    /// Mide un objetivo contra los recuentos de la sesión, o nil si no es medible.
    public static func evaluate(
        _ objetivo: String,
        shotsByType: [ShotType: Int],
        totalShots: Int
    ) -> ObjectiveMeasurement? {
        let texto = normaliza(objetivo)
        guard !fueraDeAlcance.contains(where: { texto.contains($0) }) else { return nil }

        guard let match = texto.range(of: "[0-9]+", options: .regularExpression),
              let target = Int(texto[match]) else { return nil }

        let actual: Int
        if let tipos = golpes.first(where: { texto.contains($0.0) })?.1 {
            actual = tipos.reduce(0) { $0 + (shotsByType[$1] ?? 0) }
        } else if texto.contains("golpe") {
            actual = totalShots
        } else {
            return nil
        }

        // Sin señal de tope, un objetivo de cantidad pide llegar: "hacer 15 bandejas"
        // es un mínimo aunque no diga "mínimo".
        let esMaximo = maximo.contains { texto.contains($0) }
        return ObjectiveMeasurement(
            target: target,
            actual: actual,
            met: esMaximo ? actual <= target : actual >= target
        )
    }

    /// Los objetivos que el reloj puede seguir en vivo, con su progreso.
    ///
    /// Es lo mismo que `evaluate` pero sobre los golpeos que llevas hasta ahora: el
    /// reloj lo llama en cada golpe para enseñar "bandejas 11/15". Los no medibles no
    /// salen — en una pantalla de 45 mm, una lista que no se mueve es ruido.
    public static func progress(
        objetivos: [String],
        shotsByType: [ShotType: Int],
        totalShots: Int
    ) -> [ObjectiveProgress] {
        objetivos.compactMap { objetivo in
            evaluate(objetivo, shotsByType: shotsByType, totalShots: totalShots)
                .map { ObjectiveProgress(text: objetivo, measurement: $0) }
        }
    }

    private static func normaliza(_ texto: String) -> String {
        texto.lowercased()
            .replacingOccurrences(of: "á", with: "a")
            .replacingOccurrences(of: "é", with: "e")
            .replacingOccurrences(of: "í", with: "i")
            .replacingOccurrences(of: "ó", with: "o")
            .replacingOccurrences(of: "ú", with: "u")
    }
}
