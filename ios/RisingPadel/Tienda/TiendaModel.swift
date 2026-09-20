import Foundation
import StoreKit

/// La tienda: los productos, la compra y —lo importante— **qué plan tiene este jugador**.
///
/// ## Por qué el estado de la suscripción no se decide aquí
///
/// StoreKit sabe si hay una compra en este iPhone, pero la cuota del entrenador la cobra
/// el Worker (`consumo()` en `server/live/src/coach.js`), que solo mira la tabla
/// `subscriptions`. Así que cada vez que algo cambia, este modelo hace una sola cosa:
/// mandarle al servidor el `originalTransactionId` para que **él** se lo pregunte a
/// Apple y escriba el plan. El iPhone nunca dice "soy Pro": dice "esta es mi compra,
/// pregunta tú".
///
/// El plan que se guarda aquí es, entonces, una copia de lo que contestó el servidor, y
/// sirve para pintar pantallas. Ver `Gating`.
///
/// ## Por qué `Transaction.updates` y no el resultado de la compra
///
/// La compra solo ocurre una vez; todo lo demás llega por `Transaction.updates`: la
/// renovación mensual, el cambio de mensual a anual, la compra hecha en otro dispositivo
/// del mismo ID de Apple, la que se aprueba horas después con "Compartir en familia",
/// y —la que más duele si se ignora— **el reembolso y la revocación**. Si solo se
/// escuchara el resultado de `purchase()`, un jugador al que Apple le devuelve el dinero
/// seguiría siendo Pro para siempre.
///
/// Por eso la escucha arranca en el `init` y **no se cancela nunca**: es un hilo que
/// tiene que estar vivo mientras la app lo esté. Y por eso el modelo es un singleton
/// (`compartida`): dos instancias serían dos escuchas y dos sincronizaciones por cada
/// renovación.
@MainActor
final class TiendaModel: ObservableObject {

    /// Los productos de App Store Connect. **Tienen que coincidir carácter a carácter**
    /// con los de allí y con el mapa `PLANES` de `server/live/src/suscripciones.js`.
    static let identificadores = [
        "com.risingpadel.watch.pro.mensual",
        "com.risingpadel.watch.pro.anual",
    ]

    static let compartida = TiendaModel()

    /// El plan vigente según el servidor ('free' | 'pro' | 'elite').
    @Published private(set) var plan: String
    /// Los dos productos, ordenados de menos a más duración (mensual, anual).
    @Published private(set) var productos: [Product] = []
    /// Hay una compra o una restauración en marcha.
    @Published private(set) var comprando = false
    /// Lo último que hay que contarle al jugador. Lo pinta el paywall.
    @Published var mensaje: String?

    /// La escucha de cambios. Se guarda para que no la recoja nadie, nunca para
    /// cancelarla: ver la explicación de arriba.
    private var escuchaDeCambios: Task<Void, Never>?

    private init() {
        // Lo último que dijo el servidor, para que la app abra sabiendo ya quién es.
        plan = UserDefaults.standard.string(forKey: Gating.clavePlan) ?? Gating.planGratuito

        escuchaDeCambios = Task { [weak self] in
            for await cambio in Transaction.updates {
                await self?.atender(cambio)
            }
        }

        Task { [weak self] in
            await self?.cargarProductos()
            await self?.revisarDerechos()
        }
    }

    // MARK: Catálogo

    /// Pide los productos a App Store Connect. Si falla no se inventa nada: la pantalla
    /// de venta enseña que no pudo cargar y ofrece reintentar. **Nunca un precio escrito
    /// en el código** — el precio real vive en App Store Connect, cambia por país y por
    /// promoción, y enseñar uno distinto del que cobra Apple es engañar al cliente
    /// (además de motivo de rechazo en la revisión).
    func cargarProductos() async {
        do {
            let encontrados = try await Product.products(for: Self.identificadores)
            // El orden de `products(for:)` no está garantizado y la pantalla necesita uno
            // estable: primero el de periodo más corto.
            productos = encontrados.sorted { Self.dias($0) < Self.dias($1) }
            if productos.isEmpty {
                mensaje = "La App Store no devolvió ningún producto. Revisa que la "
                    + "suscripción esté lista en App Store Connect."
            }
        } catch {
            mensaje = "No se pudo cargar la suscripción: \(error.localizedDescription)"
        }
    }

    /// Duración del periodo en días, solo para ordenar. Aproximada a posta: no se usa
    /// para calcular ni enseñar nada, únicamente para que mensual vaya antes que anual.
    private static func dias(_ producto: Product) -> Int {
        guard let periodo = producto.subscription?.subscriptionPeriod else { return 0 }
        switch periodo.unit {
        case .day: return periodo.value
        case .week: return periodo.value * 7
        case .month: return periodo.value * 30
        case .year: return periodo.value * 365
        @unknown default: return 0
        }
    }

    // MARK: Comprar y restaurar

    func comprar(_ producto: Product) async {
        guard !comprando else { return }
        comprando = true
        mensaje = nil
        defer { comprando = false }

        do {
            var opciones: Set<Product.PurchaseOption> = []
            // Se pega la cuenta de Rising Pádel a la compra. Apple la devuelve dentro de
            // la transacción firmada, y con ella el servidor puede comprobar que quien
            // reclama la suscripción es quien la compró — ver `cuentaDeCompra()`.
            if let cuenta = Self.cuentaDeCompra() {
                opciones.insert(.appAccountToken(cuenta))
            }

            switch try await producto.purchase(options: opciones) {
            case .success(let verificacion):
                await atender(verificacion)
            case .userCancelled:
                break
            case .pending:
                // "Pedir permiso para comprar" y compras que requieren aprobación: la
                // transacción llegará más tarde por `Transaction.updates`, sola.
                mensaje = "La compra está pendiente de aprobación. Se activará sola en "
                    + "cuanto Apple la confirme."
            @unknown default:
                mensaje = "La App Store devolvió un resultado que esta versión no entiende."
            }
        } catch {
            mensaje = "No se pudo completar la compra: \(error.localizedDescription)"
        }
    }

    /// Restaurar compras. **Apple lo exige** en cualquier app con suscripción: sin un
    /// botón que lo haga, la revisión la rechaza (guía 3.1.1). Y hace falta de verdad:
    /// es lo que devuelve el plan en un móvil nuevo o después de reinstalar.
    func restaurar() async {
        guard !comprando else { return }
        comprando = true
        mensaje = nil
        defer { comprando = false }

        do {
            try await AppStore.sync()
            await revisarDerechos()
            mensaje = Gating.esPro(plan)
                ? "Listo: tu suscripción está activa."
                : "No hemos encontrado ninguna suscripción activa con este ID de Apple."
        } catch {
            mensaje = "No se pudieron restaurar las compras: \(error.localizedDescription)"
        }
    }

    // MARK: Derechos

    /// Lo que StoreKit dice que este jugador tiene comprado ahora mismo.
    ///
    /// Se llama al arrancar porque `Transaction.updates` solo trae **cambios**: si la
    /// suscripción se compró en otro móvil, o la app se acaba de reinstalar, no llega
    /// ningún cambio y sin esto el jugador abriría la app como gratuito.
    func revisarDerechos() async {
        var compra: String?
        for await resultado in Transaction.currentEntitlements {
            guard case .verified(let transaccion) = resultado,
                  Self.identificadores.contains(transaccion.productID),
                  transaccion.revocationDate == nil else { continue }
            if let fin = transaccion.expirationDate, fin < Date() { continue }
            compra = String(transaccion.originalID)
        }

        guard let compra else {
            // Sin compra en este dispositivo, manda lo que diga el servidor: puede haber
            // una suscripción vigente que este iPhone todavía no ha visto.
            await consultarPlan()
            return
        }

        // Se abre la interfaz sin esperar a la red. Esto NO es regalar nada: lo que
        // cuesta dinero (las llamadas al modelo) lo sigue midiendo el servidor con su
        // propia tabla, y en un segundo la respuesta de `sincronizar` pone el plan real.
        aplicar(plan: "pro")
        await sincronizar(compra)
    }

    /// Atiende una transacción, venga de una compra o de `Transaction.updates`.
    private func atender(_ resultado: VerificationResult<Transaction>) async {
        switch resultado {
        case .verified(let transaccion):
            // `finish()` SIEMPRE, y antes de nada más: una transacción sin terminar se
            // le vuelve a presentar a la app en cada arranque, para siempre.
            await transaccion.finish()
            await sincronizar(String(transaccion.originalID))
        case .unverified:
            // Firma que no cuadra: ni se termina ni se sincroniza. Lo normal es que sea
            // un intento de colar una compra falsa, y el servidor lo rechazaría igual.
            mensaje = "Apple no ha podido verificar esa compra."
        }
    }

    // MARK: El servidor, que es quien manda

    private struct RespuestaDePlan: Decodable {
        let plan: String?
    }

    /// Le manda al servidor el identificador de la compra para que se lo pregunte a
    /// Apple. La respuesta trae el plan que se ha escrito en `subscriptions`.
    private func sincronizar(_ originalTransactionId: String) async {
        guard var peticion = Self.peticion("/v1/suscripcion/sincronizar", metodo: "POST") else {
            return
        }
        peticion.httpBody = try? JSONSerialization.data(
            withJSONObject: ["originalTransactionId": originalTransactionId]
        )

        guard let (datos, respuesta) = try? await URLSession.shared.data(for: peticion),
              let http = respuesta as? HTTPURLResponse else { return }

        switch http.statusCode {
        case 200..<300:
            if let cuerpo = try? JSONDecoder().decode(RespuestaDePlan.self, from: datos),
               let plan = cuerpo.plan {
                aplicar(plan: plan)
            }
        case 403:
            mensaje = "Esa suscripción está asociada a otra cuenta de Rising Pádel."
        case 404:
            // O este servidor no vende suscripciones (no tiene las claves de Apple), o
            // Apple no reconoce la compra. En los dos casos no hay nada que hacer aquí y
            // tampoco hay nada que contarle al jugador: el paywall se sigue viendo.
            break
        default:
            break
        }
    }

    /// El plan que dice el servidor, sin pasar por Apple. Lo barato para arrancar.
    func consultarPlan() async {
        guard let peticion = Self.peticion("/v1/suscripcion", metodo: "GET"),
              let (datos, respuesta) = try? await URLSession.shared.data(for: peticion),
              let http = respuesta as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let cuerpo = try? JSONDecoder().decode(RespuestaDePlan.self, from: datos),
              let plan = cuerpo.plan else { return }
        aplicar(plan: plan)
    }

    private func aplicar(plan nuevo: String) {
        guard plan != nuevo else { return }
        plan = nuevo
        UserDefaults.standard.set(nuevo, forKey: Gating.clavePlan)
    }

    // MARK: Fontanería

    /// La petición al servidor de la liga, con el token de la cuenta. El mismo patrón que
    /// usa `CoachService.porElServidor`: la URL en UserDefaults, el token en el Llavero.
    /// Sin servidor o sin cuenta no hay nada que sincronizar — la compra se queda hecha
    /// en Apple y se sincronizará en cuanto el jugador conecte su cuenta.
    private static func peticion(_ ruta: String, metodo: String) -> URLRequest? {
        guard let base = CoachService.servidorConfigurado(),
              let token = ComunidadCuenta.read("token") else { return nil }
        let raiz = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let url = URL(string: raiz + ruta) else { return nil }

        var salida = URLRequest(url: url)
        salida.httpMethod = metodo
        salida.setValue("application/json", forHTTPHeaderField: "content-type")
        salida.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        salida.timeoutInterval = 30
        return salida
    }

    /// El `appAccountToken` de esta cuenta: un UUID derivado del token de la comunidad.
    ///
    /// Apple guarda este valor dentro de la transacción firmada y se lo devuelve al
    /// servidor, que comprueba que coincide con el de quien reclama la suscripción. Sin
    /// él, cualquiera que conociese el `originalTransactionId` de un suscriptor podría
    /// pedirlo para su propia cuenta.
    ///
    /// Se deriva en vez de guardarse para no tener un dato más que sincronizar: el token
    /// de la cuenta ya es aleatorio y ya vive en el Llavero. Un UUID son 16 bytes = 32
    /// caracteres hexadecimales, y el token tiene 48. **La misma derivación está escrita
    /// en `cuentaEsperada()` del servidor; si se cambia una, hay que cambiar la otra.**
    static func cuentaDeCompra() -> UUID? {
        guard let token = ComunidadCuenta.read("token")?.lowercased(), token.count >= 32 else {
            return nil
        }
        let hexadecimal = Array(token.prefix(32))
        guard hexadecimal.allSatisfy({ $0.isHexDigit }) else { return nil }
        let texto = String(hexadecimal[0..<8]) + "-"
            + String(hexadecimal[8..<12]) + "-"
            + String(hexadecimal[12..<16]) + "-"
            + String(hexadecimal[16..<20]) + "-"
            + String(hexadecimal[20..<32])
        return UUID(uuidString: texto)
    }
}
