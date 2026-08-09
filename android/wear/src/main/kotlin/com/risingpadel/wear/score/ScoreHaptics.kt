package com.risingpadel.wear.score

import android.content.Context
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import com.risingpadel.core.score.ScoreEvent
import com.risingpadel.core.training.EventoDeRutina

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

    /**
     * Avisa de que un ejercicio de la rutina se ha completado.
     *
     * Solo vibra en los cambios de paso, no en cada golpe: en una tanda de treinta
     * derechas, treinta vibraciones son ruido. Lo que hay que notar sin mirar el reloj es
     * "ya puedes cambiar de golpe".
     */
    fun rutina(event: EventoDeRutina) {
        val vibrator = vibrator ?: return
        if (!vibrator.hasVibrator()) return

        val effect = when (event) {
            // Dos toques: ejercicio hecho, toca el siguiente.
            EventoDeRutina.PASO_COMPLETADO ->
                VibrationEffect.createWaveform(longArrayOf(0, 60, 90, 60), -1)
            // Uno largo: la rutina entera está terminada.
            EventoDeRutina.TERMINADA ->
                VibrationEffect.createOneShot(400, VibrationEffect.DEFAULT_AMPLITUDE)
            else -> return
        }
        runCatching { vibrator.vibrate(effect) }
    }

    private companion object {
        const val MEDIUM = 128
    }
}
