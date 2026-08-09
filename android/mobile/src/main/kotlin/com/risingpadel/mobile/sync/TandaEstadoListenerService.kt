package com.risingpadel.mobile.sync

import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import com.risingpadel.core.sync.EstadoDeTanda

/**
 * Recoge el estado que devuelve el reloj tras cada orden de tanda.
 *
 * Es un servicio y no un listener de la Activity porque el reloj puede contestar cuando
 * el móvil ya tiene la pantalla apagada —la orden viaja rápido, la respuesta puede tardar
 * si el reloj estaba dormido— y perder la respuesta dejaría el mando con el contador
 * congelado en el número de hace dos tandas.
 */
class TandaEstadoListenerService : WearableListenerService() {

    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != EstadoDeTanda.PATH) return
        EstadoDeTanda.decode(String(event.data))?.let(BuzonDeTanda::publicar)
    }
}
