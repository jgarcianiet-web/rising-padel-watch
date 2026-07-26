package com.risingpadel.wear.transport

import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.WearableListenerService
import com.risingpadel.core.settings.DeviceSettings
import com.risingpadel.wear.data.WearSettings
import kotlinx.coroutines.runBlocking

/**
 * Recibe los ajustes que el móvil replica por el Data Layer.
 *
 * Es un servicio y no un listener de la Activity porque los ajustes tienen que llegar
 * aunque la app del reloj esté cerrada: el jugador los cambia en el móvil el día antes y
 * el reloj tiene que estar ya configurado cuando llega a la pista.
 */
class SettingsListenerService : WearableListenerService() {

    override fun onDataChanged(events: DataEventBuffer) {
        val settings = events
            .filter { it.type == DataEvent.TYPE_CHANGED }
            .filter { it.dataItem.uri.path == PATH }
            .mapNotNull { event ->
                DataMapItem.fromDataItem(event.dataItem)
                    .dataMap
                    .getString(KEY_SETTINGS_JSON)
                    ?.let { DeviceSettings.decode(it) }
            }
            // Si llegan varios en el mismo lote, solo importa el más reciente.
            .maxByOrNull { it.updatedAtEpochMs }
            ?: return

        // `onDataChanged` corre en un hilo de fondo del servicio y el sistema puede
        // pararlo en cuanto vuelve, así que hay que escribir antes de salir.
        runBlocking { WearSettings(applicationContext).applyRemote(settings) }
    }

    companion object {
        const val PATH = "/padel/settings"
        const val KEY_SETTINGS_JSON = "settings_json"
    }
}
