import PadelCore
import SwiftUI

/// La portada de la app (§3 y §5 del documento de producto).
///
/// El principio que la gobierna, y el que decide qué entra y qué no: **el jugador tiene
/// que entender su situación en menos de cinco segundos**. Tres preguntas, en este
/// orden: dónde estoy, qué estoy mejorando, qué hago ahora. Todo lo que no conteste a
/// una de las tres se queda fuera de esta pantalla y vive en su pestaña.

// MARK: - Splash

/// Pantalla de arranque. Negra, con la marca, y se va sola.
///
/// Dura 1,1 s a propósito: lo justo para que la animación se lea, no tanto como para
/// que estorbe a quien abre la app cinco veces al día. No bloquea nada — lo de detrás
/// ya está cargado cuando desaparece.
struct SplashView: View {
    @State private var visible = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 10) {
                Text("RISING")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(.white)
                Text("PÁDEL")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(T.lima)
                Text("MEASURE. TRAIN. RISE.")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 12)
            }
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.94)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) { visible = true }
        }
    }
}

// MARK: - Inicio

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var liga: LigaModel

    /// A dónde saltar cuando se toca una tarjeta. La portada no resuelve nada por sí
    /// misma: orienta y manda a la pestaña que sí lo hace.
    let irA: (PestanaPrincipal) -> Void

    @State private var mostrarAjustes = false
    @State private var mostrarComunidad = false

    private var ultima: PadelSession? { model.sessions.first }

    private var progresos: [ProgresoDeObjetivo] {
        guard let temporada = liga.temporadaActual else { return [] }
        return ProgresoDeGolpes.deTemporada(temporada, partidos: liga.state.matches)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    risingLevel
                    objetivoPrincipal
                    areaDeMejora
                    ultimoPartido
                    tarjetaCoach
                }
                .padding(16)
            }
            .background(T.fondo)
            .navigationTitle("Rising Pádel")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { mostrarComunidad = true } label: {
                        Image(systemName: "person.3.fill")
                    }
                    .accessibilityLabel("Comunidad")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { mostrarAjustes = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Ajustes")
                }
            }
            .sheet(isPresented: $mostrarAjustes) { SettingsView() }
            .sheet(isPresented: $mostrarComunidad) { ComunidadView() }
        }
    }

    // MARK: Rising Level

    private var risingLevel: some View {
        let actual = LigaMetrics.nivelActual(liga.state.matches, perfil: liga.state.perfil)
        let delta = LigaMetrics.deltaNivel(liga.state.matches, perfil: liga.state.perfil)

        return Tarjeta {
            VStack(spacing: 4) {
                Rotulo("RISING LEVEL")
                if let actual {
                    Text(String(format: "%.2f", actual))
                        .font(.system(size: 54, weight: .heavy, design: .rounded))
                        .foregroundStyle(T.tinta)
                    if let delta, abs(delta) >= 0.01 {
                        Text(
                            (delta > 0 ? "+" : "") + String(format: "%.2f", delta)
                                + "  ·  vs. tus últimos partidos"
                        )
                        .font(.caption)
                        .foregroundStyle(delta > 0 ? T.verde : T.rojo)
                    }
                } else {
                    Text("—")
                        .font(.system(size: 54, weight: .heavy, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                    Text("Juega un partido con el reloj y aquí aparecerá tu nivel.")
                        .font(.caption)
                        .foregroundStyle(T.tintaSuave)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Objetivo principal

    @ViewBuilder
    private var objetivoPrincipal: some View {
        let perfil = liga.state.perfil
        if !perfil.nivelObjetivo.isEmpty,
           let porcentaje = LigaMetrics.progresoMeta(liga.state.matches, perfil: perfil) {
            Button { irA(.objetivos) } label: {
                Tarjeta {
                    VStack(alignment: .leading, spacing: 8) {
                        Rotulo("OBJETIVO")
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(perfil.nivelPlaytomic.isEmpty ? "—" : perfil.nivelPlaytomic)
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                            Image(systemName: "arrow.right")
                                .font(.caption.bold())
                                .foregroundStyle(T.tintaSuave)
                            Text(perfil.nivelObjetivo)
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(T.pista)
                        }
                        Barra(fraccion: Double(porcentaje) / 100, color: T.pista)
                        Text("\(porcentaje) %")
                            .font(.caption)
                            .foregroundStyle(T.tintaSuave)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Principal área de mejora

    @ViewBuilder
    private var areaDeMejora: some View {
        if let area = ProgresoDeGolpes.principalAreaDeMejora(progresos) {
            Button { irA(.objetivos) } label: {
                Tarjeta {
                    VStack(alignment: .leading, spacing: 8) {
                        Rotulo("PRINCIPAL ÁREA DE MEJORA")
                        Text(area.objetivo.golpe.uppercased())
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(T.tinta)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(area.notaActual.map { String(format: "%.2f", $0) } ?? "sin datos")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                            Text("/ " + String(format: "%.2f", area.objetivo.notaObjetivo))
                                .font(.subheadline)
                                .foregroundStyle(T.tintaSuave)
                        }
                        Barra(fraccion: area.fraccion, color: T.lima)
                        if area.notaActual != nil {
                            Text(
                                (area.avance >= 0 ? "+" : "")
                                    + String(format: "%.2f", area.avance)
                                    + " desde el inicio"
                            )
                            .font(.caption)
                            .foregroundStyle(area.avance >= 0 ? T.verde : T.rojo)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
        } else if liga.temporadaActual?.objetivosDeGolpe.isEmpty ?? true {
            // Sin objetivos no hay área de mejora que enseñar, y decirlo es más útil
            // que dejar el hueco en blanco: es la acción que falta por hacer.
            Button { irA(.objetivos) } label: {
                Tarjeta {
                    VStack(alignment: .leading, spacing: 6) {
                        Rotulo("TUS OBJETIVOS")
                        Text("Ponle una meta a un golpe")
                            .font(.headline)
                            .foregroundStyle(T.tinta)
                        Text("Elige un golpe y hasta dónde quieres llevarlo. La app te dirá cada partido si te estás acercando.")
                            .font(.caption)
                            .foregroundStyle(T.tintaSuave)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Último partido

    @ViewBuilder
    private var ultimoPartido: some View {
        if let sesion = ultima {
            // Va a la ficha de ESTA sesión y no a la pestaña de partidos: desde la
            // portada, "ver análisis" significa ver este partido, no una lista donde
            // hay que volver a buscarlo. Se empuja `SessionDetailView` y no
            // `LastSessionView` porque esa última trae su propio NavigationStack y
            // anidarlos deja dos barras de título, una encima de la otra.
            NavigationLink { SessionDetailView(session: sesion) } label: {
                Tarjeta {
                    VStack(alignment: .leading, spacing: 10) {
                        Rotulo("ÚLTIMO PARTIDO")
                        HStack(spacing: 18) {
                            Dato(
                                titulo: "Nivel",
                                valor: sesion.level.gradedShots > 0
                                    ? String(format: "%.2f", sesion.level.overall)
                                    : "—"
                            )
                            Dato(titulo: "Duración", valor: formatDuration(sesion.durationSeconds))
                            Dato(titulo: "Intensidad", valor: intensidad(sesion))
                        }
                        Text("Ver análisis")
                            .font(.caption.bold())
                            .foregroundStyle(T.pista)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// La intensidad, a partir del pulso medio contra las zonas que ya calcula el core.
    /// Sin permiso de salud no hay pulso y no se enseña nada inventado.
    private func intensidad(_ sesion: PadelSession) -> String {
        let segundos = sesion.health.zones.secondsPerZone
        let total = segundos.values.reduce(0, +)
        guard total > 0 else { return "—" }
        // Z4 y Z5 son el trabajo duro; la proporción que ocupan es lo que distingue un
        // partido exigente de un peloteo largo con el mismo número de golpeos.
        let duras = (segundos["z4"] ?? 0) + (segundos["z5"] ?? 0)
        let fraccion = Double(duras) / Double(total)
        if fraccion >= 0.35 { return "Alta" }
        if fraccion >= 0.12 { return "Media" }
        return "Suave"
    }

    // MARK: Rising AI

    private var tarjetaCoach: some View {
        Button { irA(.coach) } label: {
            Tarjeta {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "brain.head.profile")
                        Rotulo("RISING AI")
                    }
                    Text(liga.state.analisis?.lectura ?? "Pregúntale a tu entrenador qué entrenar esta semana.")
                        .font(.subheadline)
                        .foregroundStyle(T.tinta)
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)
                    Text(liga.state.analisis == nil ? "Abrir el entrenador" : "Ver recomendaciones")
                        .font(.caption.bold())
                        .foregroundStyle(T.pista)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Piezas compartidas de la portada

/// El contenedor de todas las tarjetas. Existe para que no haya seis definiciones
/// distintas de "tarjeta" con radios y sombras que no coinciden.
struct Tarjeta<Contenido: View>: View {
    @ViewBuilder let contenido: Contenido

    var body: some View {
        contenido
            .padding(16)
            .background(T.superficie, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(T.borde, lineWidth: 1))
    }
}

/// El rótulo pequeño en mayúsculas que encabeza cada tarjeta.
struct Rotulo: View {
    private let texto: String
    init(_ texto: String) { self.texto = texto }

    var body: some View {
        Text(texto)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(1.1)
            .foregroundStyle(T.tintaSuave)
    }
}

/// Una barra de progreso con la altura y el radio de la app. La de sistema no deja
/// fijar el color en todos los estilos y quedaba de un azul que no es el nuestro.
struct Barra: View {
    let fraccion: Double
    var color: Color = T.pista

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(T.borde)
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * min(max(fraccion, 0), 1))
            }
        }
        .frame(height: 8)
    }
}

/// Un número con su etiqueta debajo, la unidad mínima de las fichas.
struct Dato: View {
    let titulo: String
    let valor: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(valor)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(T.tinta)
            Text(titulo)
                .font(.caption2)
                .foregroundStyle(T.tintaSuave)
        }
    }
}
