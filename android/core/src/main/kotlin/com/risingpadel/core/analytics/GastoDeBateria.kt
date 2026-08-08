package com.risingpadel.core.analytics

import com.risingpadel.core.model.PadelSession

/**
 * Cuánta batería gasta medir una sesión, en porcentaje por hora.
 *
 * Es la primera pregunta que hace cualquiera antes de fiarse de un reloj deportivo, y la
 * única que no se puede contestar leyendo código: depende del modelo de reloj, de su
 * edad, del frío que haga y de si el pulso estaba encendido. La única respuesta honesta
 * es medirla en el reloj de quien pregunta.
 *
 * Se descartan las sesiones que no pueden decir nada:
 *
 * - **Cortas.** En quince minutos el sistema puede no haber movido el indicador ni un
 *   punto, y dividir 1 punto entre 0,25 h da un 4%/h inventado. Con menos de media hora
 *   el ruido manda sobre la señal.
 * - **Cargando.** Si el reloj estuvo en el cargador, la batería sube y el gasto sale
 *   negativo. Eso no es "gastó poco", es que no se midió nada.
 * - **Sin dato.** Un reloj que no supo dar el nivel no cuenta como que gastó cero.
 */
data class GastoDeBateria(
    /** Porcentaje por hora, la cifra que se enseña. */
    val porHora: Float,
    /** Sobre cuántas sesiones se calculó: es lo que dice si el número vale algo. */
    val sesiones: Int,
    /** Horas de juego que sostienen la media. */
    val horas: Float,
) {
    /**
     * Horas de reloj a este ritmo, partiendo de la batería llena. Es el número que la
     * gente quiere de verdad: "¿me llega para el torneo del sábado?".
     */
    val horasDeAutonomia: Float get() = if (porHora <= 0) 0f else 100f / porHora

    companion object {
        /** Por debajo de esta duración, la resolución del indicador de batería manda. */
        const val MIN_MINUTOS = 30

        /** Con una sesión suelta no se promedia nada: fue un día, no una medida. */
        const val MIN_SESIONES = 2

        /** Null si todavía no hay con qué contestar. Mejor eso que un número inventado. */
        fun de(sesiones: List<PadelSession>): GastoDeBateria? {
            val utiles = sesiones.mapNotNull { sesion ->
                val bateria = sesion.battery ?: return@mapNotNull null
                val horas = sesion.durationSeconds / 3600f
                if (horas * 60 < MIN_MINUTOS) return@mapNotNull null
                // Cargando durante la sesión: el dato no vale. Un consumo de cero sí
                // vale — es raro, pero es una medida.
                if (bateria.consumido < 0) return@mapNotNull null
                bateria.consumido to horas
            }
            if (utiles.size < MIN_SESIONES) return null

            val puntos = utiles.sumOf { it.first }
            val horas = utiles.map { it.second }.sum()
            if (horas <= 0f) return null

            return GastoDeBateria(
                // Se suman puntos y horas y se divide una vez, en vez de promediar los
                // ritmos de cada sesión: así una sesión de veinte minutos no pesa lo
                // mismo que una de tres horas para decidir el ritmo del reloj.
                porHora = puntos / horas,
                sesiones = utiles.size,
                horas = horas,
            )
        }
    }
}
