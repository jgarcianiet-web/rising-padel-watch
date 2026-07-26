package com.risingpadel.mobile.sync

import android.content.Context
import android.util.Log
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import com.risingpadel.core.settings.DeviceSettings
import kotlinx.coroutines.tasks.await

/**
 * Replica los ajustes al reloj por el Data Layer.
 *
 * `DataClient` y no `MessageClient` porque el item **persiste**: el reloj recibe el
 * último estado en cuanto vuelve a estar a tiro, aunque estuviera apagado cuando se
 * cambió el ajuste. Con un mensaje habría que acertar con el momento.
 *
 * La ruta es fija (un único item que se sobrescribe), no una por cambio: lo que importa
 * es el estado actual, no el historial de ediciones.
 */
class WatchSettingsSender(context: Context) {

    private val dataClient = Wearable.getDataClient(context)

    suspend fun send(settings: DeviceSettings) {
        val request = PutDataMapRequest.create(PATH).apply {
            dataMap.putString(KEY_SETTINGS_JSON, DeviceSettings.encode(settings))
            // El Data Layer descarta un item byte a byte idéntico al anterior. La marca
            // de tiempo ya va dentro del JSON, así que cualquier cambio real lo mueve.
            dataMap.putLong(KEY_UPDATED_AT, settings.updatedAtEpochMs)
        }.asPutDataRequest().setUrgent()

        // Sin reloj emparejado esto falla, y no es un error que deba ver el usuario: la
        // app de móvil funciona igual sin reloj.
        runCatching { dataClient.putDataItem(request).await() }
            .onFailure { Log.i(TAG, "Ajustes no replicados al reloj: ${it.message}") }
    }

    private companion object {
        const val PATH = "/padel/settings"
        const val KEY_SETTINGS_JSON = "settings_json"
        const val KEY_UPDATED_AT = "updated_at"
        const val TAG = "WatchSettingsSender"
    }
}
