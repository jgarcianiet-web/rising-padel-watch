import Foundation
import PadelCore

/// Dominio de la Liga Personal, portado 1:1 de la app Expo (`padel`, src/types/domain.ts).
///
/// La regla que gobierna este fichero: **la copia de seguridad JSON de la app Expo tiene
/// que importar aquí sin transformación**, y viceversa. Por eso los nombres de campo son
/// los del TypeScript (fecha, tipo, marcador…), por eso `Perfil` guarda strings donde
/// parecería que van números (son campos de texto en la web-app original) y por eso todo
/// se decodifica con tolerancia: un backup viejo sin un campo nuevo no puede fallar.

/// Un set anotado a mano: strings porque en el formulario original son campos de texto.
struct LigaSetMarcador: Codable, Equatable {
    var yo = ""
    var rival = ""
    var tbYo = ""
    var tbRival = ""
}

struct LigaGolpeSesion: Codable, Equatable {
    var nombre: String
    var nota: Double
}

struct LigaGolpeVolumen: Codable, Equatable {
    var nombre: String
    var cantidad: Int
}

struct LigaSaludPartido: Codable, Equatable {
    var duracionMin: Int
    var pulsoMedio: Int?
    var pulsoMax: Int?
    var calorias: Int?
}

struct LigaPuntoProgreso: Codable, Equatable {
    var minuto: Double
    var nivel: Double
}

struct LigaFrecuenciaGolpeo: Codable, Equatable {
    var intervaloMin: Int
    var cuentas: [Int]
}

/// Un partido de la liga. El espejo exacto de `Match` en la app Expo.
struct LigaMatch: Codable, Equatable, Identifiable {
    /// `Date.now()` de JavaScript: milisegundos de época.
    var id: Int64
    var fecha: String
    var tipo: String
    var resultado: String
    var posicion: String
    var sets: String
    var marcador: [LigaSetMarcador]?
    var club: String
    var companero: String
    /// Los rivales del partido, en texto libre ("Juan y Pedro"). Campo nuevo de
    /// esta app: un backup viejo no lo trae y la app Expo lo ignora.
    var rivales: String?
    var nivel: Double?
    var nivelBand: Double?
    var mejorGolpe: String?
    var mejorPunt: Double?
    var peorGolpe: String?
    var peorPunt: Double?
    var golpesSesion: [LigaGolpeSesion]?
    var objetivos: [Bool]
    var nota: String
    var bandInicio: Double?
    var bandFin: Double?
    var bandMediaJugador: Double?
    var golpesVolumen: [LigaGolpeVolumen]?
    var totalGolpes: Int?
    var salud: LigaSaludPartido?
    var bandPuntos: [LigaPuntoProgreso]?
    var frecuenciaGolpeo: LigaFrecuenciaGolpeo?

    /// Decodificación tolerante campo a campo: un backup de una versión vieja (o de la
    /// web-app original) trae menos campos, y uno futuro puede traer más.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        fecha = try c.decodeIfPresent(String.self, forKey: .fecha) ?? ""
        tipo = try c.decodeIfPresent(String.self, forKey: .tipo) ?? "amistoso"
        resultado = try c.decodeIfPresent(String.self, forKey: .resultado) ?? "derrota"
        posicion = try c.decodeIfPresent(String.self, forKey: .posicion) ?? "reves"
        sets = try c.decodeIfPresent(String.self, forKey: .sets) ?? ""
        marcador = try c.decodeIfPresent([LigaSetMarcador].self, forKey: .marcador)
        club = try c.decodeIfPresent(String.self, forKey: .club) ?? ""
        companero = try c.decodeIfPresent(String.self, forKey: .companero) ?? ""
        rivales = try c.decodeIfPresent(String.self, forKey: .rivales)
        nivel = try c.decodeIfPresent(Double.self, forKey: .nivel)
        nivelBand = try c.decodeIfPresent(Double.self, forKey: .nivelBand)
        mejorGolpe = try c.decodeIfPresent(String.self, forKey: .mejorGolpe)
        mejorPunt = try c.decodeIfPresent(Double.self, forKey: .mejorPunt)
        peorGolpe = try c.decodeIfPresent(String.self, forKey: .peorGolpe)
        peorPunt = try c.decodeIfPresent(Double.self, forKey: .peorPunt)
        golpesSesion = try c.decodeIfPresent([LigaGolpeSesion].self, forKey: .golpesSesion)
        objetivos = try c.decodeIfPresent([Bool].self, forKey: .objetivos) ?? [false, false, false]
        nota = try c.decodeIfPresent(String.self, forKey: .nota) ?? ""
        bandInicio = try c.decodeIfPresent(Double.self, forKey: .bandInicio)
        bandFin = try c.decodeIfPresent(Double.self, forKey: .bandFin)
        bandMediaJugador = try c.decodeIfPresent(Double.self, forKey: .bandMediaJugador)
        golpesVolumen = try c.decodeIfPresent([LigaGolpeVolumen].self, forKey: .golpesVolumen)
        totalGolpes = try c.decodeIfPresent(Int.self, forKey: .totalGolpes)
        salud = try c.decodeIfPresent(LigaSaludPartido.self, forKey: .salud)
        bandPuntos = try c.decodeIfPresent([LigaPuntoProgreso].self, forKey: .bandPuntos)
        frecuenciaGolpeo = try c.decodeIfPresent(LigaFrecuenciaGolpeo.self, forKey: .frecuenciaGolpeo)
    }

    init(
        id: Int64,
        fecha: String,
        tipo: String,
        resultado: String,
        posicion: String = "reves",
        sets: String = "",
        marcador: [LigaSetMarcador]? = nil,
        club: String = "",
        companero: String = "",
        rivales: String? = nil,
        nivel: Double? = nil,
        nivelBand: Double? = nil,
        mejorGolpe: String? = nil,
        mejorPunt: Double? = nil,
        peorGolpe: String? = nil,
        peorPunt: Double? = nil,
        golpesSesion: [LigaGolpeSesion]? = nil,
        objetivos: [Bool] = [false, false, false],
        nota: String = "",
        bandInicio: Double? = nil,
        bandFin: Double? = nil,
        bandMediaJugador: Double? = nil,
        golpesVolumen: [LigaGolpeVolumen]? = nil,
        totalGolpes: Int? = nil,
        salud: LigaSaludPartido? = nil,
        bandPuntos: [LigaPuntoProgreso]? = nil,
        frecuenciaGolpeo: LigaFrecuenciaGolpeo? = nil
    ) {
        self.id = id
        self.fecha = fecha
        self.tipo = tipo
        self.resultado = resultado
        self.posicion = posicion
        self.sets = sets
        self.marcador = marcador
        self.club = club
        self.companero = companero
        self.rivales = rivales
        self.nivel = nivel
        self.nivelBand = nivelBand
        self.mejorGolpe = mejorGolpe
        self.mejorPunt = mejorPunt
        self.peorGolpe = peorGolpe
        self.peorPunt = peorPunt
        self.golpesSesion = golpesSesion
        self.objetivos = objetivos
        self.nota = nota
        self.bandInicio = bandInicio
        self.bandFin = bandFin
        self.bandMediaJugador = bandMediaJugador
        self.golpesVolumen = golpesVolumen
        self.totalGolpes = totalGolpes
        self.salud = salud
        self.bandPuntos = bandPuntos
        self.frecuenciaGolpeo = frecuenciaGolpeo
    }
}

/// Perfil del jugador. Strings a propósito: en la web-app original son inputs de texto y
/// el backup los guarda así.
struct LigaPerfil: Codable, Equatable {
    var nivelPlaytomic = ""
    var nivelBand = ""
    var nivelObjetivo = ""
    var fechaInicio = ""
}

/// Un análisis generado por la IA de la liga.
struct LigaAnalisis: Codable, Equatable {
    var lectura = ""
    var patrones: [String] = []
    var plan: [String] = []
    var foco = ""
    var objetivos: [String] = []
    var fecha = ""
    var nPartidos = 0

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lectura = try c.decodeIfPresent(String.self, forKey: .lectura) ?? ""
        patrones = try c.decodeIfPresent([String].self, forKey: .patrones) ?? []
        plan = try c.decodeIfPresent([String].self, forKey: .plan) ?? []
        foco = try c.decodeIfPresent(String.self, forKey: .foco) ?? ""
        objetivos = try c.decodeIfPresent([String].self, forKey: .objetivos) ?? []
        fecha = try c.decodeIfPresent(String.self, forKey: .fecha) ?? ""
        nPartidos = try c.decodeIfPresent(Int.self, forKey: .nPartidos) ?? 0
    }

    // El init(from:) tolerante se come el memberwise: hay que devolverlo a mano para
    // que el entrenador pueda construir un análisis.
    init(
        lectura: String = "",
        patrones: [String] = [],
        plan: [String] = [],
        foco: String = "",
        objetivos: [String] = [],
        fecha: String = "",
        nPartidos: Int = 0
    ) {
        self.lectura = lectura
        self.patrones = patrones
        self.plan = plan
        self.foco = foco
        self.objetivos = objetivos
        self.fecha = fecha
        self.nPartidos = nPartidos
    }
}

/// Una temporada de la liga: un tramo de fechas con un objetivo de partidos.
///
/// Los partidos **no** llevan referencia a su temporada a propósito: la temporada es un
/// rango de fechas y cada partido cae en la suya por su `fecha`. Así el backup no cambia
/// de shape en los partidos (que es lo que la app Expo relee), funciona con historiales
/// importados de antes de que existieran temporadas, y mover un partido de fecha lo
/// recoloca solo.
struct LigaTemporada: Codable, Equatable, Identifiable {
    /// Milisegundos de época de su creación, como el id de los partidos.
    var id: Int64
    var nombre = ""
    /// yyyy-mm-dd. El rango es [inicio, fin]; fin vacío = temporada en curso.
    var fechaInicio = ""
    var fechaFin = ""
    /// Cuántos partidos se quiere jugar esta temporada. Nil = sin meta de volumen.
    var objetivoPartidos: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        nombre = try c.decodeIfPresent(String.self, forKey: .nombre) ?? ""
        fechaInicio = try c.decodeIfPresent(String.self, forKey: .fechaInicio) ?? ""
        fechaFin = try c.decodeIfPresent(String.self, forKey: .fechaFin) ?? ""
        objetivoPartidos = try c.decodeIfPresent(Int.self, forKey: .objetivoPartidos)
    }

    init(id: Int64, nombre: String, fechaInicio: String, fechaFin: String = "", objetivoPartidos: Int? = nil) {
        self.id = id
        self.nombre = nombre
        self.fechaInicio = fechaInicio
        self.fechaFin = fechaFin
        self.objetivoPartidos = objetivoPartidos
    }

    var enCurso: Bool { fechaFin.isEmpty }

    /// true si el partido cae en el rango de esta temporada. Comparación de strings
    /// yyyy-mm-dd, que ordena igual que las fechas.
    func contiene(_ match: LigaMatch) -> Bool {
        match.fecha >= fechaInicio && (fechaFin.isEmpty || match.fecha <= fechaFin)
    }
}

/// El estado completo de la liga: lo que guarda el fichero y lo que exporta el backup.
struct LigaState: Codable, Equatable {
    var matches: [LigaMatch] = []
    var objetivos: [String] = []
    var perfil = LigaPerfil()
    var analisis: LigaAnalisis?
    var analisisHistorial: [LigaAnalisis] = []
    /// En orden de creación. Campo nuevo de esta app: un backup viejo no lo trae (la
    /// liga entera se comporta como una sola temporada) y la app Expo lo ignora.
    var temporadas: [LigaTemporada] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        matches = try c.decodeIfPresent([LigaMatch].self, forKey: .matches) ?? []
        objetivos = try c.decodeIfPresent([String].self, forKey: .objetivos) ?? []
        perfil = try c.decodeIfPresent(LigaPerfil.self, forKey: .perfil) ?? LigaPerfil()
        analisis = try c.decodeIfPresent(LigaAnalisis.self, forKey: .analisis)
        analisisHistorial =
            try c.decodeIfPresent([LigaAnalisis].self, forKey: .analisisHistorial)
            ?? (analisis.map { [$0] } ?? [])
        temporadas = try c.decodeIfPresent([LigaTemporada].self, forKey: .temporadas) ?? []
    }
}
