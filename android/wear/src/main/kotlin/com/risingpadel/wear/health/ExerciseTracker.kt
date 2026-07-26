package com.risingpadel.wear.health

import android.content.Context
import androidx.health.services.client.ExerciseClient
import androidx.health.services.client.ExerciseUpdateCallback
import androidx.health.services.client.HealthServices
import androidx.health.services.client.data.Availability
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.DeltaDataType
import androidx.health.services.client.data.ExerciseConfig
import androidx.health.services.client.data.ExerciseLapSummary
import androidx.health.services.client.data.ExerciseType
import androidx.health.services.client.data.ExerciseUpdate
import androidx.health.services.client.data.WarmUpConfig
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.guava.await

/** Métricas de salud del workout, ya normalizadas. */
data class ExerciseMetrics(
    val heartRateBpm: Int? = null,
    val activeEnergyKcal: Float? = null,
    val steps: Int? = null,
    val distanceMeters: Float? = null,
)

/**
 * Envoltorio de Health Services.
 *
 * El tipo de ejercicio es [ExerciseType.TENNIS]: Health Services no tiene pádel, y
 * tenis es el perfil más parecido en patrón de esfuerzo (intervalos cortos e intensos
 * con desplazamientos laterales), así que es el que mejor estima calorías.
 */
class ExerciseTracker(context: Context) {

    private val client: ExerciseClient = HealthServices.getClient(context).exerciseClient

    /** Tipos de dato que este reloj concreto sabe medir para tenis. */
    suspend fun supportedDataTypes(): Set<DataType<*, *>> {
        val capabilities = client.getCapabilitiesAsync().await()
        val forTennis = capabilities.getExerciseTypeCapabilities(ExerciseType.TENNIS)
        return DESIRED_DATA_TYPES.filterTo(mutableSetOf()) { it in forTennis.supportedDataTypes }
    }

    /** Prepara los sensores antes de empezar, para que la FC ya esté disponible al primer punto. */
    suspend fun warmUp(dataTypes: Set<DataType<*, *>>) {
        // WarmUpConfig solo acepta tipos delta —muestras instantáneas como la FC—. Los
        // acumulados (calorías, pasos, distancia) no se pueden precalentar porque no son
        // una lectura puntual sino un total que se va sumando.
        val warmUpTypes = dataTypes.filterIsInstance<DeltaDataType<*, *>>().toSet()
        if (warmUpTypes.isEmpty()) return
        runCatching {
            client.prepareExerciseAsync(WarmUpConfig(ExerciseType.TENNIS, warmUpTypes)).await()
        }
    }

    suspend fun start(dataTypes: Set<DataType<*, *>>) {
        val config = ExerciseConfig.builder(ExerciseType.TENNIS)
            .setDataTypes(dataTypes)
            // El pádel tiene pausas constantes entre puntos: la autopausa cortaría la
            // sesión cada dos por tres.
            .setIsAutoPauseAndResumeEnabled(false)
            .setIsGpsEnabled(false)
            .build()
        client.startExerciseAsync(config).await()
    }

    suspend fun end() {
        runCatching { client.endExerciseAsync().await() }
    }

    /** Stream de métricas. Emite en cada actualización de Health Services (≈1 Hz). */
    fun metrics(): Flow<ExerciseMetrics> = callbackFlow {
        val callback = object : ExerciseUpdateCallback {
            override fun onExerciseUpdateReceived(update: ExerciseUpdate) {
                trySend(update.toMetrics())
            }

            override fun onLapSummaryReceived(lapSummary: ExerciseLapSummary) = Unit

            override fun onAvailabilityChanged(dataType: DataType<*, *>, availability: Availability) = Unit

            override fun onRegistered() = Unit

            override fun onRegistrationFailed(throwable: Throwable) {
                close(throwable)
            }
        }
        client.setUpdateCallback(callback)
        awaitClose { client.clearUpdateCallback(callback) }
    }

    private fun ExerciseUpdate.toMetrics(): ExerciseMetrics {
        val heartRate = latestMetrics.getData(DataType.HEART_RATE_BPM)
            .lastOrNull()?.value?.toInt()
        val calories = latestMetrics.getData(DataType.CALORIES_TOTAL)?.total?.toFloat()
        val steps = latestMetrics.getData(DataType.STEPS_TOTAL)?.total?.toInt()
        val distance = latestMetrics.getData(DataType.DISTANCE_TOTAL)?.total?.toFloat()
        return ExerciseMetrics(
            heartRateBpm = heartRate,
            activeEnergyKcal = calories,
            steps = steps,
            distanceMeters = distance,
        )
    }

    private companion object {
        val DESIRED_DATA_TYPES = setOf<DataType<*, *>>(
            DataType.HEART_RATE_BPM,
            DataType.CALORIES_TOTAL,
            DataType.STEPS_TOTAL,
            DataType.DISTANCE_TOTAL,
        )
    }
}
