import Charts
import PadelCore
import SwiftUI

/// **MI EVOLUCIÓN** (§16 y §17 del documento de producto).
///
/// El Rising Level a lo largo del tiempo y, debajo, una tarjeta por golpe con su nota y
/// cuánto ha cambiado. Responde a "¿voy mejorando?" con la única respuesta que vale:
/// dos números y la distancia entre ellos.
struct EvolucionView: View {
    @EnvironmentObject private var liga: LigaModel

    /// Los tramos que pide el documento. El seleccionado recorta los partidos de la
    /// gráfica y también el cálculo de las tarjetas: si miras tres meses, la flecha
    /// tiene que comparar dentro de esos tres meses.
    enum Tramo: String, CaseIterable, Identifiable {
        case semana = "7 días"
        case mes = "30 días"
        case trimestre = "3 meses"
        case temporada = "Temporada"
        case todo = "Todo"

        var id: String { rawValue }

        /// Días hacia atrás, o nil si el tramo no se define por días.
        var dias: Int? {
            switch self {
            case .semana: return 7
            case .mes: return 30
            case .trimestre: return 90
            case .temporada, .todo: return nil
            }
        }
    }

    /// El plan del jugador. **La curva entera es gratis; partirla en tramos es de Pro.**
    ///
    /// Esconder la evolución completa detrás del muro dejaría la app sin lo único que
    /// contesta "¿voy mejorando?", que es la razón por la que alguien se la instala. Lo
    /// que se vende es leerla por trozos —los últimos siete días, el trimestre, la
    /// temporada—, que es lo que se usa cuando ya llevas meses midiendo.
    @StateObject private var tienda = TiendaModel.compartida

    @State private var tramo: Tramo = .mes
    @State private var muroAbierto = false

    private var puedeElegirTramo: Bool {
        Gating.disponible(.evolucionPorTramos, plan: tienda.plan)
    }

    /// El tramo que se aplica de verdad: sin Pro, siempre el historial entero.
    /// Se filtra aquí y no solo en la interfaz — cambiar el `Picker` de sitio no puede
    /// abrir la función.
    private var tramoVigente: Tramo { puedeElegirTramo ? tramo : .todo }

    private var partidos: [LigaMatch] {
        let todos = liga.state.matches
        switch tramoVigente {
        case .todo:
            return todos
        case .temporada:
            guard let actual = liga.temporadaActual else { return todos }
            return todos.filter { actual.contiene($0) }
        default:
            guard let dias = tramoVigente.dias,
                  let desde = Calendar.current.date(
                    byAdding: .day, value: -dias, to: Date()
                  )
            else { return todos }
            let corte = LigaFechas.iso(desde)
            return todos.filter { $0.fecha >= corte }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    selector
                    nivelGlobal
                    tarjetasDeGolpes
                }
                .padding(16)
            }
            .background(T.fondo)
            .navigationTitle("Mi evolución")
            .sheet(isPresented: $muroAbierto) {
                PaywallView(destacando: .evolucionPorTramos, enHoja: true)
            }
        }
    }

    @ViewBuilder
    private var selector: some View {
        if puedeElegirTramo {
            Picker("Tramo", selection: $tramo) {
                ForEach(Tramo.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        } else {
            // Sin Pro se enseña lo que hay —el historial entero— y al lado lo que se
            // compra, dicho con el nombre del tramo y no con un candado genérico.
            Button { muroAbierto = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                    Text("Viendo todo tu historial · elegir tramo es de Pro")
                        .font(.caption)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                }
                .foregroundStyle(T.tintaSuave)
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(T.superficie, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.borde, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Rising Level

    private var nivelGlobal: some View {
        let puntos = partidos
            .compactMap { partido -> (String, Double)? in
                guard let nivel = LigaMetrics.nivelDeSesion(partido) else { return nil }
                return (partido.fecha, nivel)
            }
            .sorted { $0.0 < $1.0 }

        return PadelCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("RISING LEVEL")
                if let ultimo = puntos.last?.1 {
                    Text(String(format: "%.2f", ultimo))
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(T.tinta)
                }
                if puntos.count >= 2 {
                    Chart(Array(puntos.enumerated()), id: \.offset) { indice, punto in
                        LineMark(
                            x: .value("Partido", indice),
                            y: .value("Nivel", punto.1)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(T.pista)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }
                    // La escala se ciñe a la zona con datos: en el 1-7 entero, la
                    // variación de un mes sería una raya plana que no cuenta nada.
                    .chartYScale(domain: dominio(puntos.map(\.1)))
                    .chartXAxis(.hidden)
                    .frame(height: 150)
                } else {
                    Text("Con dos o más partidos en este tramo aparecerá la curva.")
                        .font(.caption)
                        .foregroundStyle(T.tintaSuave)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func dominio(_ niveles: [Double]) -> ClosedRange<Double> {
        let bajo = niveles.min() ?? 1
        let alto = niveles.max() ?? 7
        return max(bajo - 0.2, 1)...min(alto + 0.2, 7)
    }

    // MARK: Tarjetas por golpe

    private var tarjetasDeGolpes: some View {
        // Se recorre el repertorio y no los nombres que aparezcan en los partidos, para
        // que el orden sea siempre el mismo y no baile según lo que jugaras esa semana.
        let filas = GolpeVisible.allCases.compactMap { visible -> (String, Double, Double?)? in
            let notas = ProgresoDeGolpes.notasDe(visible.etiqueta, partidos: partidos)
            guard let actual = notas.last else { return nil }
            // El cambio se mide contra la PRIMERA nota del tramo, que es lo que
            // significa "has mejorado en los últimos 30 días".
            let delta = notas.count >= 2 ? actual - notas[0] : nil
            return (visible.etiqueta, actual, delta)
        }

        return VStack(spacing: 10) {
            HStack {
                SectionLabel("TUS GOLPES")
                Spacer()
            }
            if filas.isEmpty {
                PadelCard {
                    Text("No hay golpes medidos en este tramo.")
                        .font(.caption)
                        .foregroundStyle(T.tintaSuave)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(filas, id: \.0) { nombre, nota, delta in
                    NavigationLink {
                        LigaGolpeDetalleView(nombre: nombre)
                    } label: {
                        PadelCard {
                            HStack {
                                Text(nombre)
                                    .font(.headline)
                                    .foregroundStyle(T.tinta)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(String(format: "%.2f", nota))
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundStyle(T.tinta)
                                    if let delta, abs(delta) >= 0.01 {
                                        Text(
                                            (delta > 0 ? "↑ +" : "↓ ")
                                                + String(format: "%.2f", delta)
                                        )
                                        .font(.caption2.bold())
                                        .foregroundStyle(delta > 0 ? T.verde : T.rojo)
                                    }
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
