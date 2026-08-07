package com.risingpadel.core.level

import com.risingpadel.core.model.ShotType
import kotlinx.serialization.Serializable

/**
 * Una referencia de nivel: lo que mide el reloj a alguien de nivel **técnico** conocido.
 *
 * La fuente son las tandas del modo de datos: le pones el reloj a un jugador, dices qué
 * nivel técnico tiene y le pides diez golpes de cada tipo. Eso, y no el resultado de sus
 * partidos, es lo que define la escala.
 *
 * Deliberadamente **no** se usa el nivel de una plataforma de partidos (Playtomic y
 * similares): ese número mide con quién ganas, no cómo golpeas. Un jugador puede tener
 * técnica de 4 y estar en un 3 competitivo porque juega poco, le toca mala pareja o le
 * falta táctica — anclar la técnica ahí mezclaría dos cosas distintas y la medición
 * dejaría de significar nada.
 */
@Serializable
data class ReferenciaNivel(
    /** Nivel técnico de quien dio estos golpes, de 1 a 7. */
    val nivelTecnico: Float,
    /** Mediana de velocidad de pala (km/h) por tipo de golpe en su tanda. */
    val velocidadPorTipo: Map<String, Float>,
    /** Cuántos golpes la sostienen. */
    val golpes: Int,
)

/**
 * Convierte referencias de jugadores de nivel conocido en las bandas del estimador.
 *
 * Para cada tipo de golpe se ajusta una recta velocidad = a + b·nivel por mínimos
 * cuadrados sobre las referencias disponibles, y de ahí salen las velocidades de nivel 1
 * y de nivel 7. Es el paso que convierte la escala de "estimación razonada a partir de
 * rangos publicados" en "medida contra jugadores reales".
 *
 * Cinturones, porque una banda mal puesta miente sobre el nivel de alguien:
 * 1. Hacen falta al menos dos niveles técnicos **distintos** entre las referencias: con
 *    todas del mismo nivel no hay recta que ajustar.
 * 2. La pendiente tiene que ser positiva — más nivel, más velocidad de pala. Si sale
 *    plana o al revés, ese tipo de golpe no se toca.
 * 3. El tipo necesita un mínimo de golpes en cada referencia.
 */
object LevelReferenceCalibrator {

    /** Golpes mínimos de un tipo en una referencia para que cuente. */
    const val MIN_GOLPES = 10
    /** Niveles técnicos distintos mínimos para poder ajustar una recta. */
    const val MIN_NIVELES = 2

    /**
     * Devuelve las bandas calibradas por tipo de golpe. Vacío si las referencias no dan
     * para nada: entonces se quedan las de fábrica, que es lo honesto.
     */
    fun bandas(referencias: List<ReferenciaNivel>): Map<ShotType, ShotBand> {
        val utiles = referencias.filter { it.golpes >= MIN_GOLPES }
        if (utiles.map { it.nivelTecnico }.distinct().size < MIN_NIVELES) return emptyMap()

        val salida = mutableMapOf<ShotType, ShotBand>()
        for (tipo in ShotType.entries) {
            if (tipo == ShotType.UNKNOWN) continue
            val base = LevelConfig.DEFAULT_BANDS[tipo] ?: continue

            val puntos = utiles.mapNotNull { referencia ->
                referencia.velocidadPorTipo[tipo.wireName]?.let { referencia.nivelTecnico to it }
            }
            if (puntos.map { it.first }.distinct().size < MIN_NIVELES) continue

            val recta = ajustar(puntos) ?: continue
            val (a, b) = recta
            // Más nivel tiene que significar más velocidad de pala; si no, el rasgo no
            // separa niveles en este tipo de golpe y se queda la banda de fábrica.
            if (b <= 0f) continue

            salida[tipo] = ShotBand(
                speedAtLevel1 = (a + b * 1f).coerceAtLeast(5f),
                speedAtLevel7 = (a + b * 7f).coerceAtMost(200f),
                idealSweptDeg = base.idealSweptDeg,
                compactIsBetter = base.compactIsBetter,
            )
        }
        return salida
    }

    /** Mínimos cuadrados: devuelve (ordenada, pendiente) o null si no hay varianza. */
    private fun ajustar(puntos: List<Pair<Float, Float>>): Pair<Float, Float>? {
        val n = puntos.size
        if (n < 2) return null
        val mediaX = puntos.sumOf { it.first.toDouble() } / n
        val mediaY = puntos.sumOf { it.second.toDouble() } / n
        var num = 0.0
        var den = 0.0
        for ((x, y) in puntos) {
            num += (x - mediaX) * (y - mediaY)
            den += (x - mediaX) * (x - mediaX)
        }
        if (den == 0.0) return null
        val b = num / den
        return ((mediaY - b * mediaX).toFloat() to b.toFloat())
    }
}
