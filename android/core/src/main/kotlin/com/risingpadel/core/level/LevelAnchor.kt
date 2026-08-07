package com.risingpadel.core.level

import kotlinx.serialization.Serializable

/**
 * Un punto de anclaje: qué mide el reloj, de media, en jugadores que declaran un nivel
 * conocido.
 */
@Serializable
data class AnclaDeNivel(
    /** Nivel declarado por el jugador (escala 1-7 tipo Playtomic). */
    val nivelDeclarado: Float,
    /** Mediana de lo que midió el reloj a los jugadores de ese nivel. */
    val medidoMediana: Float,
    /** Cuántos jugadores distintos lo sostienen. */
    val jugadores: Int,
)

/**
 * La tabla que traduce **lo que mide el reloj** a **nivel real de juego**.
 *
 * Existe porque son dos cosas distintas y confundirlas sería mentir: el reloj mide
 * velocidad de pala, amplitud de swing y regularidad, y de ahí sale un número; lo que
 * un jugador quiere saber es a qué nivel de pista equivale eso. La única forma honesta
 * de unir las dos escalas es medir a jugadores cuyo nivel se conoce de antemano.
 *
 * Por eso la tabla **no se inventa aquí**: la construye el servidor con los niveles que
 * declaran los usuarios de la comunidad, y va mejorando según juega más gente. Con dos
 * anclas o menos no se traduce nada — antes sin equivalencia que con una inventada.
 */
@Serializable
data class LevelAnchorTable(
    val puntos: List<AnclaDeNivel> = emptyList(),
    /** Cuándo se calculó, para poder refrescarla. */
    val creadoEpochMs: Long = 0,
) {
    /** Sin anclas suficientes no hay traducción posible. */
    val fiable: Boolean
        get() = puntos.count { it.jugadores >= MIN_JUGADORES_POR_ANCLA } >= MIN_ANCLAS

    /**
     * Traduce una medición del reloj al nivel de juego equivalente, interpolando entre
     * las anclas conocidas. Null si la tabla todavía no se sostiene.
     *
     * Fuera del rango medido no se extrapola a lo loco: se devuelve el nivel del ancla
     * más cercana. Decirle a alguien que es un 7 porque pega más fuerte que la persona
     * más fuerte que hemos medido sería exactamente el tipo de mentira que esta clase
     * existe para evitar.
     */
    fun equivalente(medido: Float): Float? {
        if (!fiable) return null
        val validos = puntos
            .filter { it.jugadores >= MIN_JUGADORES_POR_ANCLA }
            .sortedBy { it.medidoMediana }

        validos.firstOrNull()?.let { if (medido <= it.medidoMediana) return it.nivelDeclarado }
        validos.lastOrNull()?.let { if (medido >= it.medidoMediana) return it.nivelDeclarado }

        for (i in 0 until validos.size - 1) {
            val bajo = validos[i]
            val alto = validos[i + 1]
            if (medido in bajo.medidoMediana..alto.medidoMediana) {
                val rango = alto.medidoMediana - bajo.medidoMediana
                if (rango <= 0f) return bajo.nivelDeclarado
                val t = (medido - bajo.medidoMediana) / rango
                return bajo.nivelDeclarado + t * (alto.nivelDeclarado - bajo.nivelDeclarado)
            }
        }
        return null
    }

    companion object {
        /** Un ancla con menos jugadores que esto no cuenta: sería una anécdota. */
        const val MIN_JUGADORES_POR_ANCLA = 3
        /** Con menos anclas que esto no hay curva que interpolar. */
        const val MIN_ANCLAS = 2
    }
}

/**
 * Lo que la app puede decir hoy sobre el nivel de un jugador, con lo que hay.
 *
 * El percentil no necesita anclaje: comparar tu medición con la de los demás es cierto
 * desde el primer día. La equivalencia sí, y por eso puede venir vacía.
 */
data class LecturaDeNivel(
    val medido: Float,
    val equivalente: Float?,
    /** 0-100: qué porcentaje de la comunidad queda por debajo. Null si no hay con quién. */
    val percentil: Int?,
) {
    companion object {
        /** Con menos gente que esto, un percentil no significa nada. */
        const val MIN_COMUNIDAD = 8

        fun calcular(
            medido: Float,
            tabla: LevelAnchorTable,
            medicionesComunidad: List<Float>,
        ): LecturaDeNivel = LecturaDeNivel(
            medido = medido,
            equivalente = tabla.equivalente(medido),
            percentil = if (medicionesComunidad.size >= MIN_COMUNIDAD) {
                val pordebajo = medicionesComunidad.count { it < medido }
                (pordebajo * 100 / medicionesComunidad.size).coerceIn(0, 100)
            } else {
                null
            },
        )
    }
}
