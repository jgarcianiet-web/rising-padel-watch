package com.risingpadel.wear.training

import android.content.Context
import com.risingpadel.core.detection.DetectorConfig
import com.risingpadel.core.model.MotionSample
import com.risingpadel.core.model.PlayerProfile
import com.risingpadel.core.model.ShotType
import com.risingpadel.core.model.SourceInfo
import com.risingpadel.core.training.TrainingRecorder
import com.risingpadel.core.training.TrainingSampleStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File
import java.util.UUID

data class TrainingUiState(
    val recording: Boolean = false,
    val label: ShotType = ShotType.FOREHAND,
    /** Capturados en la tanda en curso. */
    val capturedInBatch: Int = 0,
    /** Total acumulado en el reloj, de todas las tandas. */
    val totalStored: Int = 0,
    val storedBytes: Long = 0,
)

/**
 * Modo de recogida de datos de entrenamiento.
 *
 * El jugador elige un tipo de golpe y da una tanda solo de ese tipo. Es la única forma
 * práctica de conseguir etiquetas fiables: intentar etiquetar después, mirando series de
 * acelerómetro, no funciona.
 *
 * **Estos datos se quedan en el reloj** hasta que el usuario los envía al móvil a
 * propósito, y no se suben nunca a la liga. Ver `docs/training-data.md`.
 */
class TrainingSession(context: Context) {

    val store = TrainingSampleStore(File(context.filesDir, "training/muestras.jsonl"))

    private var recorder: TrainingRecorder? = null

    private val _state = MutableStateFlow(TrainingUiState())
    val state: StateFlow<TrainingUiState> = _state.asStateFlow()

    init {
        refreshStoredCounts()
    }

    fun setLabel(label: ShotType) {
        if (_state.value.recording) return
        _state.value = _state.value.copy(label = label)
    }

    fun start(
        source: SourceInfo,
        profile: PlayerProfile,
        config: DetectorConfig,
        playerAlias: String,
        monotonicMs: Long,
    ) {
        val newRecorder = TrainingRecorder(
            source = source,
            profile = profile,
            config = config,
            sampleIdProvider = { UUID.randomUUID().toString() },
            nowEpochMs = { System.currentTimeMillis() },
        ).apply {
            label = _state.value.label
            this.playerAlias = playerAlias
        }
        newRecorder.start(monotonicMs)
        recorder = newRecorder
        _state.value = _state.value.copy(recording = true, capturedInBatch = 0)
    }

    /**
     * Se escribe cada golpeo en cuanto está listo, no al final de la tanda: si el reloj
     * se queda sin batería a mitad, se pierde como mucho el último.
     */
    fun onMotion(sample: MotionSample) {
        val current = recorder ?: return
        val captured = current.onMotion(sample)
        if (captured.isEmpty()) return
        store.appendAll(captured)
        _state.value = _state.value.copy(capturedInBatch = current.capturedCount)
    }

    fun stop() {
        val current = recorder ?: return
        store.appendAll(current.stop())
        val captured = current.capturedCount
        recorder = null
        _state.value = _state.value.copy(recording = false, capturedInBatch = captured)
        refreshStoredCounts()
    }

    fun clearStored() {
        if (_state.value.recording) return
        store.clear()
        refreshStoredCounts()
    }

    private fun refreshStoredCounts() {
        _state.value = _state.value.copy(
            totalStored = store.count(),
            storedBytes = store.sizeBytes,
        )
    }
}
