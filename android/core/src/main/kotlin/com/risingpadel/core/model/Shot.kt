package com.risingpadel.core.model

import kotlinx.serialization.Serializable

/** Tipos de golpeo que distingue el clasificador v1. */
@Serializable
enum class ShotType(val wireName: String) {
    FOREHAND("forehand"),
    BACKHAND("backhand"),
    FOREHAND_VOLLEY("forehandVolley"),
    BACKHAND_VOLLEY("backhandVolley"),
    OVERHEAD("overhead"),
    SERVE("serve"),
    UNKNOWN("unknown");

    companion object {
        fun fromWire(value: String): ShotType =
            entries.firstOrNull { it.wireName == value } ?: UNKNOWN
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
    val elevationDeg: Float,
    val axialRotationRadS: Float,
    val swingDurationMs: Long,
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
