import PadelCore
import SwiftUI

/// El panel de precisión del reloj: cuánto acierta, golpe a golpe, y qué toca arreglar.
///
/// Este número ya existía, pero repartido: dentro de cada sesión revisada y dentro de
/// cada tanda. Suelto no cambiaba ninguna decisión. Junto responde a las dos preguntas
/// que de verdad importan: ¿me puedo fiar de lo que cuenta este reloj?, y si no, ¿qué
/// tanda tengo que ir a grabar el sábado?
struct PrecisionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                let informe = model.precision
                VStack(spacing: 12) {
                    if informe.hayDatos {
                        titularCard(informe)
                        if !informe.golpes.isEmpty { golpesCard(informe) }
                        if !informe.golpesSinTandas.isEmpty { pendientesCard(informe) }
                    } else {
                        vacioCard
                    }
                    metodoCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(T.fondo)
            .scrollContentBackground(.hidden)
            .navigationTitle("Precisión del reloj")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    // MARK: El titular

    private func titularCard(_ informe: InformeDePrecision) -> some View {
        PadelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: -4) {
                        Text(informe.aciertoGlobal.map { "\(pct($0))%" } ?? "—")
                            .font(.padelDisplay(56))
                            .monospacedDigit()
                            .foregroundStyle(color(informe.aciertoGlobal))
                        Text("acierta el reloj")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(T.tintaSuave)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(informe.golpesEnTandas)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(T.tinta)
                        Text("golpes medidos")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(T.tintaSuave)
                    }
                }

                if let sin = informe.sinClasificar, sin > 0 {
                    Text("Además, un \(pct(sin))% se le escapa sin clasificar. No cuenta como "
                         + "fallo —no ensucia tus estadísticas— pero es un golpe que pierdes.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // La conclusión, en una frase. Es lo único que mucha gente va a leer.
                if let peor = informe.peorGolpe, let acierto = peor.aciertoEnTandas, acierto < 0.8 {
                    Divider().overlay(T.borde)
                    Label {
                        Text("Lo que peor va es \(nombre(peor.type)): \(pct(acierto))% de acierto"
                             + (peor.seConfundeCon.map { ", se confunde con \(nombre($0).lowercased())" } ?? "")
                             + ".")
                    } icon: {
                        Image(systemName: "wrench.and.screwdriver.fill")
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(T.rojo)
                }
            }
        }
    }

    // MARK: Golpe a golpe

    private func golpesCard(_ informe: InformeDePrecision) -> some View {
        PadelCard(title: "Golpe a golpe", icon: "list.bullet.clipboard") {
            VStack(spacing: 0) {
                ForEach(informe.golpes) { golpe in
                    fila(golpe)
                    if golpe.id != informe.golpes.last?.id {
                        Divider().overlay(T.borde).padding(.vertical, 2)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func fila(_ golpe: PrecisionDeGolpe) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Circle()
                    .fill(ColorDeGolpe.color(golpe.type))
                    .frame(width: 9, height: 9)
                Text(nombre(golpe.type))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(T.tinta)
                Spacer(minLength: 6)
                if let acierto = golpe.aciertoEnTandas, !golpe.faltanTandas {
                    Text("\(pct(acierto))%")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(color(acierto))
                } else {
                    Text("sin medir")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                }
            }

            if let acierto = golpe.aciertoEnTandas, !golpe.faltanTandas {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(T.borde)
                        Capsule()
                            .fill(color(acierto))
                            .frame(width: geo.size.width * CGFloat(min(max(acierto, 0.02), 1)))
                    }
                }
                .frame(height: 6)
            }

            Text(detalle(golpe))
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(T.tintaSuave)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }

    /// La línea que explica el número. Sin ella un 40% es un reproche; con ella es una
    /// instrucción: "tus víboras salen como smash 12 de 20 veces".
    private func detalle(_ golpe: PrecisionDeGolpe) -> String {
        var partes: [String] = []
        if golpe.faltanTandas {
            partes.append(golpe.enTandas == 0
                          ? "sin ninguna tanda grabada"
                          : "solo \(golpe.enTandas) golpes grabados, hacen falta \(PrecisionDeGolpe.minTandasParaJuzgar)")
        } else {
            partes.append("\(golpe.acertadosEnTandas) de \(golpe.enTandas) en tandas")
            if let con = golpe.seConfundeCon {
                partes.append("se confunde con \(nombre(con).lowercased()) \(golpe.vecesConfundido) veces")
            }
        }
        if let desvio = golpe.desvioEnPartidos, abs(desvio) >= 0.05 {
            partes.append(desvio > 0
                          ? "en partido cuenta un \(pct(desvio))% de más"
                          : "en partido se deja un \(pct(desvio))%")
        }
        return partes.joined(separator: " · ")
    }

    // MARK: Lo que falta por grabar

    private func pendientesCard(_ informe: InformeDePrecision) -> some View {
        PadelCard(title: "Lo que toca grabar", icon: "record.circle") {
            VStack(alignment: .leading, spacing: 10) {
                Text(informe.golpesSinTandas.map { nombre($0) }.joined(separator: " · "))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(T.tinta)
                    .fixedSize(horizontal: false, vertical: true)
                Text("De estos golpes no hay tandas suficientes para saber si el reloj los "
                     + "acierta. Hasta que las haya, su porcentaje no existe — que no es lo "
                     + "mismo que estar bien.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var vacioCard: some View {
        PadelCard {
            VStack(spacing: 10) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 32))
                    .foregroundStyle(T.tintaSuave)
                Text("Todavía no se puede medir")
                    .font(.padelTitle())
                    .foregroundStyle(T.tinta)
                Text("Hacen falta tandas etiquetadas, sesiones revisadas o las dos cosas. "
                     + "Sin verdad-terreno cualquier porcentaje sería inventado.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var metodoCard: some View {
        PadelCard(title: "De dónde sale", icon: "info.circle") {
            VStack(alignment: .leading, spacing: 8) {
                punto("Las tandas etiquetadas son la medida buena: se dice qué golpe va a "
                      + "ser antes de pegarlo, así que se sabe uno a uno si acertó.")
                punto("Las revisiones de partido («¿acertó el reloj?») solo dan recuentos: "
                      + "dicen si contó de más o de menos, no cuál falló.")
                punto("Los dos números van por separado a propósito. Mezclarlos daría uno "
                      + "más bonito y menos cierto.")
            }
        }
    }

    private func punto(_ texto: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(T.lima).frame(width: 5, height: 5).padding(.top, 5)
            Text(texto)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(T.tintaSuave)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Utilidades

    private func pct(_ fraccion: Float) -> Int { Int(abs(fraccion) * 100) }

    /// Verde / ámbar / rojo con los cortes puestos donde importan: por debajo del 70% el
    /// recuento de ese golpe no se puede enseñar como un dato, y hay que decirlo.
    private func color(_ acierto: Float?) -> Color {
        guard let acierto else { return T.tintaSuave }
        switch acierto {
        case ..<0.7: return T.rojo
        case ..<0.85: return .orange
        default: return T.verde
        }
    }

    private func nombre(_ tipo: ShotType) -> String { ShotBreakdownChart.etiqueta(tipo) }
}
