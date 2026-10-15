import Foundation

/// Leer los números de una **captura de pantalla** de otra app de pádel.
///
/// ## Por qué esto existe
///
/// La Padel Band mide el nivel de cada golpe y cuántos hubo, y su app no tiene
/// exportación ni API: lo que el jugador ve en pantalla es todo lo que hay. Pero es **su**
/// dato, de su pulsera, en su móvil, y el único camino que queda para meterlo en su propia
/// liga es leerlo de la imagen. El iPhone sabe reconocer texto en una foto sin salir del
/// dispositivo (`VNRecognizeTextRequest`); este fichero es lo que pasa de ese montón de
/// líneas de texto a números con nombre.
///
/// ## La regla que gobierna todo el fichero: **nada se da por bueno en silencio**
///
/// Un número mal leído de una captura es peor que no tener el dato, porque entra en la
/// liga con la misma pinta que uno medido. Un 3,5 que era un 8,5, un "128 golpes" que era
/// "12,8 golpes/min", y de ahí sale una curva de evolución falsa que nadie va a cuestionar
/// meses después.
///
/// Así que esto **no devuelve una sesión**: devuelve `CapturaLeida`, una lista de
/// candidatos donde cada número viene con **la línea de texto exacta de la que salió**. La
/// pantalla los enseña al lado de la imagen y el jugador confirma o corrige antes de que
/// nada se guarde. Lo que no se deja leer no se rellena con un cero: se queda fuera.
///
/// ## Y lo que no se puede arreglar leyendo mejor
///
/// **El nivel de la Band y el del reloj no son la misma escala.** Las dos pueden decir
/// "3,5" sobre el mismo partido y no significar lo mismo. Por eso cada partido guarda de
/// dónde salió su nivel (`LigaMatch.fuente`), y las curvas no mezclan fuentes sin decirlo.
/// Leer la captura con precisión perfecta no haría comparables los dos números.
///
/// Espejo de `LecturaDeCaptura` en el core Kotlin, con los tests allí.
public enum LecturaDeCaptura {

    /// Un número leído, con la línea de la que salió para poder enseñarla.
    public struct Dato: Equatable, Sendable {
        public let valor: Double
        /// La línea de texto reconocida tal cual. Es lo que se le enseña al jugador.
        public let origen: String

        public init(valor: Double, origen: String) {
            self.valor = valor
            self.origen = origen
        }
    }

    /// La nota y/o el recuento de un golpe concreto.
    public struct GolpeLeido: Equatable, Sendable, Identifiable {
        public let golpe: GolpeVisible
        public let nota: Dato?
        public let cantidad: Dato?

        public var id: String { golpe.etiqueta }

        public init(golpe: GolpeVisible, nota: Dato? = nil, cantidad: Dato? = nil) {
            self.golpe = golpe
            self.nota = nota
            self.cantidad = cantidad
        }
    }

    /// Todo lo que se pudo leer de una captura. **Todos los campos son opcionales**: una
    /// captura de la pantalla de resumen no trae lo mismo que una del detalle por golpe, y
    /// rellenar lo que falta sería inventar.
    public struct CapturaLeida: Equatable, Sendable {
        public let nivelSesion: Dato?
        public let totalGolpes: Dato?
        public let duracionMin: Dato?
        public let pulsoMedio: Dato?
        public let pulsoMax: Dato?
        public let calorias: Dato?
        public let golpes: [GolpeLeido]
        /// Las líneas que no se entendieron. Se guardan para poder enseñarlas: si falta
        /// algo que el jugador sí ve en su captura, aquí está por qué.
        public let sinEntender: [String]

        /// Si no se ha podido leer ni un solo número, no hay nada que confirmar.
        public var vacia: Bool {
            nivelSesion == nil && totalGolpes == nil && duracionMin == nil
                && pulsoMedio == nil && pulsoMax == nil && calorias == nil && golpes.isEmpty
        }
    }

    // ─── Palabras que buscamos ───
    //
    // Varias por campo y en singular y plural porque no se sabe cómo lo escribe cada app,
    // ni cómo lo escribirá la siguiente versión. Son las etiquetas que de verdad aparecen
    // en una app de pádel; cuando aparezca otra se añade aquí y nada más.

    private static let nivelClaves = ["nivel", "level", "valoracion", "puntuacion", "score"]
    private static let totalClaves = ["golpes", "golpeos", "shots", "impactos", "total"]
    private static let duracionClaves = ["duracion", "tiempo", "duration"]
    private static let pulsoMedioClaves = ["pulso medio", "fc media", "media ppm", "pulso med"]
    private static let pulsoMaxClaves = ["pulso max", "fc max", "max ppm", "pulso maximo"]
    private static let caloriasClaves = ["calorias", "kcal", "cal"]

    /// Lee las líneas que devolvió el reconocedor de texto.
    ///
    /// Las líneas llegan **en orden de lectura** (arriba abajo) y ese orden importa: en
    /// casi todas las apps el rótulo y su número no están en la misma línea, sino uno
    /// encima del otro. Por eso se busca el número en la propia línea y, si no está, en la
    /// siguiente y en la anterior — y nunca más lejos, porque a dos líneas de distancia ya
    /// no se sabe de quién es el número.
    public static func leer(_ lineas: [String]) -> CapturaLeida {
        let limpias = lineas.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let normalizadas = limpias.map(normalizar)
        var usadas = Set<Int>()

        func buscar(_ claves: [String], maximo: Double? = nil) -> Dato? {
            for i in limpias.indices where !usadas.contains(i) {
                let linea = normalizadas[i]
                guard claves.contains(where: { linea.contains($0) }) else { continue }
                // En la línea del rótulo, en la de abajo, y en la de arriba. Ese orden:
                // el número suele ir después del rótulo o justo debajo.
                for j in [i, i + 1, i - 1] {
                    guard limpias.indices.contains(j), !usadas.contains(j) else { continue }
                    guard let numero = numeroDe(limpias[j]) else { continue }
                    if let maximo, numero > maximo { continue }
                    usadas.insert(i)
                    usadas.insert(j)
                    return Dato(valor: numero, origen: limpias[j])
                }
            }
            return nil
        }

        // El orden de búsqueda NO es arbitrario: los rótulos más específicos primero. Si
        // se buscara "pulso" antes que "pulso máximo", la línea del máximo se consumiría
        // como si fuera la media — y una vez consumida ya no se puede recuperar.
        let pulsoMax = buscar(pulsoMaxClaves, maximo: 250)
        let pulsoMedio = buscar(pulsoMedioClaves, maximo: 250)
        let calorias = buscar(caloriasClaves, maximo: 5_000)
        let duracion = buscar(duracionClaves, maximo: 600)
        // El nivel va limitado a 10: en estas apps es 1-7 o 1-10, así que un "3500" en la
        // línea del nivel es que se leyó otra cosa. Mejor no traer el dato que traerlo mal.
        let nivel = buscar(nivelClaves, maximo: 10)
        let total = buscar(totalClaves, maximo: 2_000)

        let golpes = leerGolpes(limpias, normalizadas, &usadas)

        return CapturaLeida(
            nivelSesion: nivel,
            totalGolpes: total,
            duracionMin: duracion,
            pulsoMedio: pulsoMedio,
            pulsoMax: pulsoMax,
            calorias: calorias,
            golpes: golpes,
            sinEntender: limpias.indices.filter { !usadas.contains($0) }.map { limpias[$0] }
        )
    }

    /// Las líneas que nombran un golpe del repertorio, con los números que las acompañan.
    ///
    /// Cuando una línea trae **dos** números —"Bandeja 3,5 · 24"— se interpreta que el
    /// primero es la nota y el segundo el recuento, porque una nota lleva decimales y un
    /// recuento no. Si solo hay uno, decide la forma: con decimales es nota; entero es
    /// recuento. Es una heurística y por eso el número viaja con su línea: si acierta, el
    /// jugador confirma de un toque, y si no, lo ve y lo corrige.
    private static func leerGolpes(
        _ limpias: [String], _ normalizadas: [String], _ usadas: inout Set<Int>
    ) -> [GolpeLeido] {
        var encontrados: [GolpeVisible: GolpeLeido] = [:]
        for i in limpias.indices where !usadas.contains(i) {
            guard let golpe = golpeDe(normalizadas[i]) else { continue }
            // La propia línea y la de abajo: el nombre del golpe y su número a veces van
            // en dos líneas, como los rótulos.
            var numeros = numerosDe(limpias[i])
            if numeros.isEmpty, limpias.indices.contains(i + 1), !usadas.contains(i + 1) {
                numeros = numerosDe(limpias[i + 1])
                if !numeros.isEmpty { usadas.insert(i + 1) }
            }
            guard !numeros.isEmpty else { continue }
            usadas.insert(i)

            let nota: Dato?
            let cantidad: Dato?
            if numeros.count >= 2 {
                nota = Dato(valor: numeros[0], origen: limpias[i])
                cantidad = Dato(valor: numeros[1], origen: limpias[i])
            } else if tieneDecimales(numeros[0]) {
                nota = Dato(valor: numeros[0], origen: limpias[i])
                cantidad = nil
            } else {
                nota = nil
                cantidad = Dato(valor: numeros[0], origen: limpias[i])
            }
            // El primero gana: una captura larga puede repetir el nombre del golpe en una
            // leyenda o en un pie, y lo de arriba es lo que el jugador está mirando.
            if encontrados[golpe] == nil {
                encontrados[golpe] = GolpeLeido(golpe: golpe, nota: nota, cantidad: cantidad)
            }
        }
        // En el orden del repertorio y no en el de la captura: así la pantalla de
        // confirmación se lee siempre igual, venga la captura como venga.
        return GolpeVisible.allCases.compactMap { encontrados[$0] }
    }

    /// Un nivel plausible tiene decimales; un recuento de golpes, no.
    private static func tieneDecimales(_ valor: Double) -> Bool {
        valor != valor.rounded(.towardZero)
    }

    /// Cómo puede estar escrito cada golpe, **todo en una lista y ordenado de más largo a
    /// más corto**.
    ///
    /// Las dos cosas son necesarias y la segunda no es evidente. "Volea de revés" contiene
    /// "revés", así que el patrón largo tiene que probarse antes — pero además la variante
    /// sin preposición ("volea revés", que es como lo escribe media aplicación) tiene que
    /// competir **en la misma pasada**: si se deja para un segundo intento, "volea revés"
    /// ya habrá casado con "revés" y el jugador verá su volea de revés contada como revés,
    /// que es otro golpe. Pasó, y lo pilló un test.
    private static let patrones: [(String, GolpeVisible)] = {
        var salida: [(String, GolpeVisible)] = []
        for golpe in GolpeVisible.allCases {
            let completo = normalizar(golpe.etiqueta)
            let sinPreposicion = completo.replacingOccurrences(of: " de ", with: " ")
            salida.append((completo, golpe))
            if sinPreposicion != completo { salida.append((sinPreposicion, golpe)) }
        }
        return salida.sorted { $0.0.count > $1.0.count }
    }()

    /// El golpe del repertorio que nombra esta línea, o nil.
    public static func golpeDe(_ lineaNormalizada: String) -> GolpeVisible? {
        patrones.first { lineaNormalizada.contains($0.0) }?.1
    }

    /// Minúsculas, sin acentos y con un solo espacio: así "Revés" y "REVES" son lo mismo.
    public static func normalizar(_ texto: String) -> String {
        let sinAcentos = texto.lowercased()
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "es"))
        // Por `whitespacesAndNewlines` y no solo por el espacio: el reconocedor de texto
        // devuelve tabulaciones y saltos cuando la captura tiene columnas, y el espejo
        // Kotlin colapsa `\s+`. Dos normalizaciones distintas darían dos lecturas
        // distintas de la misma captura según el core, que es lo que no puede pasar.
        return sinAcentos.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// El primer número de una línea, o nil.
    public static func numeroDe(_ linea: String) -> Double? { numerosDe(linea).first }

    /// Todos los números de una línea, en orden.
    ///
    /// **La coma es decimal**, que es como lo escribe una app en español: "3,5" es tres y
    /// medio y no dos números. Y un "3,5/7" da solo el 3,5 — el 7 es el máximo de la
    /// escala, no un dato del jugador; por eso se descarta lo que vaya detrás de una barra.
    public static func numerosDe(_ linea: String) -> [Double] {
        let sinEscala = linea.replacingOccurrences(
            of: "/\\s*\\d+([.,]\\d+)?", with: "", options: .regularExpression
        )
        guard let regex = try? NSRegularExpression(pattern: "-?\\d+(?:[.,]\\d+)?") else {
            return []
        }
        let rango = NSRange(sinEscala.startIndex..., in: sinEscala)
        return regex.matches(in: sinEscala, range: rango).compactMap { match in
            guard let r = Range(match.range, in: sinEscala) else { return nil }
            let texto = String(sinEscala[r]).replacingOccurrences(of: ",", with: ".")
            guard let valor = Double(texto), valor >= 0 else { return nil }
            return valor
        }
    }
}
