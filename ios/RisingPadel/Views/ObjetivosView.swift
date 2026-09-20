import PadelCore
import SwiftUI

/// **MIS OBJETIVOS** (§19, §20 y §21 del documento de producto).
///
/// La temporada con su meta global y, debajo, las metas por golpe: "Bandeja 2,6 → 3,5",
/// cada una con lo que llevas recorrido. Es la pantalla que contesta a la segunda de
/// las tres preguntas de la app —*qué estoy mejorando*— y la que convierte un historial
/// de partidos en un plan.
struct ObjetivosView: View {
    @EnvironmentObject private var liga: LigaModel

    /// El plan del jugador: poner metas por golpe es de Pro (ver `Gating`).
    @StateObject private var tienda = TiendaModel.compartida

    @State private var editando: ObjetivoDeGolpe?
    @State private var creando = false
    @State private var vendiendo = false
    /// La temporada se editaba solo desde Partidos → Liga → ⋯ → Objetivos y perfil, tres
    /// niveles dentro de otra pestaña, y esta pantalla se limitaba a mandarte allí con
    /// una frase. Una pantalla que enseña un dato y no deja tocarlo es un callejón.
    @State private var editandoTemporada = false

    /// **La pantalla se ve entera aunque no haya Pro; lo que pide Pro es CREAR.** Quien
    /// ya tenga objetivos puestos (de una prueba, de una suscripción que caducó) los
    /// sigue viendo y los sigue midiendo: esconderle sus propios datos no vende nada y
    /// se parece demasiado a un secuestro. Lo que se cierra es la puerta de entrada.
    private var puedeCrear: Bool {
        Gating.disponible(.objetivosDeGolpe, plan: tienda.plan)
    }

    private var temporada: LigaTemporada? { liga.temporadaActual }

    private var progresos: [ProgresoDeObjetivo] {
        guard let temporada else { return [] }
        return ProgresoDeGolpes.deTemporada(temporada, partidos: liga.state.matches)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let temporada {
                        cabecera(temporada)
                        objetivoGlobal
                        objetivosTecnicos
                    } else {
                        sinTemporada
                    }
                }
                .padding(16)
            }
            .background(T.fondo)
            .navigationTitle("Mis objetivos")
            .toolbar {
                if temporada != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { nuevoObjetivo() } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Nuevo objetivo de golpe")
                    }
                }
            }
            .sheet(isPresented: $creando) {
                EditorDeObjetivo(objetivo: nil) { guardar($0) }
            }
            .sheet(isPresented: $vendiendo) {
                PaywallView(destacando: .objetivosDeGolpe, enHoja: true)
            }
            .sheet(item: $editando) { objetivo in
                EditorDeObjetivo(objetivo: objetivo) { guardar($0) }
            }
            .sheet(isPresented: $editandoTemporada) {
                LigaAjustesView(liga: liga).environmentObject(liga)
            }
        }
    }

    // MARK: Cabecera de la temporada

    private func cabecera(_ temporada: LigaTemporada) -> some View {
        Button { editandoTemporada = true } label: {
            PadelCard {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("TEMPORADA")
                        Text(temporada.nombre.isEmpty ? "Sin nombre" : temporada.nombre.uppercased())
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(T.tinta)
                            .multilineTextAlignment(.leading)
                        if !temporada.fechaInicio.isEmpty {
                            Text("\(temporada.fechaInicio) → \(temporada.fechaDeCierre.isEmpty ? "sin fecha de fin" : temporada.fechaDeCierre)")
                                .font(.caption)
                                .foregroundStyle(T.tintaSuave)
                        }
                        Text("Toca para cambiar el nombre, las fechas o la meta")
                            .font(.caption2)
                            .foregroundStyle(T.tintaSuave)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(T.pista)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Objetivo global

    @ViewBuilder
    private var objetivoGlobal: some View {
        let perfil = liga.state.perfil
        if !perfil.nivelObjetivo.isEmpty,
           let porcentaje = LigaMetrics.progresoMeta(liga.state.matches, perfil: perfil) {
            PadelCard {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("OBJETIVO PRINCIPAL")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(perfil.nivelPlaytomic.isEmpty ? "—" : perfil.nivelPlaytomic)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Image(systemName: "arrow.right").font(.caption.bold())
                            .foregroundStyle(T.tintaSuave)
                        Text(perfil.nivelObjetivo)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(T.pista)
                    }
                    PadelBar(
                        label: "Progreso",
                        value: "\(porcentaje) %",
                        fraction: Float(porcentaje) / 100
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Objetivos técnicos

    @ViewBuilder
    private var objetivosTecnicos: some View {
        if progresos.isEmpty {
            PadelCard {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("OBJETIVOS TÉCNICOS")
                    Text("Todavía no has puesto ninguno")
                        .font(.headline).foregroundStyle(T.tinta)
                    Text("Elige un golpe, mira la nota que tienes hoy y ponle una meta. Cada partido te dirá si te estás acercando.")
                        .font(.caption).foregroundStyle(T.tintaSuave)
                    Button(puedeCrear ? "Añadir objetivo" : "Añadir objetivo (Pro)") {
                        nuevoObjetivo()
                    }
                    .font(.subheadline.bold())
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 10) {
                HStack {
                    SectionLabel("OBJETIVOS TÉCNICOS")
                    Spacer()
                }
                ForEach(progresos, id: \.objetivo.golpe) { progreso in
                    Button { editando = progreso.objetivo } label: {
                        FilaDeObjetivo(progreso: progreso)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Sin temporada

    private var sinTemporada: some View {
        PadelCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("SIN TEMPORADA ABIERTA")
                Text("Los objetivos viven dentro de una temporada")
                    .font(.headline).foregroundStyle(T.tinta)
                Text("Una temporada es un tramo con fecha de inicio y de fin — «Reto hacia nivel 4», de octubre a diciembre. Ábrela aquí y podrás ponerle metas a cada golpe.")
                    .font(.caption).foregroundStyle(T.tintaSuave)
                Button("Abrir temporada") { editandoTemporada = true }
                    .font(.subheadline.bold())
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Crear

    /// El único camino hacia el editor: con Pro abre el editor y sin Pro abre la venta.
    /// Los dos botones de "nuevo objetivo" (el "+" y el de la tarjeta vacía) pasan por
    /// aquí para que no haya dos reglas distintas según por dónde se entre.
    private func nuevoObjetivo() {
        if puedeCrear {
            creando = true
        } else {
            vendiendo = true
        }
    }

    // MARK: Guardar

    /// Escribe el objetivo en la temporada activa, sustituyendo el del mismo golpe si
    /// ya existía. Un objetivo por golpe: dos metas a la vez para la bandeja no
    /// significan nada y la pantalla no sabría cuál enseñar.
    private func guardar(_ objetivo: ObjetivoDeGolpe?) {
        guard let temporada else { return }
        var objetivos = temporada.objetivosDeGolpe
        if let objetivo {
            objetivos.removeAll { $0.golpe.caseInsensitiveCompare(objetivo.golpe) == .orderedSame }
            objetivos.append(objetivo)
        }
        liga.actualizarObjetivosDeGolpe(objetivos, enTemporada: temporada.id)
        editando = nil
        creando = false
    }
}

// MARK: - Fila

private struct FilaDeObjetivo: View {
    let progreso: ProgresoDeObjetivo

    var body: some View {
        PadelCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(progreso.objetivo.golpe)
                        .font(.headline)
                        .foregroundStyle(T.tinta)
                    Spacer()
                    if progreso.cumplido {
                        Label("Cumplido", systemImage: "checkmark.seal.fill")
                            .font(.caption.bold())
                            .foregroundStyle(T.verde)
                    } else {
                        Text("\(progreso.porcentaje) %")
                            .font(.caption.bold())
                            .foregroundStyle(T.tintaSuave)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(progreso.notaActual.map { String(format: "%.2f", $0) } ?? "sin datos")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(T.tinta)
                    Text("de " + String(format: "%.2f", progreso.objetivo.notaObjetivo))
                        .font(.subheadline)
                        .foregroundStyle(T.tintaSuave)
                    Spacer()
                    Text("empezaste en " + String(format: "%.2f", progreso.objetivo.notaInicial))
                        .font(.caption2)
                        .foregroundStyle(T.tintaSuave)
                }
                PadelBar(
                    label: "Progreso",
                    value: "\(progreso.porcentaje) %",
                    fraction: Float(progreso.fraccion),
                    color: progreso.cumplido ? T.verde : T.lima
                )

                // Las últimas notas, que es lo que enseña si la tendencia acompaña. Sin
                // esto, un 60 % no dice si vas subiendo o llevas dos meses parado.
                if progreso.ultimas.count >= 2 {
                    HStack(spacing: 8) {
                        ForEach(Array(progreso.ultimas.enumerated()), id: \.offset) { _, nota in
                            Text(String(format: "%.2f", nota))
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(T.tintaSuave)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Editor

/// Alta y edición de una meta por golpe.
private struct EditorDeObjetivo: View {
    let objetivo: ObjetivoDeGolpe?
    let alGuardar: (ObjetivoDeGolpe?) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var liga: LigaModel

    @State private var golpe: String
    @State private var inicial: Double
    @State private var meta: Double

    init(objetivo: ObjetivoDeGolpe?, alGuardar: @escaping (ObjetivoDeGolpe?) -> Void) {
        self.objetivo = objetivo
        self.alGuardar = alGuardar
        _golpe = State(initialValue: objetivo?.golpe ?? GolpeVisible.bandeja.etiqueta)
        _inicial = State(initialValue: objetivo?.notaInicial ?? 3.0)
        _meta = State(initialValue: objetivo?.notaObjetivo ?? 3.5)
    }

    /// La nota que tiene hoy ese golpe, para proponerla como punto de partida. Que el
    /// jugador tenga que adivinar de dónde parte es la forma más fácil de que el
    /// porcentaje acabe siendo mentira.
    private var notaDeHoy: Double? {
        ProgresoDeGolpes.media(golpe, partidos: liga.state.matches, ultimos: ProgresoDeGolpes.ventana)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Golpe") {
                    Picker("Golpe", selection: $golpe) {
                        ForEach(GolpeVisible.allCases, id: \.self) { visible in
                            Text(visible.etiqueta).tag(visible.etiqueta)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("De dónde partes") {
                    Stepper(value: $inicial, in: 1...7, step: 0.1) {
                        Text(String(format: "%.1f", inicial))
                    }
                    if let notaDeHoy {
                        Button("Usar tu nota actual (\(String(format: "%.2f", notaDeHoy)))") {
                            inicial = (notaDeHoy * 10).rounded() / 10
                            if meta <= inicial { meta = min(7, inicial + 0.5) }
                        }
                        .font(.caption)
                    } else {
                        Text("Todavía no hay partidos con ese golpe medido.")
                            .font(.caption).foregroundStyle(T.tintaSuave)
                    }
                }

                Section("A dónde quieres llegar") {
                    Stepper(value: $meta, in: 1...7, step: 0.1) {
                        Text(String(format: "%.1f", meta))
                    }
                    if meta <= inicial {
                        Text("La meta tiene que estar por encima del punto de partida.")
                            .font(.caption).foregroundStyle(T.rojo)
                    }
                }

                if objetivo != nil {
                    Section {
                        Button("Quitar este objetivo", role: .destructive) {
                            alGuardar(nil)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(objetivo == nil ? "Nuevo objetivo" : "Objetivo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        alGuardar(ObjetivoDeGolpe(
                            golpe: golpe, notaInicial: inicial, notaObjetivo: meta
                        ))
                        dismiss()
                    }
                    .disabled(meta <= inicial)
                }
            }
        }
    }
}

// Para poder presentarlo con `.sheet(item:)`. El golpe identifica al objetivo porque
// solo puede haber uno por golpe — ver `guardar(_:)`.
extension ObjetivoDeGolpe: Identifiable {
    var id: String { golpe }
}
