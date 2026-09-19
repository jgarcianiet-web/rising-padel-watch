import PadelCore
import SwiftUI

/// **PARTIDOS** (§6 y §22 del documento de producto): el historial y el alta.
///
/// La app tiene dos historiales que no son el mismo y los dos hacen falta:
///
/// - **Sesiones** (última y histórico): lo que grabó el reloj. Golpeos, niveles por
///   golpe, pulso, curvas, el panel de precisión y la revisión "¿acertó el reloj?". Es
///   la materia prima y llega sola al acabar de jugar.
/// - **Liga**: los partidos con rival, resultado, club y objetivos. Algunos vienen de
///   una sesión y otros se apuntan a mano — un partido jugado sin reloj sigue contando
///   para tu liga.
///
/// Meterlos en una sola lista fue la primera idea y era mala: un partido a mano sin
/// sensores y una sesión sin marcador son fichas distintas, con datos distintos, y
/// mezclarlas obligaba a que la mitad de las columnas saliera vacía. El selector es más
/// honesto y además es cómo piensa el jugador: *"¿voy a mirar cómo jugué o a apuntar un
/// resultado?"*.
struct PartidosView: View {

    enum Cara: String, CaseIterable, Identifiable {
        case ultima = "Última"
        case historico = "Histórico"
        case liga = "Liga"
        var id: String { rawValue }
    }

    /// Arranca en la última: al salir de la pista, lo que se abre la app para mirar es
    /// el partido que se acaba de jugar, no una lista.
    @State private var cara: Cara = .ultima

    var body: some View {
        VStack(spacing: 0) {
            Picker("Qué mirar", selection: $cara) {
                ForEach(Cara.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(T.fondo)

            // Cada cara trae su propia pila de navegación, así que no se envuelven:
            // anidar NavigationStack deja dos barras de título, una encima de la otra.
            switch cara {
            case .ultima: LastSessionView()
            case .historico: SessionListView()
            case .liga: LigaView()
            }
        }
        .background(T.fondo)
    }
}
