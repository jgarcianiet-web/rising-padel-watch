package com.risingpadel.core.level

import com.risingpadel.core.model.ShotType

/**
 * Referencias por tipo de golpe para puntuar de 1 a 7.
 *
 * @param speedAtLevel1 velocidad estimada de pala (km/h) de un golpe de nivel 1.
 * @param speedAtLevel7 la de un nivel 7. Entre las dos se interpola.
 * @param idealSweptDeg ángulo barrido de referencia.
 * @param compactIsBetter si true, pasarse del ángulo ideal **resta**. Es el caso de las
 *   voleas: en pádel la volea se bloquea, no se golpea, y un swing largo en la red es
 *   precisamente el error que separa a un jugador de nivel bajo de uno de nivel alto.
 */
data class ShotBand(
    val speedAtLevel1: Float,
    val speedAtLevel7: Float,
    val idealSweptDeg: Float,
    val compactIsBetter: Boolean = false,
)

/**
 * Todos los parámetros del estimador de nivel.
 *
 * Están en un solo sitio y son datos, no constantes sueltas, porque **hay que
 * calibrarlos**: las bandas de abajo son estimaciones razonadas a partir de rangos
 * publicados de velocidad angular de muñeca, no medidas contra jugadores de nivel
 * conocido. Ver `docs/level.md`.
 */
data class LevelConfig(
    val bands: Map<ShotType, ShotBand> = DEFAULT_BANDS,
    /** Peso de la velocidad frente a la amplitud del swing. */
    val speedWeight: Float = 0.65f,
    /** Golpeos por debajo de esta confianza no puntúan: el tipo no está claro. */
    val minConfidence: Float = 0.45f,
    /** Por debajo de esto el nivel no se reporta como fiable. */
    val minShotsForEstimate: Int = 30,
    /** Cuántos niveles llega a restar la falta de regularidad. */
    val maxConsistencyPenalty: Float = 0.8f,
    /** Cuántos niveles llega a sumar tener repertorio completo. */
    val maxRepertoireBonus: Float = 0.4f,
    /** Golpeos mínimos de un tipo para contarlo como parte del repertorio. */
    val minShotsPerTypeForRepertoire: Int = 5,
) {
    companion object {
        /**
         * Bandas por defecto.
         *
         * Salen de convertir los rangos de velocidad angular de muñeca documentados en
         * `shot-detection.md` (volea 5-10 rad/s, derecha 15-25, smash 25-35) con el mismo
         * brazo de palanca que usa el detector, y de ensanchar los extremos para que el 1
         * y el 7 sean alcanzables sin saturar a la mitad de los jugadores.
         */
        val DEFAULT_BANDS: Map<ShotType, ShotBand> = mapOf(
            ShotType.FOREHAND to ShotBand(28f, 65f, idealSweptDeg = 200f),
            ShotType.BACKHAND to ShotBand(26f, 60f, idealSweptDeg = 180f),
            // La volea se puntúa al revés en amplitud: compacta es mejor.
            ShotType.FOREHAND_VOLLEY to ShotBand(10f, 26f, idealSweptDeg = 45f, compactIsBetter = true),
            ShotType.BACKHAND_VOLLEY to ShotBand(10f, 24f, idealSweptDeg = 45f, compactIsBetter = true),
            // La bandeja es control: su banda es más corta porque pegarla muy fuerte no
            // la hace mejor. La víbora premia algo más de velocidad, y el smash es el
            // único golpe donde la violencia es directamente el objetivo.
            ShotType.BANDEJA to ShotBand(32f, 58f, idealSweptDeg = 150f),
            ShotType.VIBORA to ShotBand(38f, 68f, idealSweptDeg = 170f),
            ShotType.SMASH to ShotBand(50f, 95f, idealSweptDeg = 210f),
            ShotType.SERVE to ShotBand(32f, 72f, idealSweptDeg = 240f),
        )

        val DEFAULT = LevelConfig()

        const val MIN_LEVEL = 1f
        const val MAX_LEVEL = 7f
    }
}
