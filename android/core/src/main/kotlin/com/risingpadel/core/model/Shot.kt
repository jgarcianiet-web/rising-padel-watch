package com.risingpadel.core.model

import kotlinx.serialization.Serializable

/** Tipos de golpeo que distingue el clasificador v1. */
@Serializable
enum class ShotType(val wireName: String) {
    FOREHAND("forehand"),
    BACKHAND("backhand"),
    FOREHAND_VOLLEY("forehandVolley"),
    BACKHAND_VOLLEY("backhandVolley"),

    /** Golpe alto de control, el techo defensivo del pádel. */
    BANDEJA("bandeja"),

    /** Golpe alto con mucho efecto lateral: lo define la rotación axial, no la fuerza. */
    VIBORA("vibora"),

    /** El remate: máxima violencia, pico de giro por encima de todo lo demás. */
    SMASH("smash"),
    SERVE("serve"),
    UNKNOWN("unknown");

    companion object {
        fun fromWire(value: String): ShotType =
            entries.firstOrNull { it.wireName == value }
                // Sesiones anteriores a separar los golpes altos: "overhead" agrupaba
                // bandeja, víbora y smash. Se mapea a bandeja, que es el más común.
                ?: if (value == "overhead") BANDEJA else UNKNOWN
    }
}

/**
 * Rasgos crudos del golpeo. No se suben a la liga: sirven para depurar la detección y
 * para poder reentrenar el clasificador más adelante.
 */
@Serializable
data class ShotFeatures(
    val sweptAngleDeg: Float,
    val peakGyroRadS: Float,
    /** Elevación **mediana** del antebrazo durante el swing: la postura del golpe. */
    val elevationDeg: Float,
    val axialRotationRadS: Float,
    val swingDurationMs: Long,
    /**
     * Hasta dónde subió el brazo durante el swing (percentil 80 de la elevación).
     *
     * Es lo que de verdad distingue un golpe alto de uno de fondo: no "cómo estaba el
     * brazo en el impacto" —que la estimación de gravedad del sistema mide fatal en
     * mitad de un swing violento— sino **si la mano pasó por encima del hombro**. Se usa
     * el percentil 80 y no el máximo porque un solo pico del filtro de fusión no puede
     * convertir una derecha en una bandeja.
     */
    val peakElevationDeg: Float = elevationDeg,
)

/**
 * Un golpeo detectado.
 *
 * @param offsetMs milisegundos desde el inicio de la sesión.
 * @param racketSpeedKmh velocidad **estimada** del centro de la pala. Es una
 *   estimación a partir de la velocidad angular de la muñeca, útil para comparar
 *   golpeos entre sí, no un velocímetro absoluto.
 */
@Serializable
data class Shot(
    val offsetMs: Long,
    val type: ShotType,
    val racketSpeedKmh: Float,
    val impactG: Float,
    val confidence: Float,
    val features: ShotFeatures,
)
