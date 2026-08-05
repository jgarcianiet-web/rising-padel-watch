import Charts
import SwiftUI

/// La ficha completa de un partido de la liga: marcador, niveles, golpes de la sesión,
/// curvas del reloj, salud, objetivos y nota. El calco de `PartidoDetalleScreen` de la
/// app Expo, con las tarjetas de esta app.
struct LigaMatchDetailView: View {
    @EnvironmentObject private var liga: LigaModel
    /// Se guarda el id y no el partido: si se edita, la ficha se redibuja con lo nuevo.
    let matchId: Int64

    @State private var editing = false

    var body: some View {
        Group {
            if let match = liga.state.matches.first(where: { $0.id == matchId }) {
                content(match)
            } else {
                ContentUnavailableView("Partido no encontrado", systemImage: "trophy")
            }
        }
        .background(T.fondo)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ m: LigaMatch) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                header(m)
                matchCard(m)
                if m.nivel != nil || m.nivelBand != nil || hayCurva(m) || m.totalGolpes != nil {
                    levelsCard(m)
                }
                if let puntos = m.bandPuntos, puntos.count >= 2 {
                    PadelCard(title: "Progreso de la sesión", icon: "chart.xyaxis.line") {
                        LigaProgressChart(puntos: puntos, media: m.bandMediaJugador)
                    }
                }
                if let frecuencia = m.frecuenciaGolpeo, !frecuencia.cuentas.isEmpty {
                    PadelCard(title: "Frecuencia de golpeo", icon: "chart.bar.fill") {
                        LigaFrequencyChart(frecuencia: frecuencia)
                    }
                }
                if m.mejorGolpe != nil || m.peorGolpe != nil
                    || !(m.golpesSesion ?? []).isEmpty || !(m.golpesVolumen ?? []).isEmpty {
                    strokesCard(m)
                }
                if let salud = m.salud {
                    PadelCard(title: "Salud (Apple Watch)", icon: "heart.fill") {
                        Text(salud.resumen)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(T.tinta)
                    }
                }
                goalsCard(m)
                Button {
                    editing = true
                } label: {
                    Label("Editar partido", systemImage: "pencil")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .sheet(isPresented: $editing) {
            LigaMatchFormView(editing: m)
                .environmentObject(liga)
        }
    }

    // MARK: Cabecera

    private func header(_ m: LigaMatch) -> some View {
        HStack(spacing: 12) {
            OutcomeBadge(text: badge(m.resultado), color: badgeColor(m.resultado))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(LigaFechas.corta(m.fecha)) · \(LigaFechas.mes(m.fecha))")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(T.tinta)
                Text(subtitulo(m))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
            }
            Spacer()
        }
    }

    private func subtitulo(_ m: LigaMatch) -> String {
        var texto = "\(m.tipo) · \(m.posicion == "reves" ? "revés" : "derecha")"
        if m.bienJugado { texto += " · bien jugado 🔥" }
        return texto
    }

    // MARK: Tarjetas

    private func matchCard(_ m: LigaMatch) -> some View {
        PadelCard(title: "El partido", icon: "trophy.fill") {
            VStack(alignment: .leading, spacing: 6) {
                if !m.sets.isEmpty {
                    Text(m.sets)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(T.pista)
                }
                if !m.club.isEmpty { linea("Club", m.club) }
                if !m.companero.isEmpty { linea("Compañero", m.companero) }
            }
        }
    }

    private func levelsCard(_ m: LigaMatch) -> some View {
        PadelCard(title: "Niveles de la sesión", icon: "gauge.with.needle") {
            VStack(alignment: .leading, spacing: 6) {
                if let nivel = m.nivel {
                    linea("Playtomic tras el partido", String(format: "%.2f", nivel))
                }
                if let sesion = m.nivelBand {
                    linea("Nivel de la sesión (reloj)", String(format: "%.1f/7", sesion))
                }
                if hayCurva(m) {
                    linea("Curva de la sesión", resumenCurva(m))
                }
                if let total = m.totalGolpes {
                    linea("Total de golpeos", "\(total)")
                }
            }
        }
    }

    private func strokesCard(_ m: LigaMatch) -> some View {
        PadelCard(title: "Golpes", icon: "figure.tennis") {
            VStack(alignment: .leading, spacing: 8) {
                if let mejor = m.mejorGolpe {
                    linea("👍 Mejor", m.mejorPunt.map { String(format: "%@ · %.0f/7", mejor, $0) } ?? mejor)
                }
                if let peor = m.peorGolpe {
                    linea("👎 Peor", m.peorPunt.map { String(format: "%@ · %.0f/7", peor, $0) } ?? peor)
                }
                if let golpes = m.golpesSesion, !golpes.isEmpty {
                    SectionLabel("Notas de la sesión")
                    // Cada chip abre la trayectoria del golpe por las sesiones.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6, alignment: .leading)],
                              alignment: .leading, spacing: 6) {
                        ForEach(Array(golpes.enumerated()), id: \.offset) { _, golpe in
                            NavigationLink {
                                LigaGolpeDetalleView(nombre: golpe.nombre)
                            } label: {
                                chip(golpe.nombre, String(format: "%.1f", golpe.nota))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if let volumen = m.golpesVolumen, !volumen.isEmpty {
                    SectionLabel("Volumen de golpeo")
                    chips(volumen.map { ($0.nombre, "×\($0.cantidad)") })
                }
            }
        }
    }

    private func goalsCard(_ m: LigaMatch) -> some View {
        let objetivos = liga.state.objetivos
        return PadelCard(
            title: "Objetivos · \(m.objetivos.filter { $0 }.count)/\(m.objetivos.count)",
            icon: "checklist"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(m.objetivos.enumerated()), id: \.offset) { index, cumplido in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: cumplido ? "checkmark.circle.fill" : "xmark.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(cumplido ? T.verde : T.rojo)
                        Text(index < objetivos.count ? objetivos[index] : "—")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(T.tinta)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Los textos son tus objetivos actuales; los checks, lo que marcaste ese día.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
                if !m.nota.isEmpty {
                    Text("“\(m.nota)”")
                        .font(.system(size: 14, design: .rounded))
                        .italic()
                        .foregroundStyle(T.tinta)
                }
            }
        }
    }

    // MARK: Piezas

    private func linea(_ etiqueta: String, _ valor: String) -> some View {
        HStack(alignment: .top) {
            Text(etiqueta)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(T.tintaSuave)
            Spacer()
            Text(valor)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(T.tinta)
                .multilineTextAlignment(.trailing)
        }
    }

    private func chips(_ items: [(String, String)]) -> some View {
        // Un grid fluido de chips: LazyVGrid adaptativo en vez del flex-wrap de RN.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6, alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                chip(item.0, item.1)
            }
        }
    }

    private func chip(_ nombre: String, _ valor: String) -> some View {
        HStack(spacing: 4) {
            Text(nombre)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(T.tinta)
            Text(valor)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(T.pista)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 9)
        .background(T.fondo, in: Capsule())
        .overlay(Capsule().stroke(T.borde, lineWidth: 1))
    }

    private func hayCurva(_ m: LigaMatch) -> Bool {
        m.bandInicio != nil || m.bandFin != nil
    }

    private func resumenCurva(_ m: LigaMatch) -> String {
        let inicio = m.bandInicio.map { String(format: "%.1f", $0) } ?? "?"
        let fin = m.bandFin.map { String(format: "%.1f", $0) } ?? "?"
        var texto = "\(inicio) → \(fin)"
        if let media = m.bandMediaJugador {
            texto += String(format: " (media %.1f)", media)
        }
        return texto
    }

    private func badge(_ resultado: String) -> String {
        switch resultado {
        case "victoria": return "V"
        case "empate": return "E"
        default: return "D"
        }
    }

    private func badgeColor(_ resultado: String) -> Color {
        switch resultado {
        case "victoria": return T.verde
        case "empate": return T.tintaSuave
        default: return T.rojo
        }
    }
}

// MARK: - Gráficas de un partido de la liga

/// Las mismas curvas que las sesiones del reloj, pero desde los datos guardados en el
/// partido — que pueden venir del reloj o de una captura de Padel Band importada.

struct LigaProgressChart: View {
    let puntos: [LigaPuntoProgreso]
    let media: Double?

    var body: some View {
        Chart {
            ForEach(Array(puntos.enumerated()), id: \.offset) { _, punto in
                AreaMark(
                    x: .value("Minuto", punto.minuto),
                    y: .value("Nivel", punto.nivel)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(T.pista.opacity(0.15))
                LineMark(
                    x: .value("Minuto", punto.minuto),
                    y: .value("Nivel", punto.nivel)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(T.pista)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            if let media {
                RuleMark(y: .value("Tu media", media))
                    .foregroundStyle(T.bola)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .annotation(position: .top, alignment: .trailing) {
                        Text(String(format: "tu media %.2f", media))
                            .font(.caption2)
                            .foregroundStyle(T.tintaSuave)
                    }
            }
        }
        .chartYScale(domain: dominio)
        .chartXAxisLabel("minutos")
        .frame(height: 180)
    }

    private var dominio: ClosedRange<Double> {
        var low = puntos.map(\.nivel).min() ?? 1
        var high = puntos.map(\.nivel).max() ?? 7
        if let media {
            low = min(low, media)
            high = max(high, media)
        }
        return max(low - 0.2, 1)...min(high + 0.2, 7)
    }
}

struct LigaFrequencyChart: View {
    let frecuencia: LigaFrecuenciaGolpeo

    var body: some View {
        Chart(Array(frecuencia.cuentas.enumerated()), id: \.offset) { index, cuenta in
            BarMark(
                x: .value("Tiempo", etiqueta(index)),
                y: .value("Golpeos", cuenta)
            )
            .foregroundStyle(T.pista)
            .cornerRadius(3)
        }
        .chartYAxisLabel("golpeos")
        .frame(height: 180)
    }

    private func etiqueta(_ index: Int) -> String {
        let minutos = (index + 1) * frecuencia.intervaloMin
        return String(format: "%d:%02d", minutos / 60, minutos % 60)
    }
}
