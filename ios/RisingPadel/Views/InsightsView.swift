import PadelCore
import SwiftUI

/// Las ideas de la sesión, agrupadas por familia.
///
/// Cada idea enseña **el dato que la sostiene** además del consejo: es lo que separa un
/// análisis de un horóscopo. La cifra de evidencia va debajo a propósito — una idea sobre
/// 200 golpeos y otra sobre 16 no merecen la misma confianza, y esconderlo sería vender
/// más certeza de la que hay.
struct InsightsCard: View {
    let session: PadelSession

    private var insights: [Insight] {
        InsightEngine().insights(for: session)
    }

    var body: some View {
        let all = insights
        if all.isEmpty {
            PadelCard(title: "Ideas de la sesión", icon: "sparkles") {
                Text("""
                    Con más golpeos aparecerán aquí las ideas: qué te funciona, qué te \
                    cuesta y qué entrenar. Hacen falta unos cuantos puntos para que una \
                    conclusión signifique algo.
                    """)
                    .font(.system(size: 12))
                    .foregroundStyle(T.tintaSuave)
            }
        } else {
            VStack(spacing: 12) {
                ForEach(InsightCategory.allCases, id: \.self) { category in
                    let group = all.filter { $0.category == category }
                    if !group.isEmpty {
                        categoryCard(category, insights: group)
                    }
                }
            }
        }
    }

    private func categoryCard(_ category: InsightCategory, insights: [Insight]) -> some View {
        PadelCard(title: category.title, icon: category.symbol) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(insights) { insight in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(insight.headline)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(T.tinta)

                        // El texto va entrecomillado y con barra lateral: se lee como lo
                        // que es, una lectura de tus datos, no una etiqueta de la app.
                        HStack(alignment: .top, spacing: 8) {
                            Capsule()
                                .fill(T.bola)
                                .frame(width: 3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(insight.detail)
                                    .font(.system(size: 13))
                                    .foregroundStyle(T.tinta)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("sobre \(insight.evidence) golpeos")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(T.tintaSuave)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
