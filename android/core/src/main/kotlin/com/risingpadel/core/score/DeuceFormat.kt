package com.risingpadel.core.score

import kotlinx.serialization.Serializable

/**
 * Qué se juega al llegar a 40-40. Cambia de una liga a otra y cambia el conteo, no solo
 * la etiqueta.
 *
 * Los tres formatos se reducen a un único parámetro: **cuántas ventajas se permiten
 * antes de que el siguiente 40-40 sea decisivo**. Con eso, la regla del juego es la
 * misma en los tres casos y solo cambia dónde está la frontera.
 */
@Serializable
enum class DeuceFormat(
    val wireName: String,
    /** Ventajas permitidas antes del punto decisivo. null = sin límite. */
    val advantagesAllowed: Int?,
) {
    /** Ventaja clásica: hay que sacar dos puntos seguidos, sin límite de ventajas. */
    ADVANTAGE("advantage", null),

    /** Punto de oro: a 40-40 el siguiente punto cierra el juego. */
    GOLDEN_POINT("goldenPoint", 0),

    /**
     * Star point: se juegan hasta **dos** ventajas. Si ninguna se convierte, el tercer
     * 40-40 es punto de oro.
     *
     * La secuencia completa es: 40-40 → ventaja → 40-40 → ventaja → 40-40 decisivo.
     */
    STAR_POINT("starPoint", 2);

    /**
     * Puntos crudos a los que el 40-40 pasa a ser decisivo, o null si nunca lo es.
     *
     * 40-40 son 3 puntos cada uno, así que cada ventaja consumida sube la frontera en
     * uno: punto de oro decide en 3-3, star point en 5-5.
     */
    val decisiveDeuceAt: Int?
        get() = advantagesAllowed?.let { 3 + it }

    /** Nombre corto para la UI. Vive junto a la regla para que las tres apps digan lo mismo. */
    val label: String
        get() = when (this) {
            ADVANTAGE -> "Ventajas"
            GOLDEN_POINT -> "Punto de oro"
            STAR_POINT -> "Star point"
        }

    companion object {
        fun fromWire(value: String): DeuceFormat =
            entries.firstOrNull { it.wireName == value } ?: GOLDEN_POINT
    }
}
