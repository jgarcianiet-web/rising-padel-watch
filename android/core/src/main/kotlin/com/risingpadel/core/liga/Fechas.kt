package com.risingpadel.core.liga

/**
 * Aritmética de fechas `yyyy-mm-dd`, sin `java.time` ni `Calendar`.
 *
 * Existe porque las fechas de la liga son cadenas y lo que hace falta de ellas es
 * **restar**: cuántos días quedan de temporada, en qué casilla del calendario cae un día.
 * Hacerlo con las fechas del sistema mete husos horarios y horarios de verano en un
 * problema que no los tiene: "del 1 de septiembre al 30 de junio" son los mismos días en
 * Madrid que en Buenos Aires.
 *
 * El algoritmo es el `days_from_civil` de Howard Hinnant: exacto para cualquier fecha del
 * calendario gregoriano proléptico, sin tablas ni casos especiales para los bisiestos. Se
 * copia igual en el core Swift para que los dos lados cuenten los mismos días.
 */
object Fechas {

    /** Día 0 = 1970-01-01. Null si la cadena no es una fecha. */
    fun diasDesdeEpoca(iso: String): Int? {
        val (anno, mes, dia) = partes(iso) ?: return null
        // Marzo pasa a ser el primer mes: así el 29 de febrero cae al final del año y
        // los bisiestos dejan de necesitar un caso aparte.
        val y = if (mes <= 2) anno - 1 else anno
        val era = (if (y >= 0) y else y - 399) / 400
        val yoe = y - era * 400
        val mp = if (mes > 2) mes - 3 else mes + 9
        val doy = (153 * mp + 2) / 5 + dia - 1
        val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /** El inverso: de día de época a `yyyy-mm-dd`. */
    fun isoDesdeDias(dias: Int): String {
        val z = dias + 719_468
        val era = (if (z >= 0) z else z - 146_096) / 146_097
        val doe = z - era * 146_097
        val yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        val y = yoe + era * 400
        val doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        val mp = (5 * doy + 2) / 153
        val dia = doy - (153 * mp + 2) / 5 + 1
        val mes = if (mp < 10) mp + 3 else mp - 9
        val anno = if (mes <= 2) y + 1 else y
        return "%04d-%02d-%02d".format(anno, mes, dia)
    }

    /** Días de [desde] a [hasta], negativo si [hasta] es anterior. Null si alguna falla. */
    fun diasEntre(desde: String, hasta: String): Int? {
        val a = diasDesdeEpoca(desde) ?: return null
        val b = diasDesdeEpoca(hasta) ?: return null
        return b - a
    }

    /** 0 = lunes … 6 = domingo. El 1970-01-01 fue jueves. */
    fun diaDeLaSemana(iso: String): Int? {
        val dias = diasDesdeEpoca(iso) ?: return null
        return ((dias + 3) % 7 + 7) % 7
    }

    private fun partes(iso: String): Triple<Int, Int, Int>? {
        val trozos = iso.split("-")
        if (trozos.size != 3) return null
        val anno = trozos[0].toIntOrNull() ?: return null
        val mes = trozos[1].toIntOrNull() ?: return null
        val dia = trozos[2].toIntOrNull() ?: return null
        if (mes !in 1..12 || dia !in 1..31) return null
        return Triple(anno, mes, dia)
    }
}
