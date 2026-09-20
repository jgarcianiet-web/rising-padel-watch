import Foundation

// Qué es de pago y qué no. **Un solo sitio, a propósito.**
//
// El reparto entre gratis y Pro no es una decisión técnica: la va a revisar el dueño del
// producto, probablemente varias veces, y casi seguro después de ver los primeros
// números de conversión. Si esa decisión estuviera repartida por las pantallas ("aquí un
// `if plan == pro`, allí otro"), cada cambio de reparto sería una cacería por el
// proyecto y el riesgo de dejarse una puerta abierta sería alto.
//
// Así que el reparto vive en `Gating.requierePro(_:)`, que es un `switch` con una línea
// por función. Mover una función de un lado a otro es mover una línea de ese switch.
//
// **Esto NO es la defensa del negocio.** Lo que cuesta dinero de verdad es el entrenador
// IA, y ese lo protege el servidor: `consumo()` en `server/live/src/coach.js` lee la
// tabla `subscriptions` —que solo escribe el Worker, después de preguntarle a Apple— y
// de ahí sale la cuota del mes. Un cliente modificado que se salte este fichero se
// encuentra con la cuota del plan gratuito igual. Aquí solo se decide **qué se enseña**.

/// Las funciones de la app que pueden pedir Pro. Añadir una es añadir un `case` y su
/// línea en `requierePro(_:)`.
enum FuncionPro: String, CaseIterable, Identifiable {
    /// El chat con Rising AI y el análisis de partidos.
    case entrenadorIA
    /// Las metas por golpe ("Bandeja 2,6 → 3,5").
    case objetivosDeGolpe
    /// La pestaña Evolución con los tramos de la temporada.
    case evolucionPorTramos

    var id: String { rawValue }

    /// El nombre con el que se vende, no el nombre interno.
    var titulo: String {
        switch self {
        case .entrenadorIA: return "Rising AI, tu entrenador"
        case .objetivosDeGolpe: return "Objetivos por golpe"
        case .evolucionPorTramos: return "Evolución por tramos"
        }
    }

    /// Qué gana el jugador. En la pantalla de venta esto es lo que se lee de verdad.
    var explicacion: String {
        switch self {
        case .entrenadorIA:
            return "Pregúntale qué entrenar, por qué no mejoras o qué hiciste peor hoy. "
                + "Conoce tus partidos y lo que mide tu reloj."
        case .objetivosDeGolpe:
            return "Ponle una meta a cada golpe y mira cuánto camino llevas después de "
                + "cada partido."
        case .evolucionPorTramos:
            return "Tu temporada partida en tramos: qué mejoró, qué se estancó y desde "
                + "cuándo."
        }
    }
}

enum Gating {

    /// Dónde se guarda el último plan conocido. Lo escribe `TiendaModel` y lo lee esto.
    ///
    /// En `UserDefaults` y no solo en memoria porque el plan tiene que estar disponible
    /// **en el primer fotograma** después de abrir la app: preguntarle al servidor tarda
    /// cientos de milisegundos, y un suscriptor que ve su pantalla de pago convertida en
    /// un anuncio cada vez que abre la app tiene toda la razón al pedir la devolución.
    static let clavePlan = "planSuscripcion"

    /// El nombre del plan gratuito. Es el que usa el servidor en `subscriptions.plan`.
    static let planGratuito = "free"

    /// El plan que se creía vigente la última vez. Para vistas que no observan la tienda.
    static var planActual: String {
        UserDefaults.standard.string(forKey: clavePlan) ?? planGratuito
    }

    /// 'pro' y 'elite' dan acceso; 'elite' existe ya en las cuotas del servidor
    /// (`CUOTA` en coach.js) aunque todavía no se venda, y nombrarlo aquí evita que el
    /// día que se venda alguien con plan superior se quede sin las funciones de pago.
    static func esPro(_ plan: String) -> Bool {
        plan == "pro" || plan == "elite"
    }

    /// **El reparto.** Una línea por función; esto es lo que se revisa y lo que se toca.
    static func requierePro(_ funcion: FuncionPro) -> Bool {
        switch funcion {
        case .entrenadorIA: return true
        case .objetivosDeGolpe: return true
        case .evolucionPorTramos: return true
        }
    }

    /// Si el jugador puede usar esa función con el plan que tiene.
    ///
    /// **El entrenador tiene una puerta más**, y no es una grieta: quien pone su propia
    /// clave de API le está pagando a Anthropic de su bolsillo en cada pregunta, así que
    /// cobrarle por el entrenador sería cobrarle por algo que el servicio no le está
    /// dando. Es el caso del que monta su propio servidor, y también el del dueño de
    /// este, que es quien paga la clave de todos los demás.
    ///
    /// No abre nada que cueste dinero ajeno: las peticiones con clave propia van directas
    /// a Anthropic desde el móvil y no tocan el servidor. Lo que sí cuesta —la clave del
    /// servicio— lo sigue guardando la cuota de `coach.js`, que no mira este fichero.
    static func disponible(_ funcion: FuncionPro, plan: String) -> Bool {
        if !requierePro(funcion) || esPro(plan) { return true }
        return funcion == .entrenadorIA && CoachKeyStore.read() != nil
    }
}
