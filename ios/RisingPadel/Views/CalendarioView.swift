import PadelCore
import SwiftUI

/// Las últimas doce semanas de juego, un cuadro por día.
///
/// El histórico es una lista, y una lista contesta "¿qué hice el martes?" pero no "¿estoy
/// jugando menos que el mes pasado?". Esa segunda es la que hace que alguien vuelva a
/// abrir la app, y se contesta de un vistazo o no se contesta: un hueco de dos semanas se
/// ve, no se lee.
struct CalendarioView: View {
    let sesiones: [PadelSession]

    private var calendario: CalendarioDeActividad? {
        CalendarioDeActividad.de(
            CalendarioDeActividad.porDia(sesiones),
            hastaISO: Fechas.hoyISO()
        )
    }

    private let lado: CGFloat = 13
    private let hueco: CGFloat = 3

    var body: some View {
        if let calendario, calendario.hayDatos {
            PadelCard(title: "Cuándo juegas", icon: "square.grid.3x3.fill") {
                VStack(alignment: .leading, spacing: 10) {
                    cuadricula(calendario)
                    resumen(calendario)
                    leyenda
                }
            }
        }
    }

    private func cuadricula(_ calendario: CalendarioDeActividad) -> some View {
        // Las semanas son columnas y los días filas, como el calendario de contribuciones
        // que todo el mundo ya sabe leer: el tiempo corre de izquierda a derecha.
        HStack(alignment: .top, spacing: hueco) {
            // Las iniciales de los días, a la izquierda. Solo tres: con las siete no se
            // lee ninguna al tamaño que caben.
            VStack(alignment: .leading, spacing: hueco) {
                ForEach(0..<7, id: \.self) { fila in
                    Text(["L", "", "X", "", "V", "", "D"][fila])
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .frame(width: 10, height: lado, alignment: .leading)
                }
            }
            ForEach(Array(calendario.semanas.enumerated()), id: \.offset) { _, semana in
                VStack(spacing: hueco) {
                    ForEach(semana) { dia in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color(dia, maximo: calendario.maxGolpes))
                            .frame(width: lado, height: lado)
                            .accessibilityLabel(etiqueta(dia))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// El color va por golpes y no por "jugó / no jugó": media hora de peloteo y un
    /// partido de dos horas no son lo mismo, y un cuadro plano lo diría.
    private func color(_ dia: DiaDeActividad, maximo: Int) -> Color {
        guard dia.jugado else { return T.borde.opacity(0.45) }
        guard maximo > 0 else { return T.lima }
        let intensidad = Double(dia.golpes) / Double(maximo)
        return T.lima.opacity(0.35 + 0.65 * min(1, max(0, intensidad)))
    }

    private func etiqueta(_ dia: DiaDeActividad) -> String {
        dia.jugado
            ? "\(dia.fechaISO): \(dia.golpes) golpeos en \(dia.minutos) minutos"
            : "\(dia.fechaISO): sin jugar"
    }

    private func resumen(_ calendario: CalendarioDeActividad) -> some View {
        HStack(spacing: 8) {
            StatTile(
                label: "Días jugados",
                value: "\(calendario.diasJugados)"
            )
            StatTile(
                label: "Por semana",
                value: String(format: "%.1f", calendario.diasPorSemana),
                tint: T.pista
            )
            StatTile(
                label: "Racha",
                value: calendario.rachaActual > 0 ? "\(calendario.rachaActual) 🔥" : "0",
                tint: calendario.rachaActual > 0 ? T.bola : T.tintaSuave
            )
            StatTile(label: "Mejor racha", value: "\(calendario.mejorRacha)")
        }
    }

    private var leyenda: some View {
        HStack(spacing: 6) {
            Text("Menos")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(T.tintaSuave)
            ForEach([0.0, 0.35, 0.6, 0.8, 1.0], id: \.self) { nivel in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(nivel == 0 ? T.borde.opacity(0.45) : T.lima.opacity(nivel))
                    .frame(width: 9, height: 9)
            }
            Text("Más")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(T.tintaSuave)
            Spacer()
            Text("12 semanas")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(T.tintaSuave)
        }
    }
}
