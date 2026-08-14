package com.risingpadel.core.sync

import com.risingpadel.core.detection.DescartesDelDetector
import com.risingpadel.core.model.ShotType
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * El mando a distancia de las tandas de entrenamiento: el móvil ordena, el reloj obedece.
 *
 * Existe porque la tanda de datos casi nunca la graba quien lleva el reloj. Lo normal es
 * ponérselo a otra persona y dirigirla desde fuera —"ahora treinta derechas", "ahora
 * bandejas"— y con los botones solo en la muñeca hay que parar el ejercicio, quitarle el
 * reloj, cambiar el tipo y volver a empezar. Eso rompe la tanda y, peor, invita a grabar
 * menos tandas de las que hacen falta.
 *
 * En Wear OS las órdenes van por `MessageClient`, que despierta el
 * `WearableListenerService` del reloj aunque su app esté cerrada y entrega cada mensaje
 * una sola vez. No van por `DataClient`: un data item se reentrega al reconectar, y una
 * orden reentregada arrancaría una tanda que nadie ha pedido — el mismo motivo por el
 * que en el lado Apple esto no viaja por contexto de aplicación.
 */
@Serializable
enum class AccionDeTanda {
    /** No cambia nada: solo pregunta cómo va. Es lo que refresca el contador. */
    @SerialName("estado")
    ESTADO,

    @SerialName("iniciar")
    INICIAR,

    @SerialName("parar")
    PARAR,

    /** Manda al móvil lo que haya guardado. */
    @SerialName("enviar")
    ENVIAR,
}

/** Una orden del móvil al reloj. */
@Serializable
data class OrdenDeTanda(
    val accion: AccionDeTanda,
    /** Tipo de golpe que se va a grabar. Solo lo mira `INICIAR`. */
    val etiqueta: ShotType? = null,
    /** Cuándo se dio la orden. Nil en órdenes de versiones viejas. */
    val creadoEpochMs: Long? = null,
) {
    /**
     * ¿Sigue vigente esta orden? Las de `ESTADO` siempre lo están: no cambian nada.
     */
    fun vigente(ahoraEpochMs: Long): Boolean {
        if (accion == AccionDeTanda.ESTADO) return true
        val creado = creadoEpochMs ?: return true
        return ahoraEpochMs - creado <= MAX_ANTIGUEDAD_MS
    }

    fun encode(): String = JSON.encodeToString(serializer(), this)

    companion object {
        /** La ruta del mensaje en el Data Layer. Una sola, compartida por los dos lados. */
        const val PATH = "/padel/mando-tanda"

        /**
         * Una orden puede tardar en llegar si el reloj estaba sin cobertura. Pasado este
         * rato ya no se obedece: arrancar una tanda diez minutos después de pedirla, con
         * el reloj otra vez en la muñeca de otro, es peor que no arrancarla.
         */
        const val MAX_ANTIGUEDAD_MS: Long = 3 * 60_000

        fun decode(json: String): OrdenDeTanda? =
            runCatching { JSON.decodeFromString(serializer(), json) }.getOrNull()
    }
}

/** Lo que el reloj contesta a cualquier orden: su estado entero. */
@Serializable
data class EstadoDeTanda(
    val grabando: Boolean,
    val etiqueta: ShotType,
    /** Golpeos capturados en la tanda en curso. */
    val capturadosEnTanda: Int,
    /** Golpeos guardados en el reloj, de todas las tandas. */
    val guardadosEnTotal: Int,
    val kilobytes: Int,
    /** Quién lleva el reloj ahora mismo, según los ajustes replicados. */
    val alias: String,
    /** Su nivel técnico declarado, que es lo que ancla la escala. Nil = sin declarar. */
    val nivel: Int? = null,
    /**
     * El reloj avisa de que sin permiso de entreno la tanda puede cortarse al apagarse la
     * pantalla. Devolver diez golpes de cincuenta en silencio sería peor que fallar.
     */
    val sensoresPuedenPararse: Boolean = false,
    /**
     * Por qué la última orden no hizo lo que se le pidió, si es que no lo hizo. Nil = todo
     * en orden. Sin esto, pulsar "Grabar" durante un partido deja un botón que parece roto
     * en vez de una explicación.
     */
    val motivo: String? = null,
    /**
     * Los swings que el detector tiró en esta tanda, con el motivo. Es lo que convierte
     * "no me coge la mitad de las bandejas" en un número con su umbral culpable al lado.
     */
    val descartes: DescartesDelDetector? = null,
    /**
     * Segundos de tanda grabados, si hay una en marcha. Es el contador que siempre
     * avanza: la prueba de que se está guardando algo, vea el detector lo que vea.
     */
    val segundosDeTanda: Int? = null,
) {
    fun encode(): String = JSON.encodeToString(serializer(), this)

    companion object {
        /** La ruta por la que el reloj devuelve su estado. */
        const val PATH = "/padel/estado-tanda"

        fun decode(json: String): EstadoDeTanda? =
            runCatching { JSON.decodeFromString(serializer(), json) }.getOrNull()
    }
}

/**
 * Tolerante con campos desconocidos a propósito: los dos lados se actualizan por
 * separado —el reloj por Play Store, el móvil también— y un mando que deja de funcionar
 * porque la otra mitad añadió un campo es un mando roto en pista.
 */
private val JSON = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
}
