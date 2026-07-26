package com.risingpadel.mobile.sync

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.risingpadel.mobile.PadelMobileApp
import kotlinx.coroutines.flow.first
import java.util.concurrent.TimeUnit

/**
 * Sube a la liga las sesiones pendientes.
 *
 * La política de reintentos vive en [com.risingpadel.core.sync.SyncQueue] y no en
 * WorkManager: la cola sabe distinguir un 400 (no reintentar nunca) de un 503
 * (reintentar con backoff), y WorkManager solo sabe de éxito o fallo. Aquí el worker
 * siempre devuelve `success`; quien decide qué se reintenta y cuándo es la cola.
 */
class SyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val container = (applicationContext as PadelMobileApp).container
        val preferences = container.settings.preferences.first()
        val config = container.settings.leagueConfig(preferences.leagueBaseUrl)

        container.sessions.refresh()
        container.syncQueue.sync(
            config = config,
            shareHealth = preferences.shareHealth,
            includeEvents = preferences.shareShotEvents,
        )
        container.sessions.refresh()
        return Result.success()
    }
}

object SyncScheduler {

    private const val PERIODIC_WORK = "padel_sync_periodic"
    private const val ONE_SHOT_WORK = "padel_sync_now"

    /** Red de seguridad: repasa la cola cada pocas horas por si algo quedó pendiente. */
    fun schedulePeriodic(context: Context) {
        val request = PeriodicWorkRequestBuilder<SyncWorker>(4, TimeUnit.HOURS)
            .setConstraints(
                Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
            )
            .build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            PERIODIC_WORK,
            ExistingPeriodicWorkPolicy.KEEP,
            request,
        )
    }

    /** Se llama al recibir una sesión del reloj y cuando el usuario pulsa sincronizar. */
    fun requestSyncNow(context: Context) {
        val request = OneTimeWorkRequestBuilder<SyncWorker>()
            .setConstraints(
                Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
            )
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            ONE_SHOT_WORK,
            ExistingWorkPolicy.REPLACE,
            request,
        )
    }
}
