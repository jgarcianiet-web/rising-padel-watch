import Foundation
import PadelCore
import SwiftUI

/// Estado de la Liga Personal dentro de la app.
///
/// Persistencia: un único JSON con el `LigaState` entero, el mismo shape que la copia de
/// seguridad de la app Expo. Guardar y exportar son la misma operación — no puede haber
/// una diferencia entre "lo que hay" y "lo que sale en el backup".
@MainActor
final class LigaModel: ObservableObject {

    @Published private(set) var state = LigaState()
    @Published var message: String?

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = fileURL ?? base.appendingPathComponent("liga/estado.json")
        load()
        seedObjetivos()
        // Al arrancar también: si la liga se importó de un backup, el reloj tiene que
        // enterarse de los objetivos que vinieron con él.
        mirrorObjectivesForWatch()
    }

    var matches: [LigaMatch] {
        // La más nueva primero, como el historial de sesiones.
        state.matches.sorted { $0.fecha > $1.fecha }
    }

    /// Los objetivos por defecto de la web-app original: sin ellos, la ficha de un
    /// partido enseñaría checks sin texto. Un backup con objetivos propios los pisa.
    private func seedObjetivos() {
        if state.objetivos.isEmpty {
            state.objetivos = LigaCatalogos.defaultObjetivos
        }
    }

    /// Clubes ya usados, para rellenar con un toque (los 6 últimos, como en la Expo).
    var clubesPrevios: [String] { previos(\.club) }
    var companerosPrevios: [String] { previos(\.companero) }
    var rivalesPrevios: [String] { previos { $0.rivales ?? "" } }

    private func previos(_ campo: (LigaMatch) -> String) -> [String] {
        var vistos = Set<String>()
        let unicos = state.matches.map(campo)
            .filter { !$0.isEmpty && vistos.insert($0).inserted }
        return Array(unicos.suffix(6).reversed())
    }

    // MARK: Temporadas

    /// La temporada en curso, o nil si la liga funciona sin temporadas (como siempre).
    var temporadaActual: LigaTemporada? {
        state.temporadas.last(where: \.enCurso)
    }

    /// Los partidos de una temporada, por su rango de fechas.
    func matches(de temporada: LigaTemporada) -> [LigaMatch] {
        state.matches.filter { temporada.contiene($0) }
    }

    /// Los partidos que cuentan hoy: los de la temporada en curso, o todos si no hay
    /// temporadas — la liga de siempre es una única temporada implícita.
    var matchesTemporadaActual: [LigaMatch] {
        guard let actual = temporadaActual else { return state.matches }
        return matches(de: actual)
    }

    /// Cierra la temporada en curso (si la hay) y abre la siguiente hoy.
    ///
    /// El cierre es la víspera del arranque nuevo: dos temporadas no pueden solaparse
    /// ni dejar días huérfanos entre medias, o un partido caería en dos o en ninguna.
    /// - Parameter nombre: cómo la llama el jugador («Reto hacia nivel 4»). En blanco
    ///   sale «Temporada N», que es un nombre de relleno y no una elección: una meta de
    ///   nueve meses con nombre propio se persigue mejor que una numerada.
    func startTemporada(nombre: String = "", objetivoPartidos: Int?) {
        let hoy = LigaFechas.hoy()
        if let index = state.temporadas.lastIndex(where: \.enCurso) {
            state.temporadas[index].fechaFin = Self.vispera(de: hoy) ?? hoy
        }
        let numero = state.temporadas.count + 1
        let limpio = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        let comoSeLlama = limpio.isEmpty ? "Temporada \(numero)" : limpio
        state.temporadas.append(LigaTemporada(
            id: Int64(Date().timeIntervalSince1970 * 1000),
            nombre: comoSeLlama,
            fechaInicio: hoy,
            objetivoPartidos: objetivoPartidos
        ))
        save()
        message = "\(comoSeLlama) en marcha"
    }

    /// Cambia el nombre de la temporada en curso.
    ///
    /// Se puede renombrar en cualquier momento y a propósito: el nombre es del jugador y
    /// no un identificador — la temporada se identifica por su `id` y por sus fechas, así
    /// que cambiarlo no mueve ni un partido de sitio. Un nombre en blanco no se guarda:
    /// una temporada sin nombre no se puede nombrar en ninguna pantalla.
    func setNombreDeTemporada(_ nombre: String) {
        guard let index = state.temporadas.lastIndex(where: \.enCurso) else { return }
        let limpio = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty, limpio != state.temporadas[index].nombre else { return }
        state.temporadas[index].nombre = limpio
        save()
    }

    /// Cambia las fechas de la temporada en curso.
    ///
    /// La de inicio era la del día que se pulsó el botón, que no siempre es la buena: la
    /// temporada empezó en septiembre aunque estrenaras la app en noviembre, y con la
    /// fecha mal los partidos de septiembre y octubre se quedan fuera.
    ///
    /// El fin es el **previsto**: no cierra la temporada, solo da el plazo. Cerrarla es
    /// empezar la siguiente, y eso sigue siendo una decisión explícita.
    func setFechasDeTemporada(inicio: String, finPrevisto: String) {
        guard let index = state.temporadas.lastIndex(where: \.enCurso) else { return }
        if !inicio.isEmpty { state.temporadas[index].fechaInicio = inicio }
        state.temporadas[index].fechaFinPrevista = finPrevisto
        save()
    }

    /// Cambia la meta de partidos de la temporada en curso.
    func setObjetivoPartidos(_ objetivo: Int?) {
        guard let index = state.temporadas.lastIndex(where: \.enCurso) else { return }
        state.temporadas[index].objetivoPartidos = objetivo
        save()
    }

    /// Reemplaza las metas por golpe de una temporada.
    ///
    /// Va por id y no por "la que esté en curso" a propósito: la pantalla de objetivos
    /// enseña la temporada que enseña, y si alguien cierra una temporada desde otro
    /// sitio mientras tiene el editor abierto, guardar no puede acabar escribiendo las
    /// metas en la temporada equivocada.
    func actualizarObjetivosDeGolpe(_ objetivos: [ObjetivoDeGolpe], enTemporada id: Int64) {
        guard let index = state.temporadas.firstIndex(where: { $0.id == id }) else { return }
        state.temporadas[index].objetivosDeGolpe = objetivos
        save()
    }

    /// El contexto de temporadas para el prompt del entrenador, o nil sin temporadas.
    ///
    /// Dos cosas: dónde está la temporada en curso (meta de partidos incluida) y el
    /// resumen numérico de las anteriores, para que la comparación del modelo se apoye
    /// en números y no en memoria.
    var contextoTemporadaParaEntrenador: String? {
        guard let actual = temporadaActual else { return nil }
        let jugados = matches(de: actual).count
        var lineas = ["TEMPORADA EN CURSO: \(actual.nombre) (desde \(actual.fechaInicio))."]
        if let objetivo = actual.objetivoPartidos {
            lineas.append("Meta de volumen: \(objetivo) partidos; lleva \(jugados).")
        } else {
            lineas.append("Lleva \(jugados) partidos.")
        }
        lineas.append("El REGISTRO de abajo contiene SOLO los partidos de esta temporada: tu análisis es de la temporada.")

        let anteriores = state.temporadas.filter { !$0.enCurso }
        if !anteriores.isEmpty {
            lineas.append("TEMPORADAS ANTERIORES (compara con ellas el rumbo de la actual, con números):")
            for temporada in anteriores {
                let ms = matches(de: temporada)
                guard !ms.isEmpty else { continue }
                let bien = ms.filter(\.bienJugado).count * 100 / ms.count
                let niveles = ms.compactMap(LigaMetrics.nivelDeSesion)
                let nivel = niveles.isEmpty
                    ? "sin nivel"
                    : String(format: "nivel de sesión medio %.1f", niveles.reduce(0, +) / Double(niveles.count))
                lineas.append(
                    "- \(temporada.nombre) (\(temporada.fechaInicio) a \(temporada.fechaFin)): "
                        + "\(ms.count) partidos, \(LigaMetrics.pctVictorias(ms))% victorias, "
                        + "\(bien)% bien jugados, \(nivel)."
                )
            }
        }
        // El cara a cara alimenta consejos concretos: "contra Juan pierdes el 70%,
        // y contra él tu revés cae" es mejor consejo que uno genérico.
        let rivales = LigaMetrics.caraACara(matches(de: actual)).prefix(4)
        if !rivales.isEmpty {
            lineas.append("CARA A CARA de la temporada (solo si es relevante, úsalo):")
            for rival in rivales {
                lineas.append(
                    "- contra \(rival.nombre): \(rival.victorias) de \(rival.partidos) ganados"
                )
            }
        }
        let parejas = LigaMetrics.conPareja(matches(de: actual)).prefix(2)
        for pareja in parejas {
            lineas.append(
                "- con \(pareja.nombre) de pareja: \(pareja.victorias) de \(pareja.partidos) ganados"
            )
        }
        return lineas.joined(separator: "\n")
    }

    /// El día anterior a una fecha yyyy-mm-dd, para cerrar la temporada saliente.
    private static func vispera(de iso: String) -> String? {
        guard let fecha = LigaFechas.fecha(iso),
              let anterior = Calendar.current.date(byAdding: .day, value: -1, to: fecha)
        else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: anterior)
    }

    // MARK: Perfil y objetivos

    func savePerfil(_ perfil: LigaPerfil) {
        state.perfil = perfil
        save()
        message = "Perfil guardado"
    }

    func saveObjetivos(_ objetivos: [String]) {
        state.objetivos = objetivos
        save()
        mirrorObjectivesForWatch()
        message = "Objetivos guardados"
    }

    /// Deja los objetivos en `UserDefaults` para que `AppModel` los replique al reloj.
    ///
    /// Es el camino corto a propósito: la liga no habla con el reloj —habla el AppModel,
    /// que ya observa UserDefaults para replicar—, así que escribir aquí dispara el
    /// envío sin acoplar los dos modelos.
    private func mirrorObjectivesForWatch() {
        UserDefaults.standard.set(
            state.objetivos.joined(separator: "\n"), forKey: "matchObjectives"
        )
    }

    // MARK: Partidos

    func upsert(_ match: LigaMatch) {
        if let index = state.matches.firstIndex(where: { $0.id == match.id }) {
            state.matches[index] = match
        } else {
            state.matches.append(match)
        }
        save()
    }

    func delete(_ id: Int64) {
        state.matches.removeAll { $0.id == id }
        save()
    }

    /// true si esta sesión ya se guardó como partido (el id viene de su fecha de inicio).
    func hasMatch(for session: PadelSession) -> Bool {
        state.matches.contains { $0.id == session.startedAtEpochMs }
    }

    /// Convierte una sesión del reloj en un partido de la liga.
    ///
    /// Es el mismo mapeo que hacía `parseSesion` en la app Expo cuando la sesión llegaba
    /// por deep link — voleas unificadas, catálogo de nombres de la liga, curva del reloj
    /// en los campos de la Band — pero sin salir de la app: la liga vive aquí.
    func saveMatch(from session: PadelSession, playerAverage: Float?) {
        let analytics = SessionAnalytics()
        let level = session.level

        // Nivel y volumen por golpe, con el repertorio que ve el jugador: las dos
        // voleas se funden en una y la víbora se pliega dentro de la bandeja. Mismo
        // mapeo que hace `LigaMapper` en el core Kotlin. Ver `GolpeVisible`.
        let golpes = GolpeVisible.agruparNotas(level.byShotType).map { visible, nota in
            LigaGolpeSesion(nombre: visible.etiqueta, nota: round1(Double(nota)))
        }

        // Los recuentos con la revisión del jugador aplicada: si dijo que fueron 12
        // bandejas, la liga y los objetivos ven 12, contara lo que contara el reloj.
        let volumen = GolpeVisible.agruparRecuentos(session.effectiveShotsByType).map {
            visible, cantidad in
            LigaGolpeVolumen(nombre: visible.etiqueta, cantidad: cantidad)
        }

        let progression = analytics.levelProgression(
            session.shots, durationMs: session.durationSeconds * 1000
        )
        let frequency = analytics.shotFrequency(
            session.shots,
            durationMs: session.durationSeconds * 1000,
            intervalMs: SessionAnalytics.interval10MinMs
        )

        // Los objetivos que el reloj puede medir se marcan solos: "hacer 15 bandejas"
        // se comprueba contra el recuento real. Los no medibles quedan en false y se
        // marcan a mano al editar, como siempre.
        var objetivosMedidos = 0
        let checks = state.objetivos.map { objetivo -> Bool in
            guard let medida = ObjectiveEvaluator.evaluate(
                objetivo,
                shotsByType: session.effectiveShotsByType,
                totalShots: session.effectiveTotalShots
            ) else { return false }
            objetivosMedidos += 1
            return medida.met
        }

        let score = session.score
        let match = LigaMatch(
            // El id es la fecha de inicio de la sesión: guardar dos veces la misma
            // sesión actualiza el partido en vez de duplicarlo.
            id: session.startedAtEpochMs,
            fecha: Self.fechaLocal(session.startedAtEpochMs),
            // El tipo lo da haber sido partido, no haber llevado el marcador: un
            // partido sin anotar sigue siendo competitivo.
            tipo: session.cuentaComoPartido ? "competitivo" : "amistoso",
            resultado: Self.resultado(score),
            sets: score.map { $0.allSets.map { "\($0.us)-\($0.them)" }.joined(separator: ", ") } ?? "",
            marcador: score.map {
                $0.allSets.map { LigaSetMarcador(yo: "\($0.us)", rival: "\($0.them)") }
            },
            nivelBand: level.gradedShots > 0 && level.reliable ? round1(Double(level.overall)) : nil,
            golpesSesion: golpes.isEmpty ? nil : golpes.sorted { $0.nota > $1.nota },
            objetivos: checks,
            bandInicio: progression.first.map { round1(Double($0.level)) },
            bandFin: progression.last.map { round1(Double($0.level)) },
            bandMediaJugador: playerAverage.map { round1(Double($0)) },
            golpesVolumen: volumen.isEmpty ? nil : volumen.sorted { $0.cantidad > $1.cantidad },
            totalGolpes: session.effectiveTotalShots,
            salud: session.health.isEmpty ? nil : LigaSaludPartido(
                duracionMin: Int((Double(session.durationSeconds) / 60).rounded()),
                pulsoMedio: session.health.heartRate?.meanBpm,
                pulsoMax: session.health.heartRate?.maxBpm,
                calorias: session.health.activeEnergyKcal.map { Int($0.rounded()) }
            ),
            bandPuntos: progression.count >= 2 ? progression.map {
                LigaPuntoProgreso(minuto: Double($0.offsetMs) / 60_000, nivel: round1(Double($0.level)))
            } : nil,
            frecuenciaGolpeo: frequency.isEmpty ? nil : LigaFrecuenciaGolpeo(
                intervaloMin: 10, cuentas: frequency.map(\.count)
            )
        )
        upsert(match)
        message = objetivosMedidos > 0
            ? "Partido guardado (\(objetivosMedidos) de \(checks.count) objetivos medidos por el reloj)"
            : "Partido guardado en la liga"
    }

    // MARK: Entrenador

    /// Guarda un análisis nuevo del entrenador: pasa a ser el vigente y entra en el
    /// historial, la misma semántica que en la app Expo (y el mismo shape en el backup).
    func applyAnalisis(_ analisis: LigaAnalisis) {
        state.analisis = analisis
        state.analisisHistorial.append(analisis)
        save()
    }

    /// Adopta los 3 objetivos que prescribe el entrenador como los objetivos por partido
    /// de la liga.
    func adoptObjetivos(_ objetivos: [String]) {
        guard !objetivos.isEmpty else { return }
        state.objetivos = objetivos
        save()
        mirrorObjectivesForWatch()
        message = "Objetivos del entrenador adoptados"
    }

    // MARK: Copia de seguridad

    /// Importa un backup de la app Expo (o de la web-app original). Sustituye el estado
    /// entero: es la semántica del import de la liga, no una fusión.
    func importBackup(_ data: Data) {
        do {
            let imported = try JSONDecoder().decode(LigaState.self, from: data)
            state = imported
            seedObjetivos()
            mirrorObjectivesForWatch()
            save()
            message = "Liga importada: \(imported.matches.count) partidos"
        } catch {
            message = "Ese fichero no es una copia de la liga"
        }
    }

    /// La liga como CSV, para mirarla en una hoja de cálculo. Solo lectura: el camino
    /// de vuelta sigue siendo el backup JSON.
    func exportCSV() -> URL? {
        var lineas = ["fecha;tipo;resultado;sets;posicion;club;companero;nivelPlaytomic;nivelSesion;totalGolpes;duracionMin;pulsoMedio;calorias;bienJugado;nota"]
        for m in state.matches.sorted(by: { $0.fecha < $1.fecha }) {
            // En sentencias separadas: el literal entero superaba el presupuesto del
            // type-checker de Swift ("unable to type-check in reasonable time").
            var campos: [String] = [m.fecha, m.tipo, m.resultado, m.sets, m.posicion]
            campos.append(campo(m.club))
            campos.append(campo(m.companero))
            campos.append(m.nivel.map { String(format: "%.2f", $0) } ?? "")
            campos.append(LigaMetrics.nivelDeSesion(m).map { String(format: "%.1f", $0) } ?? "")
            campos.append(m.totalGolpes.map { String($0) } ?? "")
            campos.append(m.salud.map { String($0.duracionMin) } ?? "")
            campos.append((m.salud?.pulsoMedio).map { String($0) } ?? "")
            campos.append((m.salud?.calorias).map { String($0) } ?? "")
            campos.append(m.bienJugado ? "si" : "no")
            campos.append(campo(m.nota))
            lineas.append(campos.joined(separator: ";"))
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("liga-padel.csv")
        guard let data = lineas.joined(separator: "\n").data(using: .utf8),
              (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    /// Punto y coma como separador (la convención de Excel en español) ⇒ los campos
    /// libres no pueden llevarlo ni saltos de línea.
    private func campo(_ texto: String) -> String {
        texto.replacingOccurrences(of: ";", with: ",")
            .replacingOccurrences(of: "\n", with: " ")
    }

    /// El backup es el estado tal cual, igual que en la app Expo: reimportable allí.
    func exportBackup() -> URL? {
        guard let data = try? JSONEncoder().encode(state) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("liga-padel-backup.json")
        try? data.write(to: url)
        return url
    }

    /// El estado de la liga como JSON, para la copia de seguridad automática.
    func backupData() -> Data? {
        try? JSONEncoder().encode(state)
    }

    /// Trae lo que haya en la copia de seguridad del servidor **sumando, nunca pisando**.
    ///
    /// ## El fallo que arregla
    ///
    /// Antes esto hacía `state = stored`, y la app llamaba a restaurar en cada arranque
    /// mientras no hubiera sesiones del reloj en el móvil. Resultado: apuntabas un
    /// partido a mano, lo veías guardado, cerrabas la app, y al abrirla otra vez la
    /// copia del servidor —que no lo tenía, porque solo se subía al llegar una sesión
    /// nueva del reloj— borraba el partido. Parecía que el alta manual no guardaba. Lo
    /// que pasaba es que guardaba y luego se lo llevaba por delante la restauración.
    ///
    /// ## La regla
    ///
    /// **Una restauración no puede destruir nada de este teléfono.** Los partidos se
    /// funden por id y, si el mismo id está en los dos sitios, gana el de aquí: es el
    /// que el jugador acaba de tocar. Lo demás —temporadas, perfil, análisis— solo se
    /// copia si aquí está vacío, que es el caso para el que existe la copia: una
    /// reinstalación.
    ///
    /// - Returns: cuántos partidos ha traído la copia que aquí no estaban.
    @discardableResult
    func restoreBackup(_ data: Data) -> Int {
        guard let copia = try? JSONDecoder().decode(LigaState.self, from: data) else { return 0 }

        // Reinstalación de verdad: aquí no hay liga, así que la copia ES la liga.
        if state.matches.isEmpty, state.temporadas.isEmpty {
            state = copia
            seedObjetivos()
            save()
            mirrorObjectivesForWatch()
            return copia.matches.count
        }

        let conocidos = Set(state.matches.map(\.id))
        let nuevos = copia.matches.filter { !conocidos.contains($0.id) }
        if state.temporadas.isEmpty { state.temporadas = copia.temporadas }
        if state.perfil == LigaPerfil() { state.perfil = copia.perfil }
        if state.analisis == nil { state.analisis = copia.analisis }
        guard !nuevos.isEmpty else {
            mirrorObjectivesForWatch()
            return 0
        }
        state.matches.append(contentsOf: nuevos)
        save()
        mirrorObjectivesForWatch()
        return nuevos.count
    }

    // MARK: Persistencia

    /// Sube uno en cada guardado con éxito. Es lo que mira la raíz de la app para subir
    /// la copia al servidor: sin esto la copia solo se renovaba cuando llegaba una
    /// sesión del reloj, así que un partido apuntado a mano no salía nunca del móvil.
    @Published private(set) var revision = 0

    /// El fichero existe pero no se pudo leer. Mientras esté puesto **no se escribe
    /// encima**: un JSON que no entendemos puede ser el historial entero del jugador, y
    /// sobrescribirlo con el estado vacío que quedó en memoria es la forma más rápida de
    /// convertir un problema de lectura en una pérdida de datos definitiva.
    private var lecturaFallida = false

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let stored = try? JSONDecoder().decode(LigaState.self, from: data) else {
            lecturaFallida = true
            message = "No se ha podido leer tu liga guardada. No se va a escribir encima: "
                + "exporta una copia desde el menú antes de tocar nada."
            return
        }
        state = stored
    }

    private func save() {
        guard !lecturaFallida else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(state)
            try data.write(to: fileURL, options: .atomic)
            revision &+= 1
        } catch {
            // Un guardado que falla en silencio es cómo se pierde un historial sin que
            // nadie se entere: lo que está en pantalla parece guardado y no lo está.
            message = "No se ha podido guardar la liga en este móvil."
        }
    }

    // MARK: Utilidades

    /// Un partido interrumpido se decide por sets ganados, como haría el jugador.
    ///
    /// Sin marcador **no hay resultado**, y decir "derrota" era mentira: un entreno
    /// suelto guardado como partido llenaba la racha de derrotas que nadie había perdido
    /// y bajaba el porcentaje de victorias por haber entrenado.
    private static func resultado(_ score: MatchScore?) -> String {
        guard let score else { return ResultadoDePartido.sinResultado }
        if score.isFinished, let winner = score.winner {
            return winner == .us ? "victoria" : "derrota"
        }
        let us = score.gamesWon(.us)
        let them = score.gamesWon(.them)
        if us == them { return "empate" }
        return us > them ? "victoria" : "derrota"
    }

    /// yyyy-mm-dd en hora local, el formato de fecha de la liga.
    private static func fechaLocal(_ epochMs: Int64) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: Double(epochMs) / 1000))
    }

    private func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }
}
