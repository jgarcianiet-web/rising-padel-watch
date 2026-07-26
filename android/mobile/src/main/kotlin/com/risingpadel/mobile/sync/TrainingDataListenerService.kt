package com.risingpadel.mobile.sync

import com.google.android.gms.wearable.ChannelClient
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import com.risingpadel.mobile.PadelMobileApp
import java.io.File

/**
 * Recibe el fichero de datos de entrenamiento que envía el reloj.
 *
 * **Esto no toca la cola de sincronización con la liga.** Los datos de entrenamiento se
 * quedan en el móvil hasta que el usuario los exporta a mano; no se suben a ningún sitio.
 * Ver `docs/training-data.md`.
 */
class TrainingDataListenerService : WearableListenerService() {

    override fun onChannelOpened(channel: ChannelClient.Channel) {
        if (channel.path != PATH) return

        val container = (application as PadelMobileApp).container
        val destination = container.settings.trainingDataFile
        destination.parentFile?.mkdirs()

        // Se sobrescribe en vez de acumular: el reloj manda siempre el fichero completo,
        // así que añadir duplicaría todo lo enviado en el envío anterior.
        val temporary = File(destination.parentFile, "${destination.name}.part")

        Wearable.getChannelClient(this)
            .receiveFile(channel, android.net.Uri.fromFile(temporary), false)
            .addOnCompleteListener {
                if (it.isSuccessful && temporary.exists() && temporary.length() > 0) {
                    destination.delete()
                    temporary.renameTo(destination)
                } else {
                    temporary.delete()
                }
            }
    }

    companion object {
        const val PATH = "/padel/training-data"
    }
}
