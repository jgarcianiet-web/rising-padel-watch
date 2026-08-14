package com.risingpadel.wear.training

import android.content.Context
import com.risingpadel.core.detection.DetectorConfig
import com.risingpadel.core.model.MotionSample
import com.risingpadel.core.model.PlayerProfile
import com.risingpadel.core.model.ShotType
import com.risingpadel.core.model.SourceInfo
import com.risingpadel.core.training.GrabadorDeTanda
import com.risingpadel.core.training.TrainingSampleStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File
import java.util.UUID

data class TrainingUiState(
    val recording: Boolean = false,
    val label: ShotType = ShotType.FOREHAND,
    /** Golpes que el detector cree haber visto. Informativo, no puerta. */
    val capturedInBatch: Int = 0,
    /**
     * Segundos de tanda grabados. Es el contador que SIEMPRE avanza: la prueba de que
     * se está guardando algo, vea el detector lo que vea.
     */
    val segundos: Int = 0,
    /** Tandas acumuladas en el reloj. */
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

    private var grabador: GrabadorDeTanda? = null

    private val _state = MutableStateFlow(TrainingUiState())
    val state: StateFlow<TrainingUiState> = _state.asStateFlow()

    /**
     * Los swings que el detector tiró en la tanda en curso, con el motivo.
     *
     * Se guarda al parar para que el resumen siga en pie con la tanda ya cerrada: es
     * justo cuando el móvil pregunta cómo ha ido. Null antes de la primera tanda.
     */
    val descartes: com.risingpadel.core.detection.DescartesDelDetector?
        get() = grabador?.descartes ?: descartesDeLaUltima

    private var descartesDeLaUltima: com.risingpadel.core.detection.DescartesDelDetector? = null

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
        playerLevel: Int?,
        monotonicMs: Long,
    ) {
        // La tanda se graba ENTERA y en crudo: cada muestra se guarda y el detector solo
        // comenta. Es la respuesta a un fallo de pista: la captura por ventanas dependía
        // de que el detector viera impactos, y una tanda de derechas se quedó en cero.
        val nuevo = GrabadorDeTanda(
            source = source,
            profile = profile,
            config = config,
            tandaIdProvider = { UUID.randomUUID().toString() },
            nowEpochMs = { System.currentTimeMillis() },
        ).apply {
            label = _state.value.label
            this.playerAlias = playerAlias
            this.playerLevel = playerLevel
        }
        nuevo.start(monotonicMs)
        grabador = nuevo
        descartesDeLaUltima = null
        _state.value = _state.value.copy(recording = true, capturedInBatch = 0, segundos = 0)
    }

    fun onMotion(sample: MotionSample) {
        val actual = grabador ?: return
        val golpe = actual.onMotion(sample)
        val segundos = actual.segundos
        if (golpe != null || segundos != _state.value.segundos) {
            _state.value = _state.value.copy(
                capturedInBatch = actual.golpes,
                segundos = segundos,
            )
        }
    }

    fun stop() {
        val actual = grabador ?: return
        // La tanda entera se escribe al parar. Si el reloj muere a mitad se pierde esa
        // tanda y solo esa: son dos o tres minutos, no una tarde.
        actual.stop()?.let { store.appendTanda(it) }
        descartesDeLaUltima = actual.descartes
        grabador = null
        _state.value = _state.value.copy(recording = false, capturedInBatch = actual.golpes)
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
