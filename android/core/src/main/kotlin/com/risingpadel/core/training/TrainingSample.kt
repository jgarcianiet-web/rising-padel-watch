package com.risingpadel.core.training

import com.risingpadel.core.model.Hand
import com.risingpadel.core.model.Platform
import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType
import kotlinx.serialization.Serializable

/**
 * Un golpeo etiquetado con su señal cruda, para entrenar el clasificador.
 *
 * La etiqueta viene puesta desde el momento de grabar: el jugador elige un tipo de golpe
 * y da una tanda solo de ese tipo. Etiquetar después, mirando gráficas, no funciona —
 * nadie distingue un revés de una volea alta en una serie de acelerómetro.
 *
 * **Estos datos no salen del reloj solos.** Ver `docs/training-data.md`.
 *
 * @param playerAlias alias que el jugador elige, no su nombre. Existe para poder validar
 *   el modelo dejando fuera a un jugador entero: si los golpeos de la misma persona caen
 *   a los dos lados de la partición, el modelo memoriza al jugador y la precisión que
 *   mides es mentira.
 * @param offsetsMs milisegundos de cada muestra **relativos al impacto**: negativos
 *   antes, positivos después.
 * @param heuristicPrediction lo que dijo el clasificador v1. Se guarda para poder medir
 *   cuánto mejora el modelo entrenado sobre la heurística, no para entrenar con ello.
 */
@Serializable
data class TrainingSample(
    val sampleId: String,
    val label: ShotType,
    val recordedAtEpochMs: Long,
    val playerAlias: String,
    val hand: Hand,
    val watchWrist: Hand,
    val platform: Platform,
    val device: String,
    val sampleRateHz: Int,
    /** Índice del impacto dentro de las series. */
    val impactIndex: Int,
    val offsetsMs: List<Int>,
    /** Aceleración sin gravedad, en g. Una lista de [x, y, z] por muestra. */
    val accel: List<List<Float>>,
    /** Velocidad angular en rad/s. */
    val gyro: List<List<Float>>,
    /** Vector gravedad en g. */
    val gravity: List<List<Float>>,
    val heuristicFeatures: ShotFeatures,
    val heuristicPrediction: ShotType,
    val heuristicConfidence: Float,
) {
    val sampleCount: Int get() = offsetsMs.size

    /** True si la heurística ya acertaba. Sirve para medir la mejora del modelo. */
    val heuristicWasRight: Boolean get() = heuristicPrediction == label
}
