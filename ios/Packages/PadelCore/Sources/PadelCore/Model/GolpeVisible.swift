import Foundation

/// El repertorio que la app le **enseña** al jugador, que no es el mismo que el que
/// distingue el detector por dentro.
///
/// ### Por qué existe esta capa
///
/// El detector separa nueve tipos; la app enseña siete. La diferencia no es cosmética,
/// es una decisión medida. Con las dos tandas limpias de pista (82 golpes etiquetados,
/// ago 2026) el acierto es:
///
/// | | ocho tipos | repertorio visible |
/// |---|---|---|
/// | tanda de 42 | 71 % | **85 %** |
/// | tanda de 40 (calibrada) | 80 % | **82 %** |
/// | las dos juntas | 68 % | **79 %** |
///
/// Las dos distinciones que se pliegan son justo las dos que los datos dicen que hoy no
/// se pueden sostener:
///
/// - **Víbora dentro de bandeja.** Las dos tandas se contradicen: en una la bandeja se
///   golpea más alta que la víbora y en la otra más baja. Mientras un jugador no
///   calibre con sus propias tandas, separarlas es echar una moneda al aire con dos
///   nombres.
/// - **El lado de la volea.** Una volea es un bloqueo sin muñeca, y el efecto que
///   decidiría el lado no está en la señal: las diez voleas de la tanda de 42 midieron
///   entre 0,1 y 3,9 de rotación axial, que es ruido.
///
/// Nada de esto se pierde: el detector **sigue** produciendo los nueve tipos y las
/// tandas se graban con ellos, que es lo que alimenta al modelo entrenado. Esto solo
/// decide qué se le enseña a una persona.
///
/// Espejo de `GolpeVisible` en el core Kotlin, con los tests allí.
public enum GolpeVisible: String, CaseIterable, Sendable {
    case derecha
    case reves
    case volea
    case globo
    case bandeja
    case remate
    case saque

    public var etiqueta: String {
        switch self {
        case .derecha: return "Derecha"
        case .reves: return "Revés"
        case .volea: return "Volea"
        case .globo: return "Globo"
        case .bandeja: return "Bandeja"
        case .remate: return "Remate"
        case .saque: return "Saque"
        }
    }

    /// El golpe que se le enseña al jugador, o nil si no hay nada que enseñar.
    public static func de(_ tipo: ShotType) -> GolpeVisible? {
        switch tipo {
        case .forehand: return .derecha
        case .backhand: return .reves
        case .forehandVolley, .backhandVolley: return .volea
        case .lob: return .globo
        // La víbora se pliega dentro de la bandeja: las dos son el golpe alto de
        // control y hoy no se separan con garantías. Ver la cabecera.
        case .bandeja, .vibora: return .bandeja
        case .smash: return .remate
        case .serve: return .saque
        case .unknown: return nil
        }
    }

    /// Agrupa notas **promediando**, no sumando: una nota de 1 a 7 no se acumula. Si un
    /// jugador dio bandejas de 3,0 y víboras de 3,4, su bandeja visible es 3,2.
    public static func agruparNotas(_ porTipo: [ShotType: Float]) -> [(GolpeVisible, Float)] {
        var acumulado: [GolpeVisible: [Float]] = [:]
        for (tipo, nota) in porTipo {
            guard let visible = de(tipo) else { continue }
            acumulado[visible, default: []].append(nota)
        }
        // En el orden del repertorio, no en el del diccionario: la ficha de un partido
        // tiene que leerse igual siempre.
        return allCases.compactMap { visible in
            guard let notas = acumulado[visible], !notas.isEmpty else { return nil }
            return (visible, notas.reduce(0, +) / Float(notas.count))
        }
    }

    /// Agrupa recuentos **sumando**: doce bandejas y tres víboras son quince.
    public static func agruparRecuentos(_ porTipo: [ShotType: Int]) -> [(GolpeVisible, Int)] {
        var acumulado: [GolpeVisible: Int] = [:]
        for (tipo, cuantos) in porTipo where cuantos > 0 {
            guard let visible = de(tipo) else { continue }
            acumulado[visible, default: 0] += cuantos
        }
        return allCases.compactMap { visible in
            guard let total = acumulado[visible] else { return nil }
            return (visible, total)
        }
    }
}
