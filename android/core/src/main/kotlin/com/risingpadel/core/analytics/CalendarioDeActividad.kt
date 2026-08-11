package com.risingpadel.core.analytics

import com.risingpadel.core.liga.Fechas

/** Un día del calendario. `golpes == 0` es un día sin jugar, no un hueco. */
data class DiaDeActividad(
    val fechaISO: String,
    val sesiones: Int,
    val golpes: Int,
    val minutos: Int,
) {
    val jugado: Boolean get() = sesiones > 0
}

/**
 * Las últimas semanas de juego en una cuadrícula, un cuadro por día.
 *
 * El histórico es una lista y una lista contesta "¿qué hice el martes?" pero no "¿estoy
 * jugando menos que el mes pasado?". Esa segunda pregunta es la que hace que alguien
 * vuelva a abrir la app, y se contesta de un vistazo o no se contesta: un hueco de dos
 * semanas se ve, no se lee.
 *
 * Las semanas empiezan en lunes y la última columna es la semana en curso, con los días
 * que aún no han llegado marcados como futuros. Así la cuadrícula no cambia de forma cada
 * día: solo se va llenando.
 */
data class CalendarioDeActividad(
    /** Una lista por semana, de lunes a domingo, siempre siete días. */
    val semanas: List<List<DiaDeActividad>>,
    /** El día con más golpes del periodo, para escalar la intensidad del color. */
    val maxGolpes: Int,
    val diasJugados: Int,
    /** Días seguidos jugando que acaban hoy o ayer. 0 si hace más de un día que no juegas. */
    val rachaActual: Int,
    /** La racha más larga del periodo. */
    val mejorRacha: Int,
) {
    val hayDatos: Boolean get() = diasJugados > 0

    /** Media de días jugados por semana en el periodo, para poner la racha en contexto. */
    val diasPorSemana: Float
        get() = if (semanas.isEmpty()) 0f else diasJugados.toFloat() / semanas.size

    companion object {

        /** Doce semanas: un trimestre entra en el ancho de un móvil sin apretar. */
        const val SEMANAS_POR_DEFECTO = 12

        /**
         * Construye el calendario.
         *
         * @param porDia lo que se jugó cada día, con la fecha ya en local. La conversión
         *   de epoch a fecha la hace cada plataforma porque depende del huso del móvil, y
         *   meterla aquí obligaría al core a saber de zonas horarias para nada.
         * @param hastaISO el último día de la cuadrícula, normalmente hoy.
         */
        fun de(
            porDia: List<DiaDeActividad>,
            hastaISO: String,
            semanas: Int = SEMANAS_POR_DEFECTO,
        ): CalendarioDeActividad? {
            val hasta = Fechas.diasDesdeEpoca(hastaISO) ?: return null
            val diaSemana = Fechas.diaDeLaSemana(hastaISO) ?: return null

            // Se termina el domingo de la semana en curso y se retrocede N semanas
            // enteras: así todas las columnas tienen siete días y ninguna sale coja.
            val ultimo = hasta + (6 - diaSemana)
            val primero = ultimo - (semanas * 7 - 1)

            val indice = porDia.associateBy { it.fechaISO }

            val cuadricula = (0 until semanas).map { semana ->
                (0 until 7).map { dia ->
                    val fecha = Fechas.isoDesdeDias(primero + semana * 7 + dia)
                    indice[fecha] ?: DiaDeActividad(fecha, sesiones = 0, golpes = 0, minutos = 0)
                }
            }

            val enOrden = cuadricula.flatten().filter {
                (Fechas.diasDesdeEpoca(it.fechaISO) ?: 0) <= hasta
            }
            val jugados = enOrden.count { it.jugado }

            // La racha en curso se cuenta hacia atrás desde hoy, y se le perdona el día
            // de hoy: a las nueve de la mañana nadie ha jugado todavía, y romperle la
            // racha a alguien por eso sería castigarle por madrugar.
            var racha = 0
            var desde = enOrden.size - 1
            if (desde >= 0 && !enOrden[desde].jugado) desde--
            while (desde >= 0 && enOrden[desde].jugado) {
                racha++
                desde--
            }

            var mejor = 0
            var seguidos = 0
            for (dia in enOrden) {
                if (dia.jugado) {
                    seguidos++
                    if (seguidos > mejor) mejor = seguidos
                } else {
                    seguidos = 0
                }
            }

            return CalendarioDeActividad(
                semanas = cuadricula,
                maxGolpes = enOrden.maxOfOrNull { it.golpes } ?: 0,
                diasJugados = jugados,
                rachaActual = racha,
                mejorRacha = mejor,
            )
        }

        /**
         * Agrupa sesiones por día en el huso del dispositivo.
         *
         * El puente entre el historial y la cuadrícula. Va aquí y no en la cuadrícula
         * porque "qué día fue este instante" es justo lo que depende de dónde estés, y el
         * resto del cálculo no depende de nada.
         */
        fun porDia(
            sesiones: List<com.risingpadel.core.model.PadelSession>,
            zona: java.time.ZoneId = java.time.ZoneId.systemDefault(),
        ): List<DiaDeActividad> = sesiones
            .groupBy {
                java.time.Instant.ofEpochMilli(it.startedAtEpochMs).atZone(zona).toLocalDate()
                    .toString()
            }
            .map { (fecha, delDia) ->
                DiaDeActividad(
                    fechaISO = fecha,
                    sesiones = delDia.size,
                    golpes = delDia.sumOf { it.totalShots },
                    minutos = delDia.sumOf { (it.durationSeconds / 60).toInt() },
                )
            }

        fun hoyISO(zona: java.time.ZoneId = java.time.ZoneId.systemDefault()): String =
            java.time.LocalDate.now(zona).toString()
    }
}
