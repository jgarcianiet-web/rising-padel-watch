import SwiftUI

/// La pantalla de análisis de pareja (§36.11): **"¿juego mejor con este?"**
///
/// El panel de temporada ya enseñaba el balance con cada compañero, pero un 60 % de
/// victorias con alguien no contesta nada por sí solo. Esta pantalla pone al lado lo que
/// pasa cuando juegas con cualquier otro, que es lo que convierte el número en respuesta.
///
/// Todo lo que no tiene muestra se calla, no se rellena con un cero: las tarjetas
/// aparecen y desaparecen según lo que `AnalisisDeParejas` haya podido medir. Por eso
/// casi todas son `@ViewBuilder` con un `if` delante en vez de una tarjeta fija con
/// guiones dentro.
struct ParejaView: View {
    @EnvironmentObject private var liga: LigaModel

    /// El compañero elegido. Nil = todavía no se ha tocado nada y se usa el primero.
    @State private var seleccion: String?

    /// Con quién abrir la pantalla, si se entra desde la ficha de un partido.
    private let inicial: String?

    init(inicial: String? = nil) {
        self.inicial = inicial
        _seleccion = State(initialValue: inicial)
    }

    var body: some View {
        // Con temporadas, la pareja es la de la temporada en curso; comparar contra
        // partidos de hace dos años mezclaría dos jugadores distintos (tú de entonces y
        // tú de ahora) en la misma media.
        let matches = liga.matchesTemporadaActual
        let companeros = AnalisisDeParejas.companeros(matches)
        let elegido = seleccion.flatMap { nombre in
            companeros.first { $0.lowercased() == nombre.lowercased() }
        } ?? companeros.first

        ScrollView {
            VStack(spacing: 12) {
                if companeros.isEmpty {
                    sinCompaneros
                } else {
                    selector(companeros, elegido: elegido)
                    if let elegido {
                        let analisis = AnalisisDeParejas.de(elegido, partidos: matches)
                        conjuntoCard(analisis)
                        comparacionCard(analisis)
                        repartoCard(analisis)
                        posicionCard(analisis)
                    }
                    rankingCard(matches)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(T.fondo)
        .navigationTitle("Mi pareja")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Selector

    private func selector(_ companeros: [String], elegido: String?) -> some View {
        PadelCard(title: "Compañero", icon: "person.2.fill") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(companeros, id: \.self) { nombre in
                        let activo = elegido == nombre
                        Button {
                            seleccion = nombre
                        } label: {
                            Text(nombre)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(activo ? .white : T.tinta)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(activo ? T.pista : T.pistaTinte, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var sinCompaneros: some View {
        PadelCard(title: "Mi pareja", icon: "person.2.fill") {
            Text("Todavía no hay ningún partido con compañero apuntado. Escribe con quién juegas al guardar el partido y aquí saldrá si juegas mejor con unos que con otros.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(T.tintaSuave)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Rendimiento conjunto

    private func conjuntoCard(_ analisis: AnalisisDePareja) -> some View {
        let r = analisis.juntos
        return PadelCard(title: "Con \(analisis.companero)", icon: "figure.2.arms.open") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    StatTile(label: "Partidos", value: "\(r.partidos)")
                    StatTile(
                        label: "Victorias",
                        value: r.pctVictorias.map { "\($0)%" } ?? "–",
                        tint: T.verde
                    )
                    StatTile(
                        label: "Tu nivel medio",
                        value: r.nivelMedio.map { String(format: "%.1f", $0) } ?? "–",
                        tint: T.pista
                    )
                }

                Text("\(r.victorias) ganados y \(r.derrotas) perdidos de \(r.conResultado) con resultado.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(T.tintaSuave)

                if !analisis.suficiente {
                    // El recuento sí se enseña —es un hecho— pero el porcentaje y la
                    // media se callan hasta que haya muestra. Decir cuánto falta es más
                    // útil que un guión sin explicación.
                    Text("Faltan \(analisis.partidosQueFaltan) partidos juntos para poder sacar porcentajes: con tres, ganar uno más cambia el resultado veinte puntos.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // La limitación que el documento de producto da por resuelta y aquí no lo
                // está: solo hay un reloj, el de quien usa la app.
                Text("Del rendimiento de \(analisis.companero) no hay dato: la app solo ve lo que mide tu reloj.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Con esa pareja contra con cualquier otra

    @ViewBuilder
    private func comparacionCard(_ analisis: AnalisisDePareja) -> some View {
        if let c = analisis.comparacion {
            PadelCard(title: "Con \(analisis.companero) y sin él", icon: "arrow.left.arrow.right") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(veredicto(c, nombre: analisis.companero))
                        .font(.padelTitle(15))
                        .foregroundStyle(colorVeredicto(c))
                        .fixedSize(horizontal: false, vertical: true)

                    filaComparada(
                        "Tu nivel medio",
                        con: c.con.nivelMedio.map { String(format: "%.1f", $0) },
                        sin: c.sin.nivelMedio.map { String(format: "%.1f", $0) },
                        delta: c.deltaNivel.map { String(format: "%+.1f", $0) },
                        mejora: c.deltaNivel.map { $0 > 0 }
                    )
                    filaComparada(
                        "Victorias",
                        con: c.con.pctVictorias.map { "\($0)%" },
                        sin: c.sin.pctVictorias.map { "\($0)%" },
                        delta: c.deltaPctVictorias.map { "\($0 > 0 ? "+" : "")\($0) pts" },
                        mejora: c.deltaPctVictorias.map { $0 > 0 }
                    )

                    Text("El veredicto lo decide el nivel y no las victorias: ganar depende también de quién estuviera enfrente, y de eso la app no sabe nada.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func filaComparada(
        _ etiqueta: String, con: String?, sin: String?, delta: String?, mejora: Bool?
    ) -> some View {
        HStack {
            Text(etiqueta)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(T.tinta)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(con ?? "–")
                .foregroundStyle(T.pista)
                .frame(width: 56, alignment: .trailing)
            Text(sin ?? "–")
                .foregroundStyle(T.tintaSuave)
                .frame(width: 56, alignment: .trailing)
            Text(delta ?? "–")
                .foregroundStyle(delta == nil ? T.tintaSuave : ((mejora ?? false) ? T.verde : T.rojo))
                .frame(width: 62, alignment: .trailing)
        }
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .monospacedDigit()
    }

    private func veredicto(_ c: ComparacionDePareja, nombre: String) -> String {
        switch c.veredicto {
        case .mejor: return "Juegas mejor con \(nombre)"
        case .igual: return "Con \(nombre) juegas igual que con el resto"
        case .peor: return "Con \(nombre) rindes por debajo de tu media"
        case nil: return "Todavía no se puede decir: falta nivel medido a alguno de los dos lados"
        }
    }

    private func colorVeredicto(_ c: ComparacionDePareja) -> Color {
        switch c.veredicto {
        case .mejor: return T.verde
        case .peor: return T.rojo
        default: return T.tintaSuave
        }
    }

    // MARK: Reparto de golpes

    @ViewBuilder
    private func repartoCard(_ analisis: AnalisisDePareja) -> some View {
        if !analisis.reparto.isEmpty {
            PadelCard(title: "Qué juegas con \(analisis.companero)", icon: "figure.tennis") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(analisis.reparto.prefix(6)) { golpe in
                        PadelBar(
                            label: etiquetaGolpe(golpe),
                            value: String(format: "%.0f/partido", golpe.porPartidoCon),
                            fraction: Float(golpe.cuotaCon),
                            color: colorReparto(golpe)
                        )
                    }
                    Text("La barra es qué parte de tus golpes es cada uno, no cuántos: con partidos más largos das más de todo, y eso no dice nada de la pareja.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// "Bandeja · +12 pts con ella". Sin comparación, solo el nombre: un "+0" ahí
    /// parecería un dato y sería la ausencia de uno.
    private func etiquetaGolpe(_ golpe: RepartoDeGolpe) -> String {
        guard let puntos = golpe.diferenciaEnPuntos, puntos != 0 else { return golpe.golpe }
        return "\(golpe.golpe) · \(puntos > 0 ? "+" : "")\(puntos) pts"
    }

    private func colorReparto(_ golpe: RepartoDeGolpe) -> Color {
        guard let puntos = golpe.diferenciaEnPuntos else { return T.pista }
        if puntos >= 5 { return T.lima }
        if puntos <= -5 { return T.rojo }
        return T.pista
    }

    // MARK: Equilibrio por posición

    @ViewBuilder
    private func posicionCard(_ analisis: AnalisisDePareja) -> some View {
        let p = analisis.posicion
        if let cuota = p.cuotaDerecha {
            PadelCard(title: "De qué lado juegas", icon: "arrow.left.and.right.square") {
                VStack(alignment: .leading, spacing: 10) {
                    PadelBar(
                        label: "Derecha (drive)",
                        value: "\(p.enDerecha) de \(p.partidos)",
                        fraction: Float(cuota),
                        color: T.pista
                    )
                    PadelBar(
                        label: "Revés",
                        value: "\(p.enReves) de \(p.partidos)",
                        fraction: Float(1 - cuota),
                        color: T.lima
                    )
                    Text(textoLado(p, nombre: analisis.companero))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(T.tinta)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func textoLado(_ p: EquilibrioDePosicion, nombre: String) -> String {
        switch p.ladoHabitual {
        case AnalisisDeParejas.derecha: return "Con \(nombre) tu sitio es la derecha."
        case AnalisisDeParejas.reves: return "Con \(nombre) tu sitio es el revés."
        default: return "Con \(nombre) os vais repartiendo los lados."
        }
    }

    // MARK: Mejor y peor compañero

    @ViewBuilder
    private func rankingCard(_ matches: [LigaMatch]) -> some View {
        let mejor = AnalisisDeParejas.mejorCompanero(matches)
        let peor = AnalisisDeParejas.peorCompanero(matches)
        if let mejor {
            PadelCard(title: "Con quién juegas mejor", icon: "trophy") {
                VStack(alignment: .leading, spacing: 10) {
                    filaDestacado(mejor, titulo: "Mejor", color: T.verde)
                    if let peor {
                        filaDestacado(peor, titulo: "Peor", color: T.rojo)
                    }
                    Text("Ordenado por tu nivel medio de sesión, con \(AnalisisDeParejas.minimoPartidos) partidos mínimo. Quien no llegue a esa cuenta no sale.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func filaDestacado(_ destacado: CompaneroDestacado, titulo: String, color: Color) -> some View {
        HStack(spacing: 10) {
            SectionLabel(titulo)
                .frame(width: 46, alignment: .leading)
            Text(destacado.nombre)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(T.tinta)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(destacado.rendimiento.partidos) PJ")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(T.tintaSuave)
            Text(destacado.rendimiento.nivelMedio.map { String(format: "%.1f", $0) } ?? "–")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .frame(width: 44, alignment: .trailing)
        }
    }
}
