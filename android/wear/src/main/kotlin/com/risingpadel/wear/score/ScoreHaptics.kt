package com.risingpadel.wear.score

import android.content.Context
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import com.risingpadel.core.score.ScoreEvent

/**
 * Vibraciones distintas para cada cosa que puede pasar al puntuar.
 *
 * Es lo que hace usable el marcador: entre punto y punto el jugador está colocándose,
 * no mirando el reloj. Un patrón reconocible confirma que el toque se registró y qué
 * significó, sin obligar a levantar la muñeca.
 */
class ScoreHaptics(context: Context) {

    private val vibrator: Vibrator? = runCatching {
        val manager = context.getSystemService(VibratorManager::class.java)
        manager?.defaultVibrator
    }.getOrNull()

    fun play(event: ScoreEvent) {
        val vibrator = vibrator ?: return
        if (!vibrator.hasVibrator()) return

        val effect = when (event) {
            // Un toque seco: "anotado".
            ScoreEvent.POINT -> VibrationEffect.createOneShot(30, MEDIUM)
            // Dos toques: juego.
            ScoreEvent.GAME -> VibrationEffect.createWaveform(longArrayOf(0, 40, 80, 40), -1)
            // Tres: set.
            ScoreEvent.SET -> VibrationEffect.createWaveform(longArrayOf(0, 50, 80, 50, 80, 50), -1)
            // Uno largo: partido.
            ScoreEvent.MATCH -> VibrationEffect.createOneShot(300, VibrationEffect.DEFAULT_AMPLITUDE)
            // Dos largos y suaves, distinto de todo lo anterior: se ha deshecho.
            ScoreEvent.UNDO -> VibrationEffect.createWaveform(longArrayOf(0, 120, 60, 120), -1)
        }
        runCatching { vibrator.vibrate(effect) }
    }

    private companion object {
        const val MEDIUM = 128
    }
}
