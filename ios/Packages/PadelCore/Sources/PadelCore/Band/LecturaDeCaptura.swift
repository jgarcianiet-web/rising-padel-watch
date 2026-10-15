import Foundation

/// Leer los números de una **captura de pantalla** de otra app de pádel.
///
/// ## Por qué esto existe
///
/// La Padel Band mide el nivel de cada golpe y cuántos hubo, y su app no tiene exportación
/// ni API: lo que el jugador ve en pantalla es todo lo que hay. Pero es **su** dato, de su
/// pulsera, en su móvil, y el único camino que queda para meterlo en su propia liga es
/// leerlo de la imagen.
///
/// ## La regla que gobierna todo el fichero: **nada se da por bueno en silencio**
///
/// Un número mal leído entra en la liga con la misma pinta que uno medido. Así que esto
/// **no devuelve una sesión**: devuelve `CapturaLeida`, candidatos donde cada número viene
/// con **el texto exacto del que salió**, para enseñarlo al lado de la imagen y que el
/// jugador confirme. Lo que no se deja leer no se rellena con un cero: se queda fuera.
///
/// ## Por qué hace falta saber DÓNDE está cada texto
///
/// La primera versión trabajaba con líneas y contra las capturas de verdad no valía. Una
/// app de móvil no apila rótulo y valor en una columna: los pone en rejilla.
///
/// - `Num. golpes` y `Calidad` van **uno al lado del otro**, y debajo `11` y `2.99`.
/// - En la tarjeta de actividad el número va **encima** del rótulo: `898` / `K Cal`.
/// - En el radar de calidad, igual: `3.61` encima de `VOLEA`.
///
/// Por eso la entrada es `Trozo`, con posición. Se agrupan en filas y el valor de un
/// rótulo se busca **a su derecha en la misma fila, debajo en su columna, o encima en su
/// columna**, en ese orden.
///
/// Espejo de `LecturaDeCaptura` en el core Kotlin, con los tests allí.
public enum LecturaDeCaptura {

    /// Un trozo de texto reconocido, con dónde está.
    ///
    /// `x` e `y` son el centro del trozo en coordenadas normalizadas 0-1, con **el origen
    /// arriba a la izquierda**: `y = 0` es el borde de arriba. Vision las da con el origen
    /// abajo y hay que voltearlas una sola vez, al reconocer — tener dos convenios de `y`
    /// dando vueltas es el fallo que deja la lectura del revés y nadie sabe dónde.
    public struct Trozo: Equatable, Sendable {
        public let texto: String
        public let x: Double
        public let y: Double

        public init(texto: String, x: Double, y: Double) {
            self.texto = texto
            self.x = x
            self.y = y
        }
    }

    /// Un número leído, con el texto del que salió para poder enseñarlo.
    public struct Dato: Equatable, Sendable {
        public let valor: Double
        public let origen: String

        public init(valor: Double, origen: String) {
            self.valor = valor
            self.origen = origen
        }
    }

    /// Un golpe de la captura.
    ///
    /// El `nombre` es lo que ponía en pantalla y es lo que se guarda, porque la liga
    /// guarda los golpes **por nombre** y no por enum. El `golpe` es la correspondencia
    /// con nuestro repertorio cuando la hay, y es nil cuando la captura da el golpe **sin
    /// lado**: la pantalla de volumen dice "Volea 175" sin separar derecha de revés, y
    /// partir ese 175 por la mitad sería inventarse dos números.
    public struct GolpeLeido: Equatable, Sendable, Identifiable {
        public let nombre: String
        public let golpe: GolpeVisible?
        public let nota: Dato?
        public let cantidad: Dato?

        public var id: String { nombre }

        public init(nombre: String, golpe: GolpeVisible?, nota: Dato? = nil, cantidad: Dato? = nil) {
            self.nombre = nombre
            self.golpe = golpe
            self.nota = nota
            self.cantidad = cantidad
        }
    }

    /// Todo lo que se pudo leer. **Todos los campos son opcionales**: la pantalla de
    /// resumen no trae lo mismo que la de un golpe, y rellenar lo que falta sería inventar.
    public struct CapturaLeida: Equatable, Sendable {
        public let nivelSesion: Dato?
        /// La "Calidad Media Jugador" de la gráfica de progreso.
        public let mediaDelJugador: Dato?
        public let totalGolpes: Dato?
        public let duracionMin: Dato?
        public let pulsoMedio: Dato?
        public let pulsoMax: Dato?
        public let calorias: Dato?
        public let pasos: Dato?
        /// El golpe que la app destaca como mejor ("Mejor golpe: REMATE").
        public let mejorGolpe: String?
        public let golpes: [GolpeLeido]
        /// Los textos que no se entendieron, para poder enseñarlos.
        public let sinEntender: [String]

        public var vacia: Bool {
            nivelSesion == nil && mediaDelJugador == nil && totalGolpes == nil
                && duracionMin == nil && pulsoMedio == nil && pulsoMax == nil
                && calorias == nil && pasos == nil && mejorGolpe == nil && golpes.isEmpty
        }
    }

    // ─── Rótulos ───
    //
    // Los de la Padel Band están sacados de capturas reales (oct 2026); los demás son
    // variantes razonables de otras apps.

    private static let nivelClaves = ["nivel sesion", "nivel de la sesion", "nivel", "level"]
    private static let mediaClaves = ["calidad media jugador", "media jugador"]
    /// Incluye "golpes" a secas porque la tarjeta de actividad lo rotula así, pero se usa
    /// **excluyendo** el "Num. golpes" de cada golpe: sin eso, el recuento de las bandejas
    /// entraría como el total del partido.
    private static let totalClaves = ["golpes totales", "total golpes", "golpeos", "shots", "golpes"]
    private static let duracionClaves = ["tiempo", "duracion", "duration"]
    private static let pulsoMedioClaves = ["pulso medio", "fc media", "media ppm", "pulso med"]
    private static let pulsoMaxClaves = ["pulso max", "fc max", "max ppm", "pulso maximo"]
    private static let caloriasClaves = ["k cal", "kcal", "calorias"]
    private static let pasosClaves = ["pasos", "steps"]
    private static let mejorGolpeClaves = ["mejor golpe"]
    private static let numGolpesClaves = ["num golpes", "numero de golpes"]
    private static let calidadClaves = ["calidad"]

    /// Dos filas se consideran la misma si sus centros caen dentro de esto.
    private static let toleranciaFila = 0.012
    /// Cuánto se puede desviar en horizontal un valor de su rótulo, en otra fila.
    private static let toleranciaColumna = 0.30

    /// Lee una captura de una sola columna, sin posiciones.
    public static func leer(_ lineas: [String]) -> CapturaLeida {
        leerTrozos(lineas.enumerated().map { Trozo(texto: $1, x: 0, y: Double($0)) })
    }

    /// Lee los trozos de texto reconocidos, con sus posiciones.
    public static func leerTrozos(_ trozos: [Trozo]) -> CapturaLeida {
        let limpios = trozos
            .map { Trozo(texto: $0.texto.trimmingCharacters(in: .whitespacesAndNewlines), x: $0.x, y: $0.y) }
            .filter { !$0.texto.isEmpty }
            .sorted { $0.y != $1.y ? $0.y < $1.y : $0.x < $1.x }
        guard !limpios.isEmpty else {
            return CapturaLeida(
                nivelSesion: nil, mediaDelJugador: nil, totalGolpes: nil, duracionMin: nil,
                pulsoMedio: nil, pulsoMax: nil, calorias: nil, pasos: nil,
                mejorGolpe: nil, golpes: [], sinEntender: []
            )
        }

        let contexto = Contexto(limpios)

        // El orden NO es arbitrario: los rótulos más específicos primero. Buscando
        // "calidad" antes que "calidad media jugador", la media se consume como si fuera
        // la calidad de un golpe y ya no se puede recuperar.
        let media = contexto.buscar(mediaClaves, maximo: 10)
        let nivel = contexto.buscar(nivelClaves, maximo: 10)
        let pulsoMax = contexto.buscar(pulsoMaxClaves, maximo: 250)
        let pulsoMedio = contexto.buscar(pulsoMedioClaves, maximo: 250)
        let calorias = contexto.buscar(caloriasClaves, maximo: 10_000)
        let pasos = contexto.buscar(pasosClaves, maximo: 100_000)
        let duracion = contexto.buscar(duracionClaves, maximo: 600, enMinutos: true)
        let total = contexto.buscar(totalClaves, maximo: 5_000, excluyendo: numGolpesClaves)
        let mejorGolpe = contexto.buscarTexto(mejorGolpeClaves)

        let golpes = leerGolpes(contexto)

        return CapturaLeida(
            nivelSesion: nivel,
            mediaDelJugador: media,
            totalGolpes: total,
            duracionMin: duracion,
            pulsoMedio: pulsoMedio,
            pulsoMax: pulsoMax,
            calorias: calorias,
            pasos: pasos,
            mejorGolpe: mejorGolpe,
            golpes: golpes,
            sinEntender: contexto.sinUsar()
        )
    }

    /// El estado de una lectura: lo que hay y lo que ya se ha consumido.
    private final class Contexto {
        let trozos: [Trozo]
        let normalizados: [String]
        let filas: [[Int]]
        let filaDe: [Int]
        var usados = Set<Int>()

        init(_ trozos: [Trozo]) {
            self.trozos = trozos
            self.normalizados = trozos.map { normalizar($0.texto) }

            // Agrupar en filas por altura, cada fila de izquierda a derecha.
            var filas: [[Int]] = []
            var alturaActual = -Double.greatestFiniteMagnitude
            for i in trozos.indices {
                if filas.isEmpty || abs(trozos[i].y - alturaActual) > toleranciaFila {
                    filas.append([i])
                    alturaActual = trozos[i].y
                } else {
                    filas[filas.count - 1].append(i)
                }
            }
            self.filas = filas.map { $0.sorted { trozos[$0].x < trozos[$1].x } }

            var filaDe = [Int](repeating: 0, count: trozos.count)
            for (indice, fila) in self.filas.enumerated() { for i in fila { filaDe[i] = indice } }
            self.filaDe = filaDe
        }

        func sinUsar() -> [String] {
            trozos.indices.filter { !usados.contains($0) }.map { trozos[$0].texto }
        }

        func etiquetas(_ claves: [String], excluyendo: [String] = []) -> [Int] {
            trozos.indices.filter { i in
                !usados.contains(i)
                    && claves.contains { normalizados[i].contains($0) }
                    && !excluyendo.contains { normalizados[i].contains($0) }
            }
        }

        /// El valor de un rótulo: dentro del propio rótulo, a su derecha en la misma fila,
        /// debajo en su columna, o encima en su columna — en ese orden.
        ///
        /// Lo de mirar **encima** no es simetría gratuita: en las tarjetas de actividad el
        /// número va arriba y el rótulo debajo (`898` / `K Cal`), y sin eso no se lee
        /// ninguna de las cuatro.
        func buscar(
            _ claves: [String],
            maximo: Double? = nil,
            enMinutos: Bool = false,
            desde: Int = 0,
            hasta: Int = .max,
            excluyendo: [String] = []
        ) -> Dato? {
            for i in etiquetas(claves, excluyendo: excluyendo) {
                let fila = filaDe[i]
                guard fila >= desde, fila <= hasta else { continue }
                guard let (dato, indice) = valorPara(i, maximo: maximo, enMinutos: enMinutos) else {
                    continue
                }
                usados.insert(i)
                usados.insert(indice)
                return dato
            }
            return nil
        }

        /// Como `buscar` pero el valor es texto ("Mejor golpe" → "REMATE").
        func buscarTexto(_ claves: [String]) -> String? {
            for i in etiquetas(claves) {
                let fila = filas[filaDe[i]]
                guard let elegido = fila.first(where: {
                    $0 > i && !usados.contains($0) && numerosDe(trozos[$0].texto).isEmpty
                }) else { continue }
                usados.insert(i)
                usados.insert(elegido)
                return trozos[elegido].texto
            }
            return nil
        }

        private func valorPara(
            _ etiqueta: Int, maximo: Double?, enMinutos: Bool
        ) -> (Dato, Int)? {
            func leerDe(_ indice: Int) -> Dato? {
                let texto = trozos[indice].texto
                guard let valor = enMinutos ? minutosDe(texto) : numeroDe(texto) else { return nil }
                if let maximo, valor > maximo { return nil }
                return Dato(valor: valor, origen: texto)
            }

            if let dato = leerDe(etiqueta) { return (dato, etiqueta) }

            let fila = filaDe[etiqueta]
            for j in filas[fila] where j > etiqueta && !usados.contains(j) {
                if let dato = leerDe(j) { return (dato, j) }
            }
            for otra in [fila + 1, fila - 1] {
                guard filas.indices.contains(otra) else { continue }
                let candidato = filas[otra]
                    .filter { !usados.contains($0) && abs(trozos[$0].x - trozos[etiqueta].x) <= toleranciaColumna }
                    .min { abs(trozos[$0].x - trozos[etiqueta].x) < abs(trozos[$1].x - trozos[etiqueta].x) }
                guard let candidato, let dato = leerDe(candidato) else { continue }
                return (dato, candidato)
            }
            return nil
        }
    }

    /// Los golpes de la captura.
    ///
    /// Tres maquetaciones, y las tres salen en las capturas de verdad: tarjeta de un golpe
    /// (nombre arriba, `Num. golpes` y `Calidad` debajo), lista de volumen (nombre y
    /// número en la misma fila) y radar de calidad (número encima del nombre).
    ///
    /// **Cada nombre acota hasta dónde se busca su valor**, y eso resuelve un fallo real:
    /// en la pantalla del globo el título pone "Globo" y debajo vienen "Globo Rev." y
    /// "Globo Dcha."; sin acotar, el "Globo" de arriba se habría quedado con los números
    /// de la primera tarjeta.
    private static func leerGolpes(_ contexto: Contexto) -> [GolpeLeido] {
        let apariciones: [(Int, Nombrado)] = contexto.trozos.indices.compactMap { i in
            nombreDeGolpe(contexto.normalizados[i]).map { (i, $0) }
        }
        guard !apariciones.isEmpty else { return [] }

        var encontrados: [String: GolpeLeido] = [:]
        var orden: [String] = []
        for (posicion, aparicion) in apariciones.enumerated() {
            let (indice, nombrado) = aparicion
            let filaInicio = contexto.filaDe[indice]
            let filaFin = posicion + 1 < apariciones.count
                ? contexto.filaDe[apariciones[posicion + 1].0] - 1
                : contexto.filas.count - 1

            let cantidad = contexto.buscar(
                numGolpesClaves, maximo: 5_000, desde: filaInicio, hasta: filaFin
            )
            let nota = contexto.buscar(
                calidadClaves, maximo: 10, desde: filaInicio, hasta: filaFin
            )
            var notaFinal = nota
            var cantidadFinal = cantidad
            if nota == nil, cantidad == nil {
                let (sueltaNota, sueltaCantidad) = sueltos(contexto, indice)
                notaFinal = sueltaNota
                cantidadFinal = sueltaCantidad
            }
            guard notaFinal != nil || cantidadFinal != nil else { continue }
            contexto.usados.insert(indice)
            // El primero gana: una captura puede repetir el nombre en un título y en una
            // leyenda, y lo de arriba es lo que el jugador está mirando.
            if encontrados[nombrado.nombre] == nil {
                encontrados[nombrado.nombre] = GolpeLeido(
                    nombre: nombrado.nombre,
                    golpe: nombrado.golpe,
                    nota: notaFinal,
                    cantidad: cantidadFinal
                )
                orden.append(nombrado.nombre)
            }
        }

        // En el orden del repertorio los conocidos y detrás los agregados, para que la
        // pantalla de confirmación se lea siempre igual venga la captura como venga.
        let conocidos = GolpeVisible.allCases.compactMap { visible in
            orden.compactMap { encontrados[$0] }.first { $0.golpe == visible }
        }
        let agregados = orden.compactMap { encontrados[$0] }.filter { $0.golpe == nil }
        return conocidos + agregados
    }

    /// El número que acompaña a un nombre sin rótulo: a su derecha en la misma fila (lista
    /// de volumen) o justo encima (radar de calidad).
    ///
    /// Con decimales es nota y entero es recuento, porque una calidad lleva decimales y un
    /// recuento no. Es una heurística, y por eso el número viaja con su texto.
    private static func sueltos(_ contexto: Contexto, _ indice: Int) -> (Dato?, Dato?) {
        let propios = numerosDe(contexto.trozos[indice].texto)
        let texto = contexto.trozos[indice].texto
        if propios.count >= 2 {
            return (Dato(valor: propios[0], origen: texto), Dato(valor: propios[1], origen: texto))
        }
        if propios.count == 1 {
            let dato = Dato(valor: propios[0], origen: texto)
            return tieneDecimales(propios[0]) ? (dato, nil) : (nil, dato)
        }

        let fila = contexto.filaDe[indice]
        var candidatos = contexto.filas[fila].filter { $0 > indice && !contexto.usados.contains($0) }
        if contexto.filas.indices.contains(fila - 1) {
            let arriba = contexto.filas[fila - 1]
                .filter {
                    !contexto.usados.contains($0)
                        && abs(contexto.trozos[$0].x - contexto.trozos[indice].x) <= toleranciaColumna
                }
                .min {
                    abs(contexto.trozos[$0].x - contexto.trozos[indice].x)
                        < abs(contexto.trozos[$1].x - contexto.trozos[indice].x)
                }
            if let arriba { candidatos.append(arriba) }
        }

        for j in candidatos {
            guard let numero = numeroDe(contexto.trozos[j].texto) else { continue }
            contexto.usados.insert(j)
            let dato = Dato(valor: numero, origen: contexto.trozos[j].texto)
            return tieneDecimales(numero) ? (dato, nil) : (nil, dato)
        }
        return (nil, nil)
    }

    private static func tieneDecimales(_ valor: Double) -> Bool {
        valor != valor.rounded(.towardZero)
    }

    /// Un nombre de golpe reconocido, con su correspondencia en nuestro repertorio.
    public struct Nombrado: Equatable, Sendable {
        public let nombre: String
        public let golpe: GolpeVisible?
    }

    /// Cómo puede estar escrito cada golpe, **todo en una lista y ordenado de más largo a
    /// más corto**.
    ///
    /// Las dos cosas son necesarias y la segunda no es evidente. "Volea de revés" contiene
    /// "revés", así que el patrón largo va antes — pero además las variantes abreviadas,
    /// que son las que usa la app de verdad ("Volea Rev.", "Globo Dcha."), tienen que
    /// competir **en la misma pasada**: si se dejan para un segundo intento, "volea rev"
    /// ya habrá casado con "reves" y el jugador vería su volea de revés contada como
    /// revés, que es otro golpe. Pasó, y lo pilló un test.
    ///
    /// "Volea" y "Globo" a secas son **agregados**: la pantalla de volumen no separa
    /// lados. Van los últimos, así que solo ganan cuando no hay nada más específico.
    private static let patrones: [(String, Nombrado)] = {
        var salida: [(String, Nombrado)] = []
        func añadir(_ texto: String, _ nombre: String, _ golpe: GolpeVisible?) {
            salida.append((normalizar(texto), Nombrado(nombre: nombre, golpe: golpe)))
        }
        for golpe in GolpeVisible.allCases {
            añadir(golpe.etiqueta, golpe.etiqueta, golpe)
            let sinPreposicion = golpe.etiqueta.replacingOccurrences(of: " de ", with: " ")
            if sinPreposicion != golpe.etiqueta { añadir(sinPreposicion, golpe.etiqueta, golpe) }
        }
        añadir("volea rev", "Volea de revés", .voleaReves)
        añadir("volea dcha", "Volea de derecha", .voleaDerecha)
        añadir("globo rev", "Globo de revés", .globoReves)
        añadir("globo dcha", "Globo de derecha", .globoDerecha)
        añadir("volea", "Volea", nil)
        añadir("globo", "Globo", nil)
        return salida.sorted { $0.0.count > $1.0.count }
    }()

    /// El golpe que nombra este texto ya normalizado, o nil.
    public static func nombreDeGolpe(_ normalizado: String) -> Nombrado? {
        patrones.first { normalizado.contains($0.0) }?.1
    }

    /// El golpe del repertorio que nombra este texto, o nil.
    public static func golpeDe(_ normalizado: String) -> GolpeVisible? {
        nombreDeGolpe(normalizado)?.golpe
    }

    /// Minúsculas, sin acentos, sin puntos y con un solo espacio.
    ///
    /// Los puntos fuera porque la app abrevia con ellos —"Rev.", "Dcha.", "Num. golpes"—
    /// y un patrón con punto deja de valer en cuanto otra app escriba lo mismo sin él. No
    /// afecta a los números: se sacan siempre del texto original.
    public static func normalizar(_ texto: String) -> String {
        let sinAcentos = texto.lowercased()
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "es"))
            .replacingOccurrences(of: ".", with: " ")
        // Por `whitespacesAndNewlines` y no solo por el espacio: el reconocedor devuelve
        // tabulaciones cuando la captura tiene columnas, y el espejo Kotlin colapsa `\s+`.
        return sinAcentos.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// El primer número de un texto, o nil.
    public static func numeroDe(_ texto: String) -> Double? { numerosDe(texto).first }

    /// Todos los números de un texto, en orden.
    ///
    /// **La coma es decimal**: "3,5" es tres y medio y no dos números. Un "3,5/7" da solo
    /// el 3,5 — el 7 es la escala, no un dato. Y un texto con forma de reloj ("01:39:46")
    /// no da números sueltos: eso lo lee `minutosDe`, porque leer el "01" como si fuera un
    /// dato daría un partido de un minuto.
    public static func numerosDe(_ texto: String) -> [Double] {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        if esReloj(limpio) { return [] }
        let sinEscala = limpio.replacingOccurrences(
            of: "/\\s*\\d+([.,]\\d+)?", with: "", options: .regularExpression
        )
        guard let regex = try? NSRegularExpression(pattern: "-?\\d+(?:[.,]\\d+)?") else { return [] }
        let rango = NSRange(sinEscala.startIndex..., in: sinEscala)
        return regex.matches(in: sinEscala, range: rango).compactMap { match in
            guard let r = Range(match.range, in: sinEscala) else { return nil }
            let texto = String(sinEscala[r]).replacingOccurrences(of: ",", with: ".")
            guard let valor = Double(texto), valor >= 0 else { return nil }
            return valor
        }
    }

    private static func esReloj(_ texto: String) -> Bool {
        texto.range(of: "^\\d{1,2}:\\d{2}:\\d{2}$", options: .regularExpression) != nil
    }

    /// Minutos a partir de un texto de duración.
    ///
    /// La Padel Band escribe el tiempo como **`01:39:46`**, y eso no es un número: leído
    /// con el lector normal daría "1" y el partido entraría durando un minuto. Aquí se
    /// convierte a 99,8 minutos. También vale "92 min" y un número suelto.
    public static func minutosDe(_ texto: String) -> Double? {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        if esReloj(limpio) {
            let partes = limpio.split(separator: ":").compactMap { Int($0) }
            if partes.count == 3 {
                return Double(partes[0]) * 60 + Double(partes[1]) + Double(partes[2]) / 60
            }
        }
        return numeroDe(limpio)
    }
}
