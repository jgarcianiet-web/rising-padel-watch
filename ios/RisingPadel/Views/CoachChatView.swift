import PadelCore
import SwiftUI

/// **RISING AI — tu entrenador personal.** La pantalla de conversación del §24.
///
/// Hasta ahora el entrenador era de un solo tiro: pulsabas "analizar" y salía un
/// informe. Eso responde a "¿qué tal jugué?", pero no a "¿y entonces qué entreno el
/// martes?", que es la pregunta que de verdad hace un jugador. El chat existe para esa
/// segunda parte.
///
/// Dos decisiones de diseño que no son cosméticas:
///
/// **El contexto se manda una vez, en el primer turno, y no en cada mensaje.** Los
/// hechos del reloj y el registro de partidos ocupan bastante; repetirlos en cada
/// pregunta multiplicaría el coste de cada conversación sin añadir nada, porque el
/// modelo ya los tiene en el hilo.
///
/// **El hilo no se guarda entre sesiones de la app.** Es deliberado: una conversación
/// vieja arrastra datos de partidos que ya no son los últimos, y el entrenador acabaría
/// razonando sobre una foto caducada. Cada vez que se abre, parte de los datos de hoy.
struct CoachChatView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var liga: LigaModel

    @State private var turnos: [CoachService.Turno] = []
    @State private var borrador = ""
    @State private var pensando = false
    @State private var aviso: String?
    /// El contexto ya viajó en el primer turno; los siguientes van desnudos.
    @State private var contextoEnviado = false

    /// Las preguntas del documento, que además enseñan de qué se le puede hablar. Un
    /// chat vacío con un cursor parpadeando no le dice a nadie qué preguntar.
    private let sugerencias = [
        "¿Qué tengo que entrenar?",
        "¿Por qué no mejoro?",
        "¿He mejorado mi bandeja?",
        "¿Qué hice peor hoy?",
        "¿Qué objetivos tengo para el próximo partido?",
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                conversacion
                if let aviso {
                    Text(aviso)
                        .font(.caption)
                        .foregroundStyle(T.rojo)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }
                barraDeEnvio
            }
            .background(T.fondo)
            .navigationTitle("Rising AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !turnos.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Nueva") { reiniciar() }
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    // MARK: Conversación

    private var conversacion: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if turnos.isEmpty { bienvenida }
                    ForEach(Array(turnos.enumerated()), id: \.offset) { indice, turno in
                        Burbuja(turno: turno).id(indice)
                    }
                    if pensando {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Pensando…")
                                .font(.subheadline)
                                .foregroundStyle(T.tintaSuave)
                        }
                        .id("pensando")
                    }
                }
                .padding(16)
            }
            .onChange(of: turnos.count) {
                withAnimation { scroll.scrollTo(turnos.count - 1, anchor: .bottom) }
            }
        }
    }

    private var bienvenida: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TU ENTRENADOR PERSONAL")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(T.tintaSuave)

            Text("Conozco tus partidos, lo que mide tu reloj y tus objetivos. Pregúntame.")
                .font(.body)
                .foregroundStyle(T.tinta)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(sugerencias, id: \.self) { pregunta in
                    Button {
                        enviar(pregunta)
                    } label: {
                        HStack {
                            Text(pregunta)
                                .font(.subheadline)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(T.tintaSuave)
                        }
                        .padding(.vertical, 11)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(T.superficie, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12).stroke(T.borde, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(T.tinta)
                }
            }
            .padding(.top, 4)
        }
    }

    private struct Burbuja: View {
        let turno: CoachService.Turno

        private var esMio: Bool { turno.role == "user" }

        var body: some View {
            HStack {
                if esMio { Spacer(minLength: 40) }
                Text(turno.content)
                    .font(.subheadline)
                    .foregroundStyle(esMio ? .white : T.tinta)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 13)
                    .background(
                        esMio ? T.pista : T.superficie,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(esMio ? .clear : T.borde, lineWidth: 1)
                    )
                    .textSelection(.enabled)
                if !esMio { Spacer(minLength: 40) }
            }
        }
    }

    // MARK: Enviar

    private var barraDeEnvio: some View {
        HStack(spacing: 10) {
            TextField("Pregunta a tu entrenador…", text: $borrador, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(T.superficie, in: Capsule())
                .overlay(Capsule().stroke(T.borde, lineWidth: 1))
                .onSubmit { enviar(borrador) }

            Button {
                enviar(borrador)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(puedeEnviar ? T.pista : T.tintaSuave, in: Circle())
            }
            .disabled(!puedeEnviar)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(T.fondo)
    }

    private var puedeEnviar: Bool {
        !pensando && !borrador.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func enviar(_ texto: String) {
        let pregunta = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pregunta.isEmpty, !pensando else { return }

        borrador = ""
        aviso = nil
        // El contexto solo viaja pegado a la PRIMERA pregunta. A partir de ahí el hilo
        // ya lo lleva y repetirlo sería pagar dos veces por lo mismo.
        let contenido = contextoEnviado ? pregunta : "\(contexto())\n\n\(pregunta)"
        contextoEnviado = true
        // En pantalla se enseña la pregunta a secas; el contexto es fontanería y ver un
        // muro de datos propios en tu propia burbuja es desconcertante.
        turnos.append(.init(role: "user", content: pregunta))

        var paraElModelo = turnos
        paraElModelo[paraElModelo.count - 1] = .init(role: "user", content: contenido)

        pensando = true
        Task {
            do {
                let respuesta = try await CoachService().conversar(paraElModelo, maxTokens: 1_500)
                await MainActor.run {
                    turnos.append(.init(role: "assistant", content: respuesta))
                    pensando = false
                }
            } catch {
                await MainActor.run {
                    aviso = (error as? CoachError)?.errorDescription
                        ?? "No se pudo hablar con el entrenador."
                    // La pregunta se queda en pantalla pero se saca del hilo: si no, el
                    // siguiente intento mandaría dos preguntas del usuario seguidas y la
                    // API rechaza la conversación entera.
                    turnos.removeLast()
                    pensando = false
                }
            }
        }
    }

    private func reiniciar() {
        turnos = []
        contextoEnviado = false
        aviso = nil
    }

    // MARK: El contexto que ve el entrenador

    /// Los datos del jugador, en texto plano. Son los mismos hechos que usa el análisis
    /// post-partido: medidos por el reloj o apuntados por él, nunca estimados aquí.
    private func contexto() -> String {
        var lineas = ["DATOS DEL JUGADOR (no inventes nada que no esté aquí):"]

        let perfil = liga.state.perfil
        if !perfil.nivelPlaytomic.isEmpty || !perfil.nivelObjetivo.isEmpty {
            lineas.append(
                "Nivel declarado: \(perfil.nivelPlaytomic.isEmpty ? "sin decir" : perfil.nivelPlaytomic)."
                    + " Meta: \(perfil.nivelObjetivo.isEmpty ? "sin fijar" : perfil.nivelObjetivo)."
            )
        }

        let partidos = liga.state.matches.sorted { $0.fecha > $1.fecha }.prefix(10)
        if !partidos.isEmpty {
            lineas.append("\nÚltimos partidos:")
            for partido in partidos {
                var fila = "· \(partido.fecha) — \(partido.resultado)"
                if let nivel = partido.nivel { fila += String(format: ", nivel %.2f", nivel) }
                let golpes = (partido.golpesSesion ?? [])
                    .map { String(format: "%@ %.1f", $0.nombre, $0.nota) }
                    .joined(separator: ", ")
                if !golpes.isEmpty { fila += " · \(golpes)" }
                lineas.append(fila)
            }
        }

        if let temporada = liga.temporadaActual, !temporada.objetivosDeGolpe.isEmpty {
            lineas.append("\nObjetivos de la temporada «\(temporada.nombre)»:")
            for progreso in ProgresoDeGolpes.deTemporada(temporada, partidos: liga.state.matches) {
                let actual = progreso.notaActual.map { String(format: "%.2f", $0) } ?? "sin datos"
                lineas.append(
                    "· \(progreso.objetivo.golpe): "
                        + String(format: "%.1f", progreso.objetivo.notaInicial)
                        + " → " + String(format: "%.1f", progreso.objetivo.notaObjetivo)
                        + " (ahora \(actual), \(progreso.porcentaje) % del camino)"
                )
            }
        }

        // Los hechos que solo sabe el reloj: los mismos que alimentan el análisis.
        if let hechos = CoachService.hechosReloj(sessions: model.sessions, limit: 3),
           !hechos.isEmpty {
            lineas.append("\nLo que midió el reloj en las últimas sesiones:")
            lineas.append(hechos)
        }

        return lineas.joined(separator: "\n")
    }
}
