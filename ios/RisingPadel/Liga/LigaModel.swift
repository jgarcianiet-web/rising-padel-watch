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

    private func previos(_ campo: (LigaMatch) -> String) -> [String] {
        var vistos = Set<String>()
        let unicos = state.matches.map(campo)
            .filter { !$0.isEmpty && vistos.insert($0).inserted }
        return Array(unicos.suffix(6).reversed())
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
        message = "Objetivos guardados"
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

        // Nivel por golpe con el catálogo de la liga; las dos voleas se funden en una.
        var golpes: [LigaGolpeSesion] = []
        var voleas: [Double] = []
        for (type, grade) in level.byShotType {
            if type == .forehandVolley || type == .backhandVolley {
                voleas.append(Double(grade))
            } else if let name = Self.catalogo[type] {
                golpes.append(LigaGolpeSesion(nombre: name, nota: round1(Double(grade))))
            }
        }
        if !voleas.isEmpty {
            golpes.append(LigaGolpeSesion(nombre: "Volea", nota: round1(voleas.reduce(0, +) / Double(voleas.count))))
        }

        var volumen: [LigaGolpeVolumen] = []
        var voleaCount = 0
        for (type, count) in session.shotsByType {
            if type == .forehandVolley || type == .backhandVolley {
                voleaCount += count
            } else if let name = Self.catalogo[type], count > 0 {
                volumen.append(LigaGolpeVolumen(nombre: name, cantidad: count))
            }
        }
        if voleaCount > 0 {
            volumen.append(LigaGolpeVolumen(nombre: "Volea", cantidad: voleaCount))
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
                shotsByType: session.shotsByType,
                totalShots: session.totalShots
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
            tipo: score != nil ? "competitivo" : "amistoso",
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
            totalGolpes: session.totalShots,
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

    // MARK: Persistencia

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(LigaState.self, from: data) else { return }
        state = stored
    }

    private func save() {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: Utilidades

    /// Tipos del reloj → catálogo de la liga (las voleas se tratan aparte).
    private static let catalogo: [ShotType: String] = [
        .forehand: "Derecha",
        .backhand: "Revés",
        .bandeja: "Bandeja",
        .vibora: "Víbora",
        .smash: "Remate",
        .serve: "Saque",
    ]

    /// Un partido interrumpido se decide por sets ganados, como haría el jugador.
    private static func resultado(_ score: MatchScore?) -> String {
        guard let score else { return "derrota" }
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
