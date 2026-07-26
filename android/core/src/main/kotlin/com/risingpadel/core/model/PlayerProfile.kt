package com.risingpadel.core.model

import kotlinx.serialization.Serializable

@Serializable
enum class Hand(val wireName: String) {
    RIGHT("right"),
    LEFT("left");

    companion object {
        fun fromWire(value: String): Hand = if (value == "left") LEFT else RIGHT
    }
}

/**
 * @param hand mano con la que se empuña la pala.
 * @param watchWrist muñeca donde se lleva el reloj. Para medir golpeos **tiene que
 *   coincidir con [hand]**: el reloj solo ve el brazo en el que está. Si no coinciden,
 *   [watchOnRacketArm] es false y la UI debe avisar de que el conteo no será fiable.
 * @param maxHeartRate FC máxima. Si es null se estima con 220 - edad a partir de
 *   [birthYear]; si tampoco hay año de nacimiento se usa 190.
 */
@Serializable
data class PlayerProfile(
    val hand: Hand = Hand.RIGHT,
    val watchWrist: Hand = Hand.RIGHT,
    val birthYear: Int? = null,
    val maxHeartRate: Int? = null,
    val restingHeartRate: Int? = null,
) {
    val watchOnRacketArm: Boolean get() = hand == watchWrist

    fun effectiveMaxHeartRate(currentYear: Int): Int =
        maxHeartRate ?: birthYear?.let { (220 - (currentYear - it)).coerceIn(120, 210) } ?: 190
}
