import Foundation
import PadelCore
import SwiftUI

/// Estado de la app de iPhone: historial de sesiones, ajustes y sincronización.
@MainActor
final class AppModel: ObservableObject {

    @Published private(set) var sessions: [PadelSession] = []
    @Published var message: String?

    /// Partido en curso en el reloj, o nil si no hay ninguno. Alimenta el banner en vivo.
    @Published private(set) var liveMatch: LiveMatchState?

    @AppStorage("leagueBaseURL") var leagueBaseURL = ""
    @AppStorage("shareHealth") var shareHealth = false
    @AppStorage("shareShotEvents") var shareShotEvents = true
    @AppStorage("playerHand") var playerHandRaw = Hand.right.rawValue
    @AppStorage("watchWrist") var watchWristRaw = Hand.right.rawValue
    @AppStorage("sensitivity") var sensitivityRaw = Sensitivity.medium.rawValue
    @AppStorage("collectTrainingData") var collectTrainingData = false
    /// Desbloquea el modo de recogida de datos. Es una herramienta de quien construye
    /// el dataset, no de quien juega: para un usuario normal no existe. Siete toques en
    /// la versión lo activan; con cuentas de la liga pasará a depender de un rol real.
    @AppStorage("developerMode") var developerMode = false
    @AppStorage("playerAlias") var playerAlias = "anon"
    /// Nivel de pádel del jugador (1-7); 0 = sin configurar. Es el ancla para calibrar
    /// la escala: los golpes grabados llevan el nivel de quien los dio.
    @AppStorage("playerLevel") var playerLevelRaw = 0

    /// Fichero de datos de entrenamiento recibido del reloj. **Nunca se sube a la liga**:
    /// solo se exporta cuando el usuario lo comparte a mano. Ver `docs/training-data.md`.
    @Published private(set) var trainingDataURL: URL?
    @Published private(set) var trainingDataSizeKB = 0

    private let store: SessionStore
    private let syncQueue: SyncQueue
    private var receiver: WatchSessionReceiver?

    var hasToken: Bool { KeychainTokenStore.read() != nil }

    var profile: PlayerProfile {
        PlayerProfile(
            hand: Hand(rawValue: playerHandRaw) ?? .right,
            watchWrist: Hand(rawValue: watchWristRaw) ?? .right
        )
    }

    init(store: SessionStore? = nil) {
        let resolved = store ?? FileSessionStore(directory: Self.sessionsDirectory())
        self.store = resolved
        self.syncQueue = SyncQueue(store: resolved, client: LeagueAPIClient())
        self.sessions = resolved.all()

        // El receptor se activa aquí y no en la vista: las sesiones llegan aunque el
        // usuario nunca abra la pantalla del historial.
        let receiver = WatchSessionReceiver(
            onSessionReceived: { [weak self] session in
                Task { @MainActor in self?.receive(session) }
            },
            onTrainingFileReceived: { [weak self] url in
                // Se copia sincrónicamente: el sistema borra el temporal al volver.
                let destination = Self.trainingDataDestination()
                try? FileManager.default.removeItem(at: destination)
                try? FileManager.default.copyItem(at: url, to: destination)
                Task { @MainActor in self?.refreshTrainingData() }
            },
            onLiveState: { [weak self] state in
                Task { @MainActor in self?.receiveLive(state) }
            }
        )
        // El reloj devuelve su estado por la cola cuando la orden le llegó dormido.
        receiver.onEstadoDeTanda = { [weak self] estado in
            Task { @MainActor in self?.aplicarEstadoDeTanda(estado, deOrden: nil) }
        }
        receiver.activate()
        self.receiver = receiver
        refreshTrainingData()
        // La escala de nivel calibrada manda desde el primer render.
        aplicarEscalaDeNivel()
        observeSettingsChanges()
    }

    func refresh() {
        sessions = store.all()
        // Barato: la parte cara (releer y clasificar las tandas) está cacheada aparte.
        recalcularPrecision()
    }

    // MARK: Marcador en vivo

    /// Un estado viejo reentregado por el sistema no puede pisar uno más nuevo, y el
    /// partido terminado se queda en pantalla como resultado final hasta que llega la
    /// sesión completa del reloj (que lo sustituye con todo el detalle).
    private func receiveLive(_ state: LiveMatchState) {
        if let current = liveMatch, current.sessionId == state.sessionId,
           state.updatedAtEpochMs < current.updatedAtEpochMs {
            return
        }
        liveMatch = state

        // El marcador también vive en la pantalla de bloqueo y la Dynamic Island.
        liveActivity.update(with: state)

        // Si hay liga configurada, el estado se republica para que otros lo sigan.
        // Fuego y olvido: sin cola, la siguiente actualización corrige sola.
        if let config = leagueConfig() {
            Task { await LiveScorePublisher().publish(state, config: config) }
        }
    }

    private let liveActivity = LiveActivityController()

    /// Enlace público para seguir el partido: la página de espectador del servidor de
    /// la liga (`server/live`), que vive en la misma URL base. Nil sin liga configurada.
    func liveSpectatorURL(for sessionId: String) -> URL? {
        var base = leagueBaseURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return nil }
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + "/" + sessionId)
    }

    /// Nivel medio del jugador sobre su historial: la línea de referencia de las
    /// gráficas ("calidad media"). Nil sin sesiones puntuables.
    var playerAverageLevel: Float? {
        let levels = sessions.map(\.level).filter { $0.gradedShots > 0 }.map(\.overall)
        guard !levels.isEmpty else { return nil }
        return levels.reduce(0, +) / Float(levels.count)
    }

    /// Siete toques en la versión. Apagarlo apaga también la recogida de datos, para
    /// que no quede la grabación activa escondida — la replicación quita el botón del
    /// reloj al propagarse el cambio.
    private var versionTaps = 0
    func versionTapped() {
        versionTaps += 1
        guard versionTaps >= 7 else { return }
        versionTaps = 0
        developerMode.toggle()
        if !developerMode {
            collectTrainingData = false
        }
        message = developerMode ? "Modo desarrollador activado" : "Modo desarrollador desactivado"
    }

    // MARK: Replicación de ajustes al reloj

    /// Marca de tiempo de la última edición de un ajuste replicado al reloj.
    ///
    /// `Double` y no `Int` por la misma razón que en el reloj: este valor viaja a
    /// relojes arm64_32 donde `Int` es de 32 bits y una época en milisegundos no cabe.
    /// En el iPhone `Int` habría funcionado, pero los dos lados usan el mismo tipo para
    /// que nadie pueda reintroducir el desbordamiento copiando código de un lado a otro.
    @AppStorage("settingsUpdatedAt") private var settingsUpdatedAtMs: Double = 0

    /// Lo último que se mandó, para no reenviar en cada escritura de UserDefaults.
    private var lastReplicated: DeviceSettings?
    private var settingsObserver: NSObjectProtocol?

    /// Los ajustes que el reloj necesita, con la marca de tiempo actual.
    var deviceSettings: DeviceSettings {
        DeviceSettings(
            profile: profile,
            sensitivity: Sensitivity(rawValue: sensitivityRaw) ?? .medium,
            shareHealth: shareHealth,
            collectTrainingData: collectTrainingData,
            // Se normaliza aquí y no en el campo de texto: reescribir mientras el usuario
            // teclea es hostil, y lo que importa es que lo que viaja sea consistente.
            playerAlias: DeviceSettings.sanitizeAlias(playerAlias),
            playerLevel: playerLevelRaw > 0 ? playerLevelRaw : nil,
            // Los objetivos de la liga viajan al reloj para que enseñe en vivo los que
            // puede medir. `LigaModel` los deja en UserDefaults al guardarlos, que es
            // además lo que dispara la replicación (se observa UserDefaults).
            matchObjectives: matchObjectivesRaw
                .split(separator: "\n").map(String.init),
            // Los umbrales del jugador viajan con los ajustes: se calculan aquí (el
            // fichero de tandas vive en el móvil) pero quien mide es el reloj.
            calibration: calibration,
            updatedAtEpochMs: Int64(settingsUpdatedAtMs)
        )
    }

    /// Espejo de los objetivos de la liga, en el formato que guarda `LigaModel`.
    @AppStorage("matchObjectives") private var matchObjectivesRaw = ""

    // MARK: Calibración con las tandas del jugador

    /// Los umbrales personales, serializados (`@AppStorage` no entiende de structs).
    @AppStorage("detectorCalibration") private var calibrationJSON = ""

    var calibration: DetectorCalibration? {
        guard let data = calibrationJSON.data(using: .utf8), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(DetectorCalibration.self, from: data)
    }

    /// Recalcula los umbrales del jugador con sus tandas etiquetadas y los replica al
    /// reloj. Devuelve nil si todavía no hay fichero de tandas.
    ///
    /// Es lo que le da sentido al modo de datos sin necesidad de ordenador: la etiqueta
    /// la puso el jugador antes de dar el golpe, así que cada tanda es verdad-terreno
    /// suya, y de ahí salen sus fronteras — no las de una técnica media.
    func calibrarConTandas() -> ResultadoCalibracion? {
        guard let url = trainingDataURL,
              let contenido = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        let decoder = JSONDecoder()
        let etiquetados: [(ShotType, ShotFeatures)] = contenido
            .split(separator: "\n")
            .compactMap { linea in
                guard let data = linea.data(using: .utf8),
                      let muestra = try? decoder.decode(TrainingSample.self, from: data)
                else { return nil }
                return (muestra.label, muestra.heuristicFeatures)
            }
        guard !etiquetados.isEmpty else { return nil }

        let resultado = ThresholdCalibrator.calibrar(
            etiquetados,
            ahoraEpochMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
        if let data = try? JSONEncoder().encode(resultado.calibracion),
           let texto = String(data: data, encoding: .utf8) {
            // Escribir aquí dispara la replicación al reloj (se observa UserDefaults).
            calibrationJSON = texto
        }
        recalcularTandas()
        return resultado
    }

    /// Vuelve a los umbrales de fábrica.
    func borrarCalibracion() {
        calibrationJSON = ""
        recalcularTandas()
    }

    // MARK: Precisión del detector

    /// El informe de acierto del reloj: la pregunta de la que depende todo lo demás.
    ///
    /// Se guarda calculado porque leerlo cuesta: hay que releer el fichero de tandas
    /// entero y volver a clasificar cada golpe. En la portada, que lo pinta en cada
    /// render, calcularlo al vuelo sería una pausa visible con cada scroll.
    ///
    /// A cambio hay que acordarse de recalcularlo cuando cambia algo de lo que depende:
    /// sesiones nuevas, revisiones, tandas nuevas y calibración. Están todos marcados.
    @Published private(set) var precision = InformeDePrecision(
        golpes: [], sesionesRevisadas: 0, golpesEnTandas: 0,
        aciertoGlobal: nil, sinClasificar: nil
    )

    /// Los pares de las tandas, ya clasificados. Se guardan aparte del informe porque
    /// son la mitad cara: releer el fichero y volver a clasificar cada golpe. Cambian
    /// solo cuando llegan tandas nuevas o cuando cambia la calibración; en cambio el
    /// informe cambia también con cada sesión revisada, que es mucho más a menudo.
    private var paresDeTandasCache: [(ShotType, ShotType)] = []

    /// Rehace la parte cara y luego el informe. Solo cuando cambian las tandas o la
    /// calibración.
    func recalcularTandas() {
        paresDeTandasCache = paresDeTandas()
        recalcularPrecision()
    }

    func recalcularPrecision() {
        precision = InformeDePrecision.de(sesiones: sessions, tandas: paresDeTandasCache)
    }

    /// Pares (lo que era, lo que dijo el reloj) sacados de las tandas etiquetadas.
    ///
    /// Se vuelve a pasar el clasificador **con la calibración puesta**, no se lee lo que
    /// el reloj dijo el día de la grabación: lo que interesa saber es cómo de bien
    /// acierta el detector que llevas hoy, no el que llevabas entonces.
    private func paresDeTandas() -> [(ShotType, ShotType)] {
        guard let url = trainingDataURL,
              let contenido = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        var config = DetectorConfig.default
        if let calibration { config = config.applying(calibration) }
        let clasificador = ShotClassifier(config: config)
        let decoder = JSONDecoder()

        return contenido.split(separator: "\n").compactMap { linea in
            guard let data = linea.data(using: .utf8),
                  let muestra = try? decoder.decode(TrainingSample.self, from: data)
            else { return nil }
            return (muestra.label, clasificador.classify(muestra.heuristicFeatures).type)
        }
    }

    // MARK: La escala de nivel, anclada a jugadores de nivel técnico conocido

    /// Las referencias acumuladas: por cada nivel técnico grabado, qué mide el reloj.
    @AppStorage("levelReferences") private var referenciasJSON = ""

    var referenciasDeNivel: [ReferenciaNivel] {
        guard let data = referenciasJSON.data(using: .utf8), !data.isEmpty,
              let lista = try? JSONDecoder().decode([ReferenciaNivel].self, from: data)
        else { return [] }
        return lista
    }

    /// Recalcula las referencias con las tandas grabadas y aplica la escala resultante.
    ///
    /// El nivel de cada tanda es el **técnico** de quien llevaba el reloj, que es lo que
    /// mide esta app. No se usa el nivel de una plataforma de partidos: ese número dice
    /// con quién ganas, no cómo golpeas — un jugador puede tener técnica de 4 y estar en
    /// un 3 competitivo, y mezclarlos haría que la medición no significara nada.
    @discardableResult
    func recalcularEscalaDeNivel() -> [ReferenciaNivel] {
        guard let url = trainingDataURL,
              let contenido = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        let decoder = JSONDecoder()
        // nivel técnico → tipo de golpe → velocidades de pala medidas
        var porNivel: [Float: [String: [Float]]] = [:]
        var golpesPorNivel: [Float: Int] = [:]
        let palanca = DetectorConfig.default.armLeverM

        for linea in contenido.split(separator: "\n") {
            guard let data = linea.data(using: .utf8),
                  let muestra = try? decoder.decode(TrainingSample.self, from: data),
                  let nivel = muestra.playerLevel, nivel > 0 else { continue }
            // La misma fórmula que usa el detector para la velocidad de pala.
            let velocidad = muestra.heuristicFeatures.peakGyroRadS * palanca * 3.6
            let clave = Float(nivel)
            porNivel[clave, default: [:]][muestra.label.wireName, default: []].append(velocidad)
            golpesPorNivel[clave, default: 0] += 1
        }

        let referencias = porNivel.map { nivel, porTipo in
            ReferenciaNivel(
                nivelTecnico: nivel,
                velocidadPorTipo: porTipo.mapValues { valores in
                    let ordenados = valores.sorted()
                    return ordenados[ordenados.count / 2]
                },
                golpes: golpesPorNivel[nivel] ?? 0
            )
        }
        if let data = try? JSONEncoder().encode(referencias),
           let texto = String(data: data, encoding: .utf8) {
            referenciasJSON = texto
        }
        aplicarEscalaDeNivel()
        return referencias
    }

    /// Pone en marcha la escala calibrada. Los golpes sin referencias se quedan con las
    /// bandas de fábrica: se calibra lo que los datos sostienen, nada más.
    func aplicarEscalaDeNivel() {
        let bandas = LevelReferenceCalibrator.bandas(referenciasDeNivel)
        guard !bandas.isEmpty else {
            LevelConfig.current = LevelConfig()
            return
        }
        LevelConfig.current = LevelConfig(
            bands: LevelConfig.defaultBands.merging(bandas) { _, calibrada in calibrada }
        )
    }

    /// Replica al reloj cada cambio de ajustes.
    ///
    /// Se observa `UserDefaults` en vez de enganchar cada `Toggle` porque las vistas
    /// escriben directamente en `@AppStorage`: no hay un setter donde poner la llamada, y
    /// un ajuste nuevo se replicaría solo sin que haya que acordarse de nada.
    private func observeSettingsChanges() {
        // Se parte de lo que hay para que arrancar la app no cuente como una edición: si
        // no, el primer arranque mandaría los valores por defecto con marca reciente y
        // pisaría lo que el reloj tuviera configurado.
        var seed = deviceSettings
        seed.updatedAtEpochMs = 0
        lastReplicated = seed

        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.replicateSettingsIfChanged() }
        }

        // Si ya había ajustes editados, se reenvían tal cual: puede ser un reloj recién
        // emparejado que nunca los recibió. La marca no se toca, así que no pisa nada más
        // reciente que hubiera en la muñeca.
        if settingsUpdatedAtMs > 0 {
            receiver?.replicate(deviceSettings)
        }
    }

    private func replicateSettingsIfChanged() {
        var current = deviceSettings
        // La comparación ignora la marca de tiempo; si no, escribirla dispararía otra
        // notificación y el ciclo no pararía nunca.
        current.updatedAtEpochMs = 0
        guard current != lastReplicated else { return }
        lastReplicated = current

        // Solo se mueve la marca cuando cambia algo de verdad: es lo que decide quién gana
        // si el mismo ajuste se tocó en el reloj.
        settingsUpdatedAtMs = (Date().timeIntervalSince1970 * 1000).rounded()
        current.updatedAtEpochMs = Int64(settingsUpdatedAtMs)
        receiver?.replicate(current)
    }

    // MARK: Enviar a la liga (deep link)

    /// URL `ligapadel://importar?datos=<JSON>` con el payload del contrato.
    ///
    /// Es el puente con la app de liga (repositorio `padel`): su pantalla de importar
    /// consume exactamente el payload de `POST /v1/padel-sessions`. Sin eventos por
    /// golpeo — la liga no los usa y un deep link no es sitio para decenas de KB.
    func leagueDeepLink(for session: PadelSession) -> URL? {
        // La media del historial viaja con la sesión: es la línea "calidad media" de
        // las gráficas de la liga, y solo este lado la conoce.
        let payload = session.toPayload(
            shareHealth: shareHealth,
            includeEvents: false,
            playerAverageLevel: playerAverageLevel
        )
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8),
              let encoded = json.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        else { return nil }
        return URL(string: "ligapadel://importar?datos=\(encoded)")
    }

    // MARK: Datos de entrenamiento

    // MARK: Mando de tandas

    /// Cómo va la conexión con el reloj para el mando de tandas.
    enum ConexionDelMando {
        /// El reloj contesta al momento: su app está despierta.
        case directa
        /// La orden va encolada y el reloj contestará al despertar. Tarda, pero llega.
        case enCola
        /// No hay reloj emparejado o WatchConnectivity no está disponible.
        case imposible
    }

    /// Último estado que contestó el reloj. Nil = todavía no ha contestado ninguno.
    @Published private(set) var estadoTanda: EstadoDeTanda?
    @Published private(set) var conexionDelMando: ConexionDelMando = .enCola
    /// Hay una orden esperando a que el reloj despierte. Se limpia cuando contesta.
    @Published private(set) var ordenEsperando = false
    /// Por qué la última orden no hizo lo que se le pidió. Sobrevive a los sondeos de
    /// estado a propósito: si se borrara con el siguiente latido, el aviso duraría dos
    /// segundos y el usuario se quedaría con un botón que parece roto.
    @Published private(set) var avisoTanda: String?

    /// Manda una orden al reloj y guarda el estado que devuelva.
    ///
    /// Todas las órdenes pasan por aquí, incluida la de solo preguntar: así el estado que
    /// ve el móvil siempre viene del reloj y nunca de suponer qué habrá pasado tras pulsar
    /// un botón. Si el reloj no contesta, el estado se pone a nil en vez de dejar el
    /// anterior: un contador congelado que parece vivo es peor que un "sin conexión".
    func ordenarTanda(_ accion: AccionDeTanda, etiqueta: ShotType? = nil) {
        guard let receiver else {
            conexionDelMando = .imposible
            return
        }
        let orden = OrdenDeTanda(
            accion: accion,
            etiqueta: etiqueta,
            creadoEpochMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
        // Preguntar el estado no encola: se sondea cada dos segundos y despertar el
        // reloj (o llenarle la cola de preguntas viejas) por eso no compensa. Las
        // órdenes que cambian algo sí esperan a que despierte.
        receiver.enviarOrden(orden, encolarSiDuerme: accion != .estado) { [weak self] envio in
            Task { @MainActor in
                guard let self else { return }
                switch envio {
                case .directa(let estado):
                    self.conexionDelMando = .directa
                    self.ordenEsperando = false
                    self.aplicarEstadoDeTanda(estado, deOrden: accion)
                case .encolada:
                    // El estado anterior se queda: el reloj sigue como estaba, solo que
                    // todavía no lo ha confirmado. Borrarlo dejaría la pantalla en
                    // blanco cada vez que la muñeca se baja, que es siempre.
                    self.conexionDelMando = .enCola
                    self.ordenEsperando = true
                case .dormido:
                    self.conexionDelMando = .enCola
                case .imposible:
                    self.conexionDelMando = .imposible
                }
            }
        }
    }

    /// Aplica un estado del reloj, venga por respuesta directa o encolado más tarde.
    fileprivate func aplicarEstadoDeTanda(_ estado: EstadoDeTanda, deOrden accion: AccionDeTanda?) {
        estadoTanda = estado
        conexionDelMando = .directa
        ordenEsperando = false
        if let motivo = estado.motivo {
            avisoTanda = motivo
        } else if let accion, accion != .estado {
            // Una orden nueva que sí funcionó limpia el aviso de la anterior.
            avisoTanda = nil
        }
        // Lo que el reloj mande llega como fichero y actualiza el contador solo, pero
        // refrescar aquí hace que el número del móvil no se quede viejo si el envío ya
        // había terminado antes de abrir la pantalla.
        refreshTrainingData()
    }

    func refreshTrainingData() {
        let url = Self.trainingDataDestination()
        guard FileManager.default.fileExists(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            trainingDataURL = nil
            trainingDataSizeKB = 0
            recalcularTandas()
            return
        }
        trainingDataURL = url
        trainingDataSizeKB = Int(size / 1024)
        recalcularTandas()
    }

    /// Sube el fichero de tandas al servidor para entrenar el clasificador.
    ///
    /// Explícito y con su aviso al lado: es la única vía por la que sale del móvil señal
    /// cruda de sensores. El resto de la app manda recuentos.
    func subirTandasParaEntrenar() async -> String {
        guard let url = trainingDataURL, let datos = try? Data(contentsOf: url) else {
            return "No hay tandas guardadas todavía."
        }
        guard ComunidadCuenta.read("token") != nil else {
            return "Necesitas cuenta de comunidad para subirlas."
        }
        let kb = datos.count / 1024
        let subida = await ComunidadModel.subirTanda(datos)
        return subida
            ? "Subidos \(kb) KB. Ya se pueden entrenar desde Actions."
            : "No se pudo subir. Revisa la conexión y vuelve a intentarlo."
    }

    func deleteTrainingData() {
        try? FileManager.default.removeItem(at: Self.trainingDataDestination())
        refreshTrainingData()
    }

    private static func trainingDataDestination() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(
            at: base.appendingPathComponent("training"),
            withIntermediateDirectories: true
        )
        return base.appendingPathComponent("training/muestras.jsonl")
    }

    /// Una sesión reenviada por el reloj no debe volver a la cola si ya se subió.
    private func receive(_ session: PadelSession) {
        // La sesión completa sustituye al estado en vivo: mismo partido, más detalle.
        if liveMatch?.sessionId == session.sessionId {
            liveMatch = nil
        }
        guard store.get(session.sessionId) == nil else { return }
        store.upsert(session)
        refresh()
        Task { await syncNow() }
    }

    func syncNow() async {
        guard let config = leagueConfig() else {
            message = "Configura la URL de la liga y el token en Ajustes"
            return
        }
        let report = await syncQueue.sync(
            config: config,
            shareHealth: shareHealth,
            includeEvents: shareShotEvents
        )
        refresh()
        if report.needsAuth {
            message = "El token de la liga ya no vale. Vuelve a conectarla en Ajustes."
        } else if report.uploaded > 0 {
            message = "\(report.uploaded) sesión(es) enviada(s) a la liga"
        }
    }

    func retry(_ sessionId: String) async {
        syncQueue.requeue(sessionId)
        refresh()
        await syncNow()
    }

    func delete(_ sessionId: String) {
        store.delete(sessionId)
        refresh()
    }

    /// Mete en el almacén las sesiones de una copia de seguridad. Las que ya existen
    /// no se tocan: la copia rellena huecos, nunca pisa lo local.
    func restoreSessions(_ restored: [PadelSession]) -> Int {
        var añadidas = 0
        for session in restored where store.get(session.sessionId) == nil {
            store.upsert(session)
            añadidas += 1
        }
        refresh()
        return añadidas
    }

    /// Guarda la revisión del jugador: sus recuentos mandan sobre los del reloj.
    ///
    /// La sesión no vuelve a la cola de subida: la revisión es local (la liga de la
    /// app ya la lee, y es la verdad-terreno para calibrar el detector).
    func applyReview(sessionId: String, correctedCounts: [String: Int]) {
        guard var session = store.get(sessionId) else { return }
        session.review = SessionReview(
            correctedCounts: correctedCounts,
            reviewedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
        store.upsert(session)
        refresh()
    }

    /// Vincula la sesión con un partido de la liga y la devuelve a la cola de subida.
    func linkToMatch(sessionId: String, matchId: String, leagueId: String?) async {
        guard var session = store.get(sessionId) else { return }
        let trimmed = matchId.trimmingCharacters(in: .whitespaces)
        session.matchRef = trimmed.isEmpty
            ? nil
            : MatchRef(
                matchId: trimmed,
                leagueId: leagueId?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            )
        store.upsert(session)
        syncQueue.requeue(sessionId)
        refresh()
        await syncNow()
    }

    func setToken(_ token: String) {
        KeychainTokenStore.write(token)
        // Un token nuevo desbloquea todo lo que se quedó esperando autenticación.
        syncQueue.requeueAllNeedingAuth()
        refresh()
        message = token.isEmpty ? "Token borrado" : "Token guardado"
        objectWillChange.send()
    }

    private func leagueConfig() -> LeagueConfig? {
        guard let token = KeychainTokenStore.read(),
              !leagueBaseURL.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        return LeagueConfig(baseURL: leagueBaseURL.trimmingCharacters(in: .whitespaces), token: token)
    }

    private static func sessionsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("sessions", isDirectory: true)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
