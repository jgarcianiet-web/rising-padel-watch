package com.risingpadel.core.training

import com.risingpadel.core.model.ShotType
import kotlinx.serialization.Serializable

/** Un ejercicio: tantos golpes de un tipo. */
@Serializable
data class PasoDeRutina(
    val type: ShotType,
    val golpes: Int,
) {
    init {
        require(golpes > 0) { "un paso sin golpes no es un ejercicio" }
    }
}

/**
 * Un entrenamiento con estructura: la lista de ejercicios que el reloj va cantando.
 *
 * Es lo que separa a esta app de un contador de golpes. Un contador te dice, al acabar,
 * que diste 312 golpes; una rutina te dice **qué hacer ahora** y lleva la cuenta ella
 * sola, que es lo que hace falta cuando estás en la pista con la pala en la mano y no
 * puedes ir mirando el móvil ni acordarte de por dónde ibas.
 *
 * No tiene nada que ver con el modo de datos de entrenamiento, aunque se parezcan: aquel
 * graba señal cruda para etiquetar y solo lo usa quien construye el dataset. Esto es una
 * sesión normal, que se guarda en el historial y cuenta para el nivel, con un guion.
 */
@Serializable
data class Rutina(
    val id: String,
    val nombre: String,
    /** Para qué sirve, en una línea. Es lo que se lee al elegirla. */
    val proposito: String,
    val pasos: List<PasoDeRutina>,
) {
    val golpesTotales: Int get() = pasos.sumOf { it.golpes }

    companion object {
        /**
         * Las rutinas de fábrica.
         *
         * Cuatro y no veinte a propósito: en una pantalla de 45 mm una lista larga es
         * una lista que no se lee. Cubren las tres cosas que se entrenan en pádel —fondo,
         * red y golpes altos— más una completa para el día que hay pista y ganas.
         */
        val DE_FABRICA: List<Rutina> = listOf(
            Rutina(
                id = "calentamiento",
                nombre = "Calentamiento",
                proposito = "Entrar en calor sin forzar, de fondo a red",
                pasos = listOf(
                    PasoDeRutina(ShotType.FOREHAND, 20),
                    PasoDeRutina(ShotType.BACKHAND, 20),
                    PasoDeRutina(ShotType.FOREHAND_VOLLEY, 15),
                    PasoDeRutina(ShotType.BACKHAND_VOLLEY, 15),
                ),
            ),
            Rutina(
                id = "red",
                nombre = "Red",
                proposito = "Volea y bandeja: el juego de la red",
                pasos = listOf(
                    PasoDeRutina(ShotType.FOREHAND_VOLLEY, 30),
                    PasoDeRutina(ShotType.BACKHAND_VOLLEY, 30),
                    PasoDeRutina(ShotType.BANDEJA, 25),
                ),
            ),
            Rutina(
                id = "altos",
                nombre = "Golpes altos",
                proposito = "Bandeja, víbora y remate, que es donde se decide el punto",
                pasos = listOf(
                    PasoDeRutina(ShotType.BANDEJA, 25),
                    PasoDeRutina(ShotType.VIBORA, 20),
                    PasoDeRutina(ShotType.SMASH, 15),
                ),
            ),
            Rutina(
                id = "completa",
                nombre = "Completa",
                proposito = "Todo el repertorio, una vez cada golpe",
                pasos = listOf(
                    PasoDeRutina(ShotType.SERVE, 15),
                    PasoDeRutina(ShotType.FOREHAND, 25),
                    PasoDeRutina(ShotType.BACKHAND, 25),
                    PasoDeRutina(ShotType.FOREHAND_VOLLEY, 20),
                    PasoDeRutina(ShotType.BACKHAND_VOLLEY, 20),
                    PasoDeRutina(ShotType.BANDEJA, 20),
                    PasoDeRutina(ShotType.VIBORA, 15),
                    PasoDeRutina(ShotType.SMASH, 15),
                ),
            ),
        )
    }
}

/** Cómo va el paso que se está haciendo ahora mismo. */
data class ProgresoDeRutina(
    val paso: PasoDeRutina,
    /** Índice del paso, empezando en 0. */
    val indice: Int,
    val totalPasos: Int,
    /** Golpes válidos dados en este paso. */
    val hechos: Int,
    /** Golpes de otro tipo que se dieron durante el paso: no cuentan, pero se avisan. */
    val fueraDeTipo: Int,
) {
    val restantes: Int get() = (paso.golpes - hechos).coerceAtLeast(0)
    val fraccion: Float get() = (hechos.toFloat() / paso.golpes).coerceIn(0f, 1f)
}

/** Qué acaba de pasar al registrar un golpe. Es lo que decide si el reloj vibra. */
enum class EventoDeRutina {
    /** Golpe del tipo que tocaba: se suma y sigue. */
    CUENTA,

    /** Golpe de otro tipo: no cuenta. */
    NO_CUENTA,

    /** Con este se completó el paso y ya se pasó al siguiente. */
    PASO_COMPLETADO,

    /** Con este se completó el último paso: la rutina ha terminado. */
    TERMINADA,

    /** Ya estaba terminada; no hay nada que contar. */
    YA_TERMINADA,
}

/**
 * El estado de una rutina en marcha.
 *
 * Cuenta **solo los golpes del tipo que toca**. Un revés durante la tanda de derechas no
 * suma, y no suma a propósito: si contara cualquier golpe, la rutina se completaría sola
 * peloteando y dejaría de ser un entrenamiento para ser un cronómetro. Lo que sí hace es
 * llevar la cuenta de los golpes fuera de tipo, que es información útil al acabar
 * ("cambiaste de golpe 14 veces durante la tanda de bandejas").
 *
 * Vive en el core y no en el reloj porque la lógica de avance tiene que ser idéntica en
 * watchOS y en Wear OS, y porque así se puede probar sin un reloj delante.
 */
class RutinaEnCurso(val rutina: Rutina) {

    private var indice = 0
    private var hechos = 0
    private var fueraDeTipo = 0

    /** Golpes válidos de cada paso ya cerrado, en orden. Es el resumen del final. */
    private val completados = mutableListOf<Int>()

    var terminada: Boolean = false
        private set

    val progreso: ProgresoDeRutina?
        get() = if (terminada) null else ProgresoDeRutina(
            paso = rutina.pasos[indice],
            indice = indice,
            totalPasos = rutina.pasos.size,
            hechos = hechos,
            fueraDeTipo = fueraDeTipo,
        )

    /** Golpes válidos totales de toda la rutina. */
    val golpesValidos: Int get() = completados.sum() + hechos

    /**
     * Registra un golpe detectado y dice qué ha pasado.
     *
     * Un golpe `UNKNOWN` nunca cuenta: el detector no supo qué era, y darlo por bueno
     * sería completar el ejercicio con golpes que a lo mejor ni eran del tipo pedido.
     */
    fun onShot(type: ShotType): EventoDeRutina {
        if (terminada) return EventoDeRutina.YA_TERMINADA
        val paso = rutina.pasos[indice]
        if (type != paso.type || type == ShotType.UNKNOWN) {
            fueraDeTipo++
            return EventoDeRutina.NO_CUENTA
        }

        hechos++
        if (hechos < paso.golpes) return EventoDeRutina.CUENTA

        completados.add(hechos)
        hechos = 0
        fueraDeTipo = 0
        indice++
        if (indice >= rutina.pasos.size) {
            terminada = true
            return EventoDeRutina.TERMINADA
        }
        return EventoDeRutina.PASO_COMPLETADO
    }

    /**
     * Salta al siguiente paso sin terminarlo.
     *
     * Hace falta de verdad: la máquina de bolas se queda sin pelotas, al compañero le
     * duele el hombro, o el detector no está reconociendo un golpe y el ejercicio se
     * queda atascado. Sin una salida, la rutina pasa de ayudar a estorbar.
     */
    fun saltarPaso(): EventoDeRutina {
        if (terminada) return EventoDeRutina.YA_TERMINADA
        completados.add(hechos)
        hechos = 0
        fueraDeTipo = 0
        indice++
        if (indice >= rutina.pasos.size) {
            terminada = true
            return EventoDeRutina.TERMINADA
        }
        return EventoDeRutina.PASO_COMPLETADO
    }

    /** Cuántos golpes válidos se hicieron en cada paso, para el resumen final. */
    fun resumen(): List<Pair<PasoDeRutina, Int>> {
        val hechosPorPaso = completados.toMutableList()
        if (!terminada) hechosPorPaso.add(hechos)
        return rutina.pasos.take(hechosPorPaso.size).mapIndexed { i, paso ->
            paso to hechosPorPaso[i]
        }
    }
}
