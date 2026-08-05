import Charts
import SwiftUI

/// El panel de temporada de la liga: rachas, meta, evolución del nivel, rendimiento por
/// posición, tipo y compañero, golpes que se repiten y cumplimiento de objetivos. El
/// puerto del `PanelScreen` de la app Expo.
struct LigaSeasonView: View {
    @EnvironmentObject private var liga: LigaModel

    var body: some View {
        let matches = liga.state.matches
        let perfil = liga.state.perfil

        ScrollView {
            VStack(spacing: 12) {
                headlineCard(matches, perfil)
                mensualCard(matches)
                metaCard(matches, perfil)
                evolutionCard(matches)
                objetivosCard(matches)
                statsCard("Por posición", icon: "arrow.left.arrow.right", filas: LigaMetrics.statsPosicion(matches))
                statsCard("Competitivo y amistoso", icon: "flag.2.crossed", filas: LigaMetrics.statsTipo(matches))
                if !LigaMetrics.statsCompanero(matches).isEmpty {
                    statsCard("Con cada compañero", icon: "person.2.fill", filas: LigaMetrics.statsCompanero(matches))
                }
                golpesCard(matches)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(T.fondo)
        .navigationTitle("Temporada")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Cabecera

    private func headlineCard(_ matches: [LigaMatch], _ perfil: LigaPerfil) -> some View {
        let racha = LigaMetrics.racha(matches)
        return PadelCard {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    StatTile(label: "Partidos", value: "\(matches.count)")
                    StatTile(label: "Victorias", value: "\(LigaMetrics.pctVictorias(matches))%", tint: T.verde)
                    StatTile(
                        label: "Racha",
                        value: racha > 0 ? "\(racha) 🔥" : "0",
                        tint: racha > 0 ? T.bola : T.tintaSuave
                    )
                }
                HStack(spacing: 8) {
                    StatTile(
                        label: "Nivel actual",
                        value: LigaMetrics.nivelActual(matches, perfil: perfil)
                            .map { String(format: "%.2f", $0) } ?? "–",
                        tint: T.pista
                    )
                    StatTile(
                        label: "Desde el inicio",
                        value: LigaMetrics.deltaNivel(matches, perfil: perfil)
                            .map { String(format: "%+.2f", $0) } ?? "–",
                        tint: (LigaMetrics.deltaNivel(matches, perfil: perfil) ?? 0) >= 0 ? T.verde : T.rojo
                    )
                    StatTile(label: "Mejor racha", value: "\(LigaMetrics.mejorRacha(matches))")
                }
                Text("La racha cuenta partidos bien jugados seguidos: 2 de 3 objetivos cumplidos.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Mes en curso contra el anterior

    @ViewBuilder
    private func mensualCard(_ matches: [LigaMatch]) -> some View {
        if let resumen = LigaMetrics.resumenMensual(matches, hoyISO: LigaFechas.hoy()),
           resumen.actual.n + resumen.anterior.n > 0 {
            PadelCard(title: "Este mes", icon: "calendar") {
                VStack(spacing: 6) {
                    HStack {
                        Text("").frame(maxWidth: .infinity, alignment: .leading)
                        Text("PJ").frame(width: 36)
                        Text("V").frame(width: 48)
                        Text("Bien").frame(width: 48)
                    }
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
                    filaMes(resumen.actual, destacada: true)
                    filaMes(resumen.anterior, destacada: false)
                }
            }
        }
    }

    private func filaMes(_ mes: LigaMetrics.ResumenMes, destacada: Bool) -> some View {
        HStack {
            Text(mes.clave)
                .font(.system(size: 13, weight: destacada ? .bold : .medium, design: .rounded))
                .foregroundStyle(destacada ? T.tinta : T.tintaSuave)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(mes.n)").frame(width: 36)
            Text(mes.pctVictorias.map { "\($0)%" } ?? "–")
                .foregroundStyle(T.verde)
                .frame(width: 48)
            Text(mes.pctBienJugados.map { "\($0)%" } ?? "–")
                .foregroundStyle(T.pista)
                .frame(width: 48)
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .monospacedDigit()
    }

    // MARK: Meta de la temporada

    @ViewBuilder
    private func metaCard(_ matches: [LigaMatch], _ perfil: LigaPerfil) -> some View {
        if let progreso = LigaMetrics.progresoMeta(matches, perfil: perfil) {
            PadelCard(title: "Meta de la temporada", icon: "flag.checkered") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(perfil.nivelPlaytomic)
                        Spacer()
                        Text("\(progreso)%")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(T.pista)
                        Spacer()
                        Text(perfil.nivelObjetivo)
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(T.tintaSuave)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(T.borde)
                            Capsule()
                                .fill(T.pista)
                                .frame(width: geo.size.width * Double(progreso) / 100)
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
    }

    // MARK: Evolución

    @ViewBuilder
    private func evolutionCard(_ matches: [LigaMatch]) -> some View {
        let puntos = LigaMetrics.evolucion(matches)
        if puntos.count >= 2 {
            PadelCard(title: "Evolución del nivel", icon: "chart.xyaxis.line") {
                VStack(alignment: .leading, spacing: 8) {
                    Chart {
                        ForEach(Array(puntos.enumerated()), id: \.offset) { index, punto in
                            if let nivel = punto.nivel {
                                LineMark(
                                    x: .value("Partido", index),
                                    y: .value("Playtomic", nivel),
                                    series: .value("Serie", "Playtomic")
                                )
                                .foregroundStyle(T.pista)
                                .lineStyle(StrokeStyle(lineWidth: 2.5))
                                .interpolationMethod(.catmullRom)
                            }
                            if let sesion = punto.sesion {
                                LineMark(
                                    x: .value("Partido", index),
                                    y: .value("Sesión", sesion),
                                    series: .value("Serie", "Sesión")
                                )
                                .foregroundStyle(T.bola)
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                                .interpolationMethod(.catmullRom)
                            }
                        }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: 180)

                    HStack(spacing: 14) {
                        leyenda(color: T.pista, texto: "Playtomic (acumulativo)")
                        leyenda(color: T.bola, texto: "Nivel de sesión (reloj)")
                    }
                    if let primera = puntos.first, let ultima = puntos.last, puntos.count >= 2 {
                        Text("\(primera.fecha) – \(ultima.fecha)")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(T.tintaSuave)
                    }
                }
            }
        }
    }

    private func leyenda(color: Color, texto: String) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 14, height: 3)
            Text(texto)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(T.tintaSuave)
        }
    }

    // MARK: Objetivos

    @ViewBuilder
    private func objetivosCard(_ matches: [LigaMatch]) -> some View {
        let cumplimiento = LigaMetrics.cumplimientoObjetivos(matches)
        let objetivos = liga.state.objetivos
        if !matches.isEmpty {
            PadelCard(title: "Cumplimiento de objetivos", icon: "checklist") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(0..<min(3, objetivos.count), id: \.self) { index in
                        PadelBar(
                            label: objetivos[index],
                            value: cumplimiento[index].map { "\($0)%" } ?? "–",
                            fraction: Float(cumplimiento[index] ?? 0) / 100,
                            color: colorPct(cumplimiento[index])
                        )
                    }
                    Text("El entrenador sube la exigencia de los que ya cumples más del 70%.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                }
            }
        }
    }

    private func colorPct(_ pct: Int?) -> Color {
        guard let pct else { return T.tintaSuave }
        if pct >= 70 { return T.verde }
        return pct >= 40 ? T.bola : T.rojo
    }

    // MARK: Stats por grupo

    private func statsCard(_ titulo: String, icon: String, filas: [LigaStatsFila]) -> some View {
        PadelCard(title: titulo, icon: icon) {
            VStack(spacing: 6) {
                HStack {
                    Text("").frame(maxWidth: .infinity, alignment: .leading)
                    Text("PJ").frame(width: 36)
                    Text("V").frame(width: 48)
                    Text("Bien").frame(width: 48)
                }
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(T.tintaSuave)

                ForEach(filas) { fila in
                    HStack {
                        Text(fila.etiqueta)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(T.tinta)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(fila.n)")
                            .frame(width: 36)
                        Text(fila.pctVictorias.map { "\($0)%" } ?? "–")
                            .foregroundStyle(T.verde)
                            .frame(width: 48)
                        Text(fila.pctBienJugados.map { "\($0)%" } ?? "–")
                            .foregroundStyle(T.pista)
                            .frame(width: 48)
                    }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .monospacedDigit()
                }
            }
        }
    }

    // MARK: Golpes

    @ViewBuilder
    private func golpesCard(_ matches: [LigaMatch]) -> some View {
        let mejores = LigaMetrics.topMejores(matches)
        let peores = LigaMetrics.topPeores(matches)
        if !mejores.isEmpty || !peores.isEmpty {
            PadelCard(title: "Golpes que se repiten", icon: "figure.tennis") {
                VStack(alignment: .leading, spacing: 8) {
                    if !mejores.isEmpty {
                        SectionLabel("Como mejor golpe")
                        ForEach(mejores) { filaGolpe($0, color: T.verde) }
                    }
                    if !peores.isEmpty {
                        SectionLabel("Como peor golpe")
                        ForEach(peores) { filaGolpe($0, color: T.rojo) }
                    }
                }
            }
        }
    }

    private func filaGolpe(_ golpe: LigaGolpeAgregado, color: Color) -> some View {
        NavigationLink {
            LigaGolpeDetalleView(nombre: golpe.golpe)
        } label: {
            HStack {
                Text(golpe.golpe)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(T.tinta)
                Spacer()
                Text("\(golpe.veces)× · media \(String(format: "%.1f", golpe.media))/7")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(T.tintaSuave)
            }
        }
        .buttonStyle(.plain)
    }
}
