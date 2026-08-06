package com.risingpadel.core.liga

import kotlinx.serialization.Serializable

/**
 * Dominio de la Liga Personal, portado 1:1 de la app Expo (`padel`, src/types/domain.ts)
 * y espejo del Swift `LigaModels.swift`.
 *
 * La regla que gobierna este fichero: **la copia de seguridad JSON de la app Expo (y de
 * la app de iOS) tiene que importar aquí sin transformación**, y viceversa. Por eso los
 * nombres de campo son los del TypeScript — incluidos los heredados de Padel Band
 * (nivelBand, bandInicio…), que hoy contienen el nivel que mide el reloj — y por eso
 * todo campo tiene default: un backup viejo sin un campo nuevo no puede fallar.
 */

@Serializable
data class LigaSetMarcador(
    val yo: String = "",
    val rival: String = "",
    val tbYo: String = "",
    val tbRival: String = "",
)

@Serializable
data class LigaGolpeSesion(val nombre: String, val nota: Double)

@Serializable
data class LigaGolpeVolumen(val nombre: String, val cantidad: Int)

@Serializable
data class LigaSaludPartido(
    val duracionMin: Int = 0,
    val pulsoMedio: Int? = null,
    val pulsoMax: Int? = null,
    val calorias: Int? = null,
)

@Serializable
data class LigaPuntoProgreso(val minuto: Double, val nivel: Double)

@Serializable
data class LigaFrecuenciaGolpeo(val intervaloMin: Int, val cuentas: List<Int>)

/** Un partido de la liga. El espejo exacto de `Match` en la app Expo. */
@Serializable
data class LigaMatch(
    /** `Date.now()` de JavaScript: milisegundos de época. */
    val id: Long,
    val fecha: String = "",
    val tipo: String = "amistoso",
    val resultado: String = "derrota",
    val posicion: String = "reves",
    val sets: String = "",
    val marcador: List<LigaSetMarcador>? = null,
    val club: String = "",
    val companero: String = "",
    /** Los rivales del partido, en texto libre ("Juan y Pedro"). Campo nuevo de esta
     * app: un backup viejo no lo trae y la app Expo lo ignora. */
    val rivales: String? = null,
    val nivel: Double? = null,
    val nivelBand: Double? = null,
    val mejorGolpe: String? = null,
    val mejorPunt: Double? = null,
    val peorGolpe: String? = null,
    val peorPunt: Double? = null,
    val golpesSesion: List<LigaGolpeSesion>? = null,
    val objetivos: List<Boolean> = listOf(false, false, false),
    val nota: String = "",
    val bandInicio: Double? = null,
    val bandFin: Double? = null,
    val bandMediaJugador: Double? = null,
    val golpesVolumen: List<LigaGolpeVolumen>? = null,
    val totalGolpes: Int? = null,
    val salud: LigaSaludPartido? = null,
    val bandPuntos: List<LigaPuntoProgreso>? = null,
    val frecuenciaGolpeo: LigaFrecuenciaGolpeo? = null,
) {
    /** La métrica estrella de la liga: 2 de 3 objetivos cumplidos. */
    val bienJugado: Boolean get() = objetivos.count { it } >= 2
}

/** Strings a propósito: en la web-app original son inputs de texto y el backup los guarda así. */
@Serializable
data class LigaPerfil(
    val nivelPlaytomic: String = "",
    val nivelBand: String = "",
    val nivelObjetivo: String = "",
    val fechaInicio: String = "",
)

@Serializable
data class LigaAnalisis(
    val lectura: String = "",
    val patrones: List<String> = emptyList(),
    val plan: List<String> = emptyList(),
    val foco: String = "",
    val objetivos: List<String> = emptyList(),
    val fecha: String = "",
    val nPartidos: Int = 0,
)

/**
 * Una temporada de la liga: un tramo de fechas con un objetivo de partidos.
 *
 * Los partidos no llevan referencia a su temporada: cada uno cae en la suya por su
 * `fecha`. Así el shape de los partidos del backup no cambia y los historiales
 * importados de antes de que existieran temporadas funcionan igual.
 */
@Serializable
data class LigaTemporada(
    val id: Long,
    val nombre: String = "",
    /** yyyy-mm-dd. El rango es [inicio, fin]; fin vacío = temporada en curso. */
    val fechaInicio: String = "",
    val fechaFin: String = "",
    /** Cuántos partidos se quiere jugar esta temporada. Null = sin meta de volumen. */
    val objetivoPartidos: Int? = null,
) {
    val enCurso: Boolean get() = fechaFin.isEmpty()

    /** true si el partido cae en el rango. Strings yyyy-mm-dd ordenan como fechas. */
    fun contiene(match: LigaMatch): Boolean =
        match.fecha >= fechaInicio && (fechaFin.isEmpty() || match.fecha <= fechaFin)
}

/** El estado completo de la liga: lo que guarda el fichero y lo que exporta el backup. */
@Serializable
data class LigaState(
    val matches: List<LigaMatch> = emptyList(),
    val objetivos: List<String> = emptyList(),
    val perfil: LigaPerfil = LigaPerfil(),
    val analisis: LigaAnalisis? = null,
    val analisisHistorial: List<LigaAnalisis> = emptyList(),
    /** Campo nuevo de esta app: un backup viejo no lo trae y la app Expo lo ignora. */
    val temporadas: List<LigaTemporada> = emptyList(),
)

/** Las métricas de temporada que ya usa iOS, para que Android pinte las mismas. */
/**
 * El cara a cara con una persona: cuántas veces has jugado contra (o con) ella y cómo
 * fue. `ultimos` son los resultados más recientes, true = victoria, el último el más
 * nuevo — para pintar la mini-racha VVDVV.
 */
@Serializable
data class LigaCaraACara(
    val nombre: String,
    val partidos: Int,
    val victorias: Int,
    val ultimos: List<Boolean>,
) {
    val pctVictorias: Int get() = if (partidos == 0) 0 else victorias * 100 / partidos
}

object LigaMetrics {

    /**
     * Estadísticas contra cada rival. El campo `rivales` es texto libre ("Juan y
     * Pedro"), así que se separa por comas, "y", "/" o "&" y se agrupa por nombre
     * normalizado (espacios fuera, mayúsculas da igual); se enseña la grafía de la
     * primera vez. Orden: más partidos primero, y a igualdad, alfabético.
     */
    fun caraACara(matches: List<LigaMatch>): List<LigaCaraACara> =
        agrupa(matches) { partirNombres(it.rivales ?: "") }

    /** Lo mismo, pero con la pareja: con quién juegas y cómo os va. */
    fun conPareja(matches: List<LigaMatch>): List<LigaCaraACara> =
        agrupa(matches) { partirNombres(it.companero) }

    /** "Juan y Pedro" → ["Juan", "Pedro"]. Separadores: coma, " y ", "/", "&". */
    fun partirNombres(texto: String): List<String> =
        texto.split(",", " y ", "/", "&")
            .map { it.trim() }
            .filter { it.isNotEmpty() }

    private fun agrupa(
        matches: List<LigaMatch>,
        nombresDe: (LigaMatch) -> List<String>,
    ): List<LigaCaraACara> {
        // clave normalizada → (grafía original, resultados en orden cronológico)
        val grafias = LinkedHashMap<String, String>()
        val resultados = LinkedHashMap<String, MutableList<Boolean>>()
        for (match in cronologico(matches)) {
            for (nombre in nombresDe(match)) {
                val clave = nombre.lowercase()
                grafias.getOrPut(clave) { nombre }
                resultados.getOrPut(clave) { mutableListOf() }
                    .add(match.resultado == "victoria")
            }
        }
        return resultados.entries
            .map { (clave, lista) ->
                LigaCaraACara(
                    nombre = grafias.getValue(clave),
                    partidos = lista.size,
                    victorias = lista.count { it },
                    ultimos = lista.takeLast(5),
                )
            }
            .sortedWith(compareByDescending<LigaCaraACara> { it.partidos }.thenBy { it.nombre })
    }

    fun racha(matches: List<LigaMatch>): Int {
        var racha = 0
        for (match in cronologico(matches).reversed()) {
            if (!match.bienJugado) break
            racha++
        }
        return racha
    }

    fun mejorRacha(matches: List<LigaMatch>): Int {
        var mejor = 0
        var actual = 0
        for (match in cronologico(matches)) {
            actual = if (match.bienJugado) actual + 1 else 0
            if (actual > mejor) mejor = actual
        }
        return mejor
    }

    fun pctVictorias(matches: List<LigaMatch>): Int {
        if (matches.isEmpty()) return 0
        return (matches.count { it.resultado == "victoria" } * 100.0 / matches.size).toInt()
    }

    /** Nivel de la sesión: el campo directo o, si falta, la media de la curva. */
    fun nivelDeSesion(m: LigaMatch): Double? {
        m.nivelBand?.let { return it }
        val puntos = listOfNotNull(m.bandInicio, m.bandFin)
        return if (puntos.isEmpty()) null else puntos.average()
    }

    private fun cronologico(matches: List<LigaMatch>) = matches.sortedBy { it.fecha }
}
