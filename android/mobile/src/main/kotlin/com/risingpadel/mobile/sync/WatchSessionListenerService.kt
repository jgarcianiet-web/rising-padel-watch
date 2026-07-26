package com.risingpadel.mobile.sync

import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.WearableListenerService
import com.risingpadel.core.model.PadelSession
import com.risingpadel.mobile.PadelMobileApp
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json

/**
 * Recibe las sesiones que envía el reloj por el Data Layer.
 *
 * Play Services arranca este servicio aunque la app esté cerrada, así que la sesión se
 * guarda al acabar el partido sin que el usuario tenga que abrir nada.
 */
class WatchSessionListenerService : WearableListenerService() {

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        val container = (application as PadelMobileApp).container

        // El callback corre en un hilo de background propio del servicio y el buffer se
        // cierra al volver, así que hay que consumirlo aquí mismo.
        runBlocking {
            dataEvents.forEach { event ->
                if (event.type != DataEvent.TYPE_CHANGED) return@forEach
                if (!event.dataItem.uri.path.orEmpty().startsWith(PATH_PREFIX)) return@forEach

                val payload = DataMapItem.fromDataItem(event.dataItem)
                    .dataMap
                    .getString(KEY_SESSION_JSON)
                    ?: return@forEach

                val session = runCatching {
                    json.decodeFromString(PadelSession.serializer(), payload)
                }.getOrNull() ?: return@forEach

                // Si la sesión ya está sincronizada, un reenvío del reloj no debe
                // devolverla a la cola.
                val existing = container.sessions.get(session.sessionId)
                if (existing != null) return@forEach

                container.sessions.save(session)
            }
        }
        dataEvents.release()

        SyncScheduler.requestSyncNow(this)
    }

    private companion object {
        const val PATH_PREFIX = "/padel/session"
        const val KEY_SESSION_JSON = "session_json"
    }
}
