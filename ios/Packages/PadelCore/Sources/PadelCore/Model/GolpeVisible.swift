import Foundation

/// El repertorio que la app le **enseña** al jugador, que no es el mismo que el que
/// distingue el detector por dentro.
///
/// ### Por qué existe esta capa
///
/// El detector separa diez tipos; la app enseña nueve. **La única que se pliega es la
/// víbora dentro de la bandeja**, y no por gusto: las dos tandas limpias de pista se
/// contradicen sobre cuál de las dos se golpea más alta, así que separarlas sin
/// calibrar es echar una moneda al aire con dos nombres puestos.
///
/// Medido sobre los 82 golpes etiquetados de esas dos tandas (ago 2026):
///
/// | | diez tipos | repertorio visible |
/// |---|---|---|
/// | tanda de 42 | 71 % | **76 %** |
/// | tanda de 40 (calibrada) | 80 % | **82 %** |
/// | las dos juntas | 68 % | **74 %** |
///
/// ### Por qué la volea y el globo SÍ llevan lado
///
/// Plegar también el lado de la volea daba más acierto de tabla —85 % en la tanda de 42
/// en vez de 76 %— y aun así se descartó: para un jugador no es lo mismo tener floja la
/// volea de derecha que la de revés, y una app que no se lo puede decir no le sirve
/// para entrenar. El número de la tabla mide otra cosa que lo útil que es el dato.
///
/// Hay que decirlo claro de todas formas: **el lado de la volea hoy es poco fiable**.
/// Lo decide el signo de la rotación axial, y las diez voleas de la tanda de 42
/// midieron entre 0,1 y 3,9 rad/s, que es ruido. En el globo el mismo signo tiene mejor
/// pinta —es un swing completo con muñeca, no un bloqueo— pero no hay tanda con la que
/// decirlo. Las dos cosas las arregla el modelo entrenado, no un umbral.
///
/// El detector **sigue** produciendo los diez tipos y las tandas se graban con ellos,
/// que es lo que alimenta al modelo. Esto solo decide qué se le enseña a una persona.
///
/// Espejo de `GolpeVisible` en el core Kotlin, con los tests allí.
public enum GolpeVisible: String, CaseIterable, Sendable {
    case derecha
    case reves
    case voleaDerecha
    case voleaReves
    case globoDerecha
    case globoReves
    case bandeja
    case remate
    case saque

    public var etiqueta: String {
        switch self {
        case .derecha: return "Derecha"
        case .reves: return "Revés"
        case .voleaDerecha: return "Volea de derecha"
        case .voleaReves: return "Volea de revés"
        case .globoDerecha: return "Globo de derecha"
        case .globoReves: return "Globo de revés"
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
        case .forehandVolley: return .voleaDerecha
        case .backhandVolley: return .voleaReves
        case .forehandLob: return .globoDerecha
        case .backhandLob: return .globoReves
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
