import Charts
import SwiftUI

/// La trayectoria de un golpe a través de las sesiones: cómo evoluciona su nota y
/// cuántos se dan cada día. El puerto de `GolpeDetalleScreen` de la app Expo. Se llega
/// tocando el chip del golpe en la ficha de un partido.
struct LigaGolpeDetalleView: View {
    @EnvironmentObject private var liga: LigaModel
    let nombre: String

    var body: some View {
        let evolucion = LigaMetrics.evolucionGolpe(liga.state.matches, nombre: nombre)

        ScrollView {
            VStack(spacing: 12) {
                PadelCard {
                    HStack(spacing: 8) {
                        StatTile(label: "Sesiones", value: "\(evolucion.veces)")
                        StatTile(
                            label: "Media",
                            value: evolucion.media.map { String(format: "%.1f", $0) } ?? "–",
                            tint: T.pista
                        )
                        StatTile(
                            label: "Mejor",
                            value: evolucion.mejor.map { String(format: "%.1f", $0) } ?? "–",
                            tint: T.verde
                        )
                        StatTile(
                            label: "Peor",
                            value: evolucion.peor.map { String(format: "%.1f", $0) } ?? "–",
                            tint: T.rojo
                        )
                    }
                }

                if evolucion.puntos.count >= 2 {
                    PadelCard(title: "Nota por sesión", icon: "chart.xyaxis.line") {
                        Chart {
                            ForEach(Array(evolucion.puntos.enumerated()), id: \.offset) { index, punto in
                                AreaMark(x: .value("Sesión", index), y: .value("Nota", punto.nota))
                                    .interpolationMethod(.catmullRom)
                                    .foregroundStyle(T.pista.opacity(0.15))
                                LineMark(x: .value("Sesión", index), y: .value("Nota", punto.nota))
                                    .interpolationMethod(.catmullRom)
                                    .foregroundStyle(T.pista)
                                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                                PointMark(x: .value("Sesión", index), y: .value("Nota", punto.nota))
                                    .foregroundStyle(T.pista)
                            }
                        }
                        .chartYScale(domain: dominio(evolucion))
                        .chartXAxis(.hidden)
                        .frame(height: 180)
                    }
                }

                PadelCard(title: "Sesión a sesión", icon: "list.bullet") {
                    VStack(spacing: 6) {
                        ForEach(evolucion.puntos.reversed()) { punto in
                            HStack {
                                Text(punto.fecha)
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundStyle(T.tintaSuave)
                                Spacer()
                                if let cantidad = punto.cantidad {
                                    Text("×\(cantidad)")
                                        .font(.system(size: 12, design: .rounded))
                                        .foregroundStyle(T.tintaSuave)
                                }
                                Text(String(format: "%.1f", punto.nota))
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(T.pista)
                            }
                        }
                    }
                }

                if evolucion.puntos.isEmpty {
                    Text("Este golpe todavía no tiene notas guardadas en ningún partido.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(T.fondo)
        .navigationTitle(nombre)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dominio(_ evolucion: LigaMetrics.EvolucionGolpe) -> ClosedRange<Double> {
        let low = evolucion.peor ?? 1
        let high = evolucion.mejor ?? 7
        return max(low - 0.3, 1)...min(high + 0.3, 7)
    }
}

/// El historial de análisis del entrenador: qué te dijo cada vez, para ver cómo
/// evoluciona su lectura de tu juego (y si le hiciste caso).
struct LigaAnalisisHistorialView: View {
    @EnvironmentObject private var liga: LigaModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Del más reciente al más viejo, como el historial de partidos.
                ForEach(Array(liga.state.analisisHistorial.reversed().enumerated()), id: \.offset) { _, analisis in
                    PadelCard(
                        title: analisis.fecha.isEmpty
                            ? "Análisis"
                            : "\(LigaFechas.corta(analisis.fecha)) · sobre \(analisis.nPartidos) partidos",
                        icon: "brain.head.profile"
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(analisis.lectura)
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(T.tinta)
                                .fixedSize(horizontal: false, vertical: true)
                            if !analisis.foco.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "scope")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(T.pista)
                                    Text(analisis.foco)
                                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                                        .foregroundStyle(T.tinta)
                                }
                            }
                            if !analisis.objetivos.isEmpty {
                                Text(analisis.objetivos.map { "• \($0)" }.joined(separator: "\n"))
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(T.tintaSuave)
                            }
                        }
                    }
                }
                if liga.state.analisisHistorial.isEmpty {
                    ContentUnavailableView(
                        "Todavía no hay análisis",
                        systemImage: "brain.head.profile",
                        description: Text("Pide el primero desde la tarjeta del entrenador en la Liga.")
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(T.fondo)
        .navigationTitle("Análisis anteriores")
        .navigationBarTitleDisplayMode(.inline)
    }
}
