package com.risingpadel.core.liga

import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * El análisis de pareja del §36.11: **"¿juego mejor con este?"**
 *
 * Es la pregunta que la liga no sabía contestar. El panel de temporada ya enseñaba
 * victorias y derrotas por compañero ([LigaMetrics.conPareja]), pero un 60 % de
 * victorias con alguien no dice nada si no se sabe cuánto ganas con los demás: puede ser
 * que juegues mejor con él, o que con él te toquen rivales más flojos. Lo que contesta la
 * pregunta es **la diferencia** entre jugar con esa pareja y jugar con cualquier otra.
 *
 * ### Lo que NO se mide, y por qué
 *
 * **El rendimiento del compañero no existe aquí.** El ejemplo del documento de producto
 * pone una nota para los dos jugadores, y hoy eso es imposible: la app solo tiene lo que
 * midió **el reloj de su dueño**. Ponerle una nota al compañero sería inventarla a partir
 * del resultado del partido, que es justo lo que este repo no hace. El documento describe
 * un futuro con dos cuentas conectadas; el hueco está preparado en
 * [RendimientoConPareja.nivelMedioDelCompanero], que hoy es siempre null y lo seguirá
 * siendo hasta que exista ese emparejamiento de cuentas.
 *
 * **El lado del compañero tampoco.** Del ejemplo del documento ("el lado derecho genera
 * más ataque, el izquierdo asume la defensa") aquí solo sale la mitad que se puede medir:
 * el reparto de TUS golpes según con quién juegas, en [RepartoDeGolpe]. Si con él das más
 * bandejas y menos globos, eso sí está medido, porque son golpes tuyos. Lo que hace él al
 * otro lado de la pista no lo ha visto nadie.
 *
 * ### El mínimo de partidos
 *
 * Cinco, [MINIMO_PARTIDOS]. Por debajo, un partido solo mueve el porcentaje de victorias
 * más de veinte puntos: con tres partidos, ganar uno más pasa de 33 % a 66 % y el
 * veredicto "juegas mejor con él" cambia con un sábado. Cinco es además la ventana con la
 * que ya se mide el nivel de un golpe ([ProgresoDeGolpes.VENTANA]), por el mismo motivo —
 * un partido suelto se mueve mucho, hay días.
 *
 * El mínimo se aplica **a los partidos que traen el dato, no al total**. Cinco partidos
 * juntos de los que solo dos midieron nivel dan una media de dos partidos, no de cinco, y
 * eso no es una muestra por mucho que el recuento de arriba diga cinco.
 */
data class AnalisisDePareja(
    /** La grafía del compañero tal como se pidió el análisis. */
    val companero: String,
    val juntos: RendimientoConPareja,
    /**
     * Con esa pareja contra con cualquier otra. Null cuando no hay con qué comparar:
     * hace falta el mínimo de partidos **a los dos lados**. Comparar contra tres
     * partidos con otros es comparar contra nada.
     */
    val comparacion: ComparacionDePareja?,
    /** Qué golpes das más con esa pareja que con el resto. Vacío sin muestra. */
    val reparto: List<RepartoDeGolpe>,
    val posicion: EquilibrioDePosicion,
    /** El mínimo con el que se calculó, para que la vista pueda decir cuánto falta. */
    val minimo: Int,
) {
    /** ¿Hay partidos suficientes para decir algo de esta pareja? */
    val suficiente: Boolean get() = juntos.partidos >= minimo

    /** Cuántos partidos faltan para poder analizarla. 0 si ya llega. */
    val partidosQueFaltan: Int get() = (minimo - juntos.partidos).coerceAtLeast(0)
}

/**
 * Lo que rindes en un conjunto de partidos: **lo tuyo**, que es lo único que el reloj
 * midió.
 *
 * Los recuentos ([partidos], [victorias]…) van siempre: son hechos, no estimaciones, y
 * decirle a alguien "solo lleváis 3 partidos juntos" es precisamente lo honesto. Lo que
 * se calla por debajo del mínimo son los números derivados — el porcentaje y la media —,
 * que son los que aparentan una precisión que no tienen.
 */
data class RendimientoConPareja(
    val partidos: Int,
    /**
     * Partidos con resultado anotado. Un entreno guardado sin marcador no cuenta como
     * derrota: metido en el denominador, entrenar bajaría tu porcentaje de victorias.
     */
    val conResultado: Int,
    val victorias: Int,
    val derrotas: Int,
    /** Partidos en los que el reloj llegó a medir nivel de sesión. */
    val conNivel: Int,
    /** % de victorias sobre [conResultado]. Null si no llega al mínimo. */
    val pctVictorias: Int?,
    /**
     * Tu nivel medio de sesión en esos partidos. Null si no llega al mínimo.
     *
     * Es el nivel que mide el reloj ([LigaMetrics.nivelDeSesion]) y **no** el nivel
     * Playtomic del partido. La diferencia decide el análisis entero: el Playtomic es
     * acumulativo y apenas se mueve, así que comparar dos compañeros con él compararía
     * las fechas en las que jugaste con cada uno —quien te tocó en junio "sale mejor"
     * que quien te tocó en enero— en vez de cómo jugaste tú.
     */
    val nivelMedio: Double?,
    /**
     * El nivel medio del compañero: **hoy siempre null, y a propósito**.
     *
     * La app solo tiene los datos del reloj de su dueño. Hasta que existan dos cuentas
     * conectadas (el futuro que describe el §36.11), esto no se puede medir, y una nota
     * deducida del resultado del partido sería un número inventado con aspecto de dato.
     * El hueco queda aquí para que el día que llegue el emparejamiento se rellene sin
     * mover nada más.
     */
    val nivelMedioDelCompanero: Double? = null,
)

/** Jugar con esa pareja frente a jugar con cualquier otra. */
data class ComparacionDePareja(
    val con: RendimientoConPareja,
    val sin: RendimientoConPareja,
) {
    /** Cuánto sube (o baja) tu nivel medio con esa pareja. Null si falta algún lado. */
    val deltaNivel: Double?
        get() {
            val a = con.nivelMedio ?: return null
            val b = sin.nivelMedio ?: return null
            return a - b
        }

    /** Lo mismo con el porcentaje de victorias, en puntos. */
    val deltaPctVictorias: Int?
        get() {
            val a = con.pctVictorias ?: return null
            val b = sin.pctVictorias ?: return null
            return a - b
        }

    /**
     * El veredicto, que es lo que el jugador viene a leer. Null cuando no se puede decir.
     *
     * Lo decide **el nivel y no el porcentaje de victorias**: ganar depende de quién
     * estaba al otro lado de la red, y la app no sabe el nivel de los rivales. El nivel
     * de sesión se mide en tu muñeca y no depende de contra quién juegues, así que es lo
     * único que compara dos compañeros de forma justa.
     */
    val veredicto: VeredictoDePareja?
        get() {
            val delta = deltaNivel ?: return null
            // Por debajo de una décima no hay diferencia que enseñar: el nivel se guarda
            // redondeado a una décima (ver LigaMapper), así que un delta de 0,03 es ruido
            // de redondeo con pinta de hallazgo.
            if (abs(delta) < AnalisisDeParejas.UMBRAL_NIVEL) return VeredictoDePareja.IGUAL
            return if (delta > 0) VeredictoDePareja.MEJOR else VeredictoDePareja.PEOR
        }
}

/** Cómo juegas con esa pareja comparado con el resto. */
enum class VeredictoDePareja { MEJOR, IGUAL, PEOR }

/**
 * Un golpe dentro del reparto de tu juego con esa pareja.
 *
 * Se compara **cuota** (qué parte de tus golpes son de ese tipo) y no volumen bruto, y la
 * diferencia importa: si con esa pareja juegas partidos más largos, das más de todo, y un
 * "+12 bandejas" solo estaría midiendo que el partido duró más. La cuota se normaliza
 * sola y es la que enseña el papel que ocupas en la pista, que es lo que pregunta el
 * documento. El volumen por partido se da igual porque es lo que el jugador reconoce.
 */
data class RepartoDeGolpe(
    val golpe: String,
    /** Golpes de ese tipo por partido con esa pareja. */
    val porPartidoCon: Double,
    /** Qué parte de tus golpes son de ese tipo con esa pareja, de 0 a 1. */
    val cuotaCon: Double,
    /** La misma cuota jugando con cualquier otro. Null si no hay base para comparar. */
    val cuotaSin: Double?,
) {
    /** Cuánto pesa más (o menos) ese golpe con esa pareja. Null sin comparación. */
    val diferencia: Double? get() = cuotaSin?.let { cuotaCon - it }

    /** La diferencia en puntos porcentuales, que es como se enseña. */
    val diferenciaEnPuntos: Int? get() = diferencia?.let { (it * 100).roundToInt() }
}

/**
 * De qué lado de la pista juegas con esa pareja.
 *
 * **Aviso sobre el dato**: `posicion` tiene "reves" por defecto en [LigaMatch] —lo exige
 * la compatibilidad con la copia de seguridad de la app Expo, donde el campo siempre
 * viene— así que un partido en el que nadie tocó el selector es indistinguible de uno
 * jugado de revés. Esto describe lo que hay apuntado, no afirma dónde estuviste.
 */
data class EquilibrioDePosicion(
    val enDerecha: Int,
    val enReves: Int,
    /** Qué parte de los partidos juegas de derecha (drive), 0 a 1. Null bajo el mínimo. */
    val cuotaDerecha: Double?,
    /**
     * "derecha", "reves" o null. Solo se afirma un lado fijo cuando cuatro de cada cinco
     * partidos caen del mismo ([AnalisisDeParejas.UMBRAL_LADO]); con un 60/40 el sitio os
     * lo vais repartiendo y decir "juegas de revés" sería redondear una costumbre que no
     * existe.
     */
    val ladoHabitual: String?,
) {
    val partidos: Int get() = enDerecha + enReves
}

/** Un compañero con lo que rindes a su lado: el mejor y el peor del ranking. */
data class CompaneroDestacado(
    val nombre: String,
    val rendimiento: RendimientoConPareja,
)

/**
 * El motor del análisis de pareja. Funciones puras: entran partidos, sale el análisis.
 */
object AnalisisDeParejas {

    /** Partidos mínimos para que un número derivado se pueda enseñar. Ver la cabecera. */
    const val MINIMO_PARTIDOS = 5

    /** Por debajo de una décima, el nivel no ha cambiado: se guarda con una decimal. */
    const val UMBRAL_NIVEL = 0.1

    /** Cuatro de cada cinco partidos del mismo lado para llamarlo tu lado. */
    const val UMBRAL_LADO = 0.8

    /**
     * Un partido guardado desde un entreno sin marcador. No cuenta como derrota: ver
     * [RendimientoConPareja.conResultado]. El mismo valor que usa `ResultadoDePartido` en
     * la app móvil, repetido aquí porque el core no depende de ella.
     */
    private const val SIN_RESULTADO = "sin resultado"

    /** La posición de drive, tal como la guarda el formulario de partido. */
    const val DERECHA = "derecha"
    const val REVES = "reves"

    /**
     * El análisis completo de una pareja.
     *
     * @param companero el nombre, con la grafía que sea: se compara sin mayúsculas.
     * @param partidos todos los partidos de los que se quiere sacar la comparación —
     *   normalmente los de la temporada en curso. Se reparten aquí en "con él" y "con
     *   cualquier otro".
     */
    fun de(
        companero: String,
        partidos: List<LigaMatch>,
        minimo: Int = MINIMO_PARTIDOS,
    ): AnalisisDePareja {
        val con = partidos.filter { juegaCon(it, companero) }
        // "Con cualquier otro" son los partidos con OTRO compañero apuntado, no todos los
        // demás. Un partido sin compañero escrito no es un partido con otra persona: es un
        // partido del que no se sabe con quién fue, y bien pudo ser con él. Meterlo en la
        // base de comparación sería decidir por el jugador.
        val sin = partidos.filter { it.companero.isNotBlank() && !juegaCon(it, companero) }

        val rendimientoCon = rendimiento(con, minimo)
        val rendimientoSin = rendimiento(sin, minimo)

        return AnalisisDePareja(
            companero = companero.trim(),
            juntos = rendimientoCon,
            comparacion =
                if (con.size >= minimo && sin.size >= minimo) {
                    ComparacionDePareja(con = rendimientoCon, sin = rendimientoSin)
                } else {
                    null
                },
            reparto = reparto(con, sin, minimo),
            posicion = equilibrio(con, minimo),
            minimo = minimo,
        )
    }

    /**
     * Los compañeros con los que has jugado, el que más veces primero. La lista del
     * selector de la pantalla. Sin filtro de mínimo: esconder a alguien del selector
     * haría imposible ver cuántos partidos os faltan para poder analizarlo.
     */
    fun companeros(partidos: List<LigaMatch>): List<String> =
        LigaMetrics.conPareja(partidos).map { it.nombre }

    /**
     * Los compañeros ordenados por cómo juegas tú a su lado, el mejor primero.
     *
     * Ordena por **nivel medio de sesión** y deja fuera a quien no llegue al mínimo de
     * partidos o a quien no tenga nivel medido: ver [ComparacionDePareja.veredicto] sobre
     * por qué el porcentaje de victorias no sirve para comparar compañeros entre sí. Sin
     * niveles el ranking no existe, y caer al porcentaje de victorias cambiaría
     * calladamente lo que significa "el mejor compañero".
     */
    fun ranking(
        partidos: List<LigaMatch>,
        minimo: Int = MINIMO_PARTIDOS,
    ): List<CompaneroDestacado> =
        companeros(partidos)
            .map { nombre ->
                CompaneroDestacado(nombre, rendimiento(partidos.filter { juegaCon(it, nombre) }, minimo))
            }
            .filter { it.rendimiento.partidos >= minimo && it.rendimiento.nivelMedio != null }
            .sortedWith(
                compareByDescending<CompaneroDestacado> { it.rendimiento.nivelMedio }
                    .thenBy { it.nombre },
            )

    /** El compañero con el que mejor juegas. Null si nadie llega al mínimo. */
    fun mejorCompanero(
        partidos: List<LigaMatch>,
        minimo: Int = MINIMO_PARTIDOS,
    ): CompaneroDestacado? = ranking(partidos, minimo).firstOrNull()

    /**
     * El compañero con el que peor juegas.
     *
     * Null si solo hay un compañero con muestra: el único que tienes no es "el peor" de
     * nada, y enseñarlo a la vez como mejor y como peor es una tontería que además suena
     * a reproche hacia una persona real.
     */
    fun peorCompanero(
        partidos: List<LigaMatch>,
        minimo: Int = MINIMO_PARTIDOS,
    ): CompaneroDestacado? = ranking(partidos, minimo).takeIf { it.size >= 2 }?.last()

    /** true si ese partido se jugó con esa persona. `companero` es texto libre. */
    fun juegaCon(match: LigaMatch, companero: String): Boolean {
        val buscado = companero.trim()
        if (buscado.isEmpty()) return false
        return LigaMetrics.partirNombres(match.companero).any { it.equals(buscado, ignoreCase = true) }
    }

    /** El rendimiento tuyo en un conjunto de partidos. Ver [RendimientoConPareja]. */
    fun rendimiento(partidos: List<LigaMatch>, minimo: Int = MINIMO_PARTIDOS): RendimientoConPareja {
        val conResultado = partidos.filter { it.resultado != SIN_RESULTADO }
        val victorias = conResultado.count { it.resultado == "victoria" }
        val derrotas = conResultado.count { it.resultado == "derrota" }
        val niveles = partidos.mapNotNull { LigaMetrics.nivelDeSesion(it) }

        return RendimientoConPareja(
            partidos = partidos.size,
            conResultado = conResultado.size,
            victorias = victorias,
            derrotas = derrotas,
            conNivel = niveles.size,
            // El mínimo se mide sobre los partidos que traen el dato, no sobre el total:
            // cinco partidos de los que dos midieron nivel son una media de dos.
            pctVictorias =
                if (conResultado.size >= minimo) {
                    (victorias * 100.0 / conResultado.size).roundToInt()
                } else {
                    null
                },
            nivelMedio = if (niveles.size >= minimo) niveles.average() else null,
        )
    }

    /**
     * El reparto de golpes con esa pareja frente al resto.
     *
     * **Un partido sin `golpesVolumen` no entra**: no es un partido de cero golpes, es un
     * partido que no se midió (se apuntó a mano, o el reloj no estaba). Dentro de un
     * partido que sí trae volumen, en cambio, un golpe que no aparece **sí** es un cero de
     * verdad: el reloj estuvo puesto y no vio ninguno.
     *
     * Lista vacía si no hay partidos medidos suficientes con esa pareja. La cuota de
     * comparación es null si los que no son con ella tampoco llegan.
     */
    fun reparto(
        con: List<LigaMatch>,
        sin: List<LigaMatch>,
        minimo: Int = MINIMO_PARTIDOS,
    ): List<RepartoDeGolpe> {
        val medidosCon = con.filter { !it.golpesVolumen.isNullOrEmpty() }
        if (medidosCon.size < minimo) return emptyList()
        val medidosSin = sin.filter { !it.golpesVolumen.isNullOrEmpty() }

        val sumasCon = sumaPorGolpe(medidosCon)
        val totalCon = sumasCon.porClave.values.sum()
        if (totalCon == 0) return emptyList()

        val sumasSin = sumaPorGolpe(medidosSin)
        val totalSin = sumasSin.porClave.values.sum()
        val haySin = medidosSin.size >= minimo && totalSin > 0

        return sumasCon.porClave.entries
            .map { (clave, cantidad) ->
                RepartoDeGolpe(
                    golpe = sumasCon.grafias.getValue(clave),
                    porPartidoCon = cantidad.toDouble() / medidosCon.size,
                    cuotaCon = cantidad.toDouble() / totalCon,
                    // Un golpe que nunca das con los demás es una cuota de 0 legítima:
                    // esos partidos sí se midieron. Distinto de no tener base, que es el
                    // null de arriba.
                    cuotaSin =
                        if (haySin) (sumasSin.porClave[clave] ?: 0).toDouble() / totalSin else null,
                )
            }
            // Primero lo que más destaca con esa pareja, que es lo que se viene a leer.
            // Los golpes sin comparación caen al final: no se han ganado un titular.
            .sortedWith(
                compareByDescending<RepartoDeGolpe> { it.diferencia ?: Double.NEGATIVE_INFINITY }
                    .thenByDescending { it.cuotaCon }
                    .thenBy { it.golpe },
            )
    }

    /** De qué lado juegas con esa pareja. Ver el aviso de [EquilibrioDePosicion]. */
    fun equilibrio(con: List<LigaMatch>, minimo: Int = MINIMO_PARTIDOS): EquilibrioDePosicion {
        val enDerecha = con.count { it.posicion == DERECHA }
        val enReves = con.count { it.posicion == REVES }
        val total = enDerecha + enReves
        if (total < minimo) {
            return EquilibrioDePosicion(enDerecha, enReves, cuotaDerecha = null, ladoHabitual = null)
        }
        val cuota = enDerecha.toDouble() / total
        return EquilibrioDePosicion(
            enDerecha = enDerecha,
            enReves = enReves,
            cuotaDerecha = cuota,
            ladoHabitual = when {
                cuota >= UMBRAL_LADO -> DERECHA
                cuota <= 1 - UMBRAL_LADO -> REVES
                else -> null
            },
        )
    }

    /**
     * Golpes sumados por clave en minúsculas, con la grafía de la primera vez aparte.
     *
     * Las dos cosas hacen falta: la clave es la que cruza los dos conjuntos (los partidos
     * importados traen los nombres como los escribió quien los metió a mano, y un
     * "Bandeja" con esa pareja y un "bandeja" con el resto tienen que cruzarse o la cuota
     * de comparación saldría cero); la grafía es la que se le enseña al jugador.
     */
    private class SumaDeGolpes(
        val porClave: LinkedHashMap<String, Int>,
        val grafias: LinkedHashMap<String, String>,
    )

    private fun sumaPorGolpe(partidos: List<LigaMatch>): SumaDeGolpes {
        val grafias = LinkedHashMap<String, String>()
        val sumas = LinkedHashMap<String, Int>()
        for (partido in partidos) {
            for (golpe in partido.golpesVolumen.orEmpty()) {
                if (golpe.cantidad <= 0) continue
                val clave = golpe.nombre.lowercase()
                grafias.getOrPut(clave) { golpe.nombre }
                sumas[clave] = (sumas[clave] ?: 0) + golpe.cantidad
            }
        }
        return SumaDeGolpes(sumas, grafias)
    }
}
