package com.risingpadel.core.liga

import kotlinx.serialization.Serializable
import kotlin.math.roundToInt

/**
 * Un objetivo técnico de la temporada: **"Bandeja 2,6 → 3,5"**.
 *
 * Es distinto de los objetivos de partido que ya existían ("hacer 15 bandejas"), y los
 * dos hacen falta. El de partido es una tarea para hoy y se mide contando golpes; este
 * es una meta de nivel para la temporada entera y se mide con la nota del golpe, que es
 * la unidad en la que el jugador piensa su progreso.
 *
 * El golpe se guarda por **nombre** y no como enum, igual que en [LigaGolpeSesion]: es
 * lo que hace que una copia de seguridad de la app Expo entre aquí sin transformar, y
 * lo que permite que un objetivo sobre un golpe que hoy no existe (una chiquita, una
 * salida de pared) se guarde y espere sin romper nada.
 */
@Serializable
data class ObjetivoDeGolpe(
    /** El nombre del golpe, tal como lo escribe [com.risingpadel.core.model.GolpeVisible]. */
    val golpe: String,
    /** La nota de partida, la que tenía el jugador cuando se fijó el objetivo. */
    val notaInicial: Double,
    val notaObjetivo: Double,
)

/**
 * Un objetivo de golpe con lo que ha pasado desde que se fijó.
 *
 * @property notaActual la media de las últimas [ProgresoDeGolpes.VENTANA] veces que se
 *   midió ese golpe, o null si no se ha vuelto a medir desde que se fijó el objetivo.
 * @property ultimas las notas recientes de ese golpe, de la más vieja a la más nueva.
 * @property fraccion cuánto del camino está hecho, de 0 a 1.
 * @property avance cuántas décimas se ha subido desde el inicio. Puede ser negativo.
 */
data class ProgresoDeObjetivo(
    val objetivo: ObjetivoDeGolpe,
    val notaActual: Double?,
    val ultimas: List<Double>,
    val fraccion: Double,
    val avance: Double,
) {
    val cumplido: Boolean get() = notaActual != null && notaActual >= objetivo.notaObjetivo

    /**
     * El porcentaje que ve el jugador. **Redondeado, no truncado**: con truncamiento,
     * ir justo por la mitad de camino (2,6 → 3,05 con meta en 3,5) salía "49 %" porque
     * la resta en coma flotante da 0,4999999 en vez de 0,5. Nadie va a depurar eso
     * mirando una barra de progreso.
     */
    val porcentaje: Int get() = (fraccion * 100).roundToInt()
}

/**
 * Mide los objetivos técnicos de una temporada contra los partidos que se han jugado.
 *
 * Dos decisiones que conviene entender:
 *
 * **La nota actual es la media de los últimos cinco partidos, no la del último.** Un
 * partido suelto se mueve mucho —hay días— y un objetivo que sube y baja medio punto
 * entre dos sábados no dice nada útil. Cinco es lo que pide el documento de producto y
 * además es lo mínimo para que una mala tarde no borre un mes de trabajo.
 *
 * **Los partidos que no traen ese golpe no cuentan.** Si en tres partidos seguidos no
 * diste ni una bandeja, tu bandeja no ha empeorado: sencillamente no hay dato. Rellenar
 * ese hueco con un cero sería inventarse una regresión.
 */
object ProgresoDeGolpes {

    /** Cuántos partidos entran en la media de "cómo estás ahora". */
    const val VENTANA = 5

    /** La ventana larga, para comparar contra la tendencia de fondo. */
    const val VENTANA_LARGA = 20

    /**
     * El progreso de un objetivo, con los partidos ya filtrados a su temporada.
     *
     * @param partidos en cualquier orden; se ordenan aquí por fecha.
     */
    fun progreso(
        objetivo: ObjetivoDeGolpe,
        partidos: List<LigaMatch>,
        ventana: Int = VENTANA,
    ): ProgresoDeObjetivo {
        val notas = notasDe(objetivo.golpe, partidos)
        val ultimas = notas.takeLast(ventana)
        val actual = if (ultimas.isEmpty()) null else ultimas.average()

        val camino = objetivo.notaObjetivo - objetivo.notaInicial
        val fraccion = when {
            actual == null -> 0.0
            // Un objetivo que no pide subir nada ya está cumplido; sin esta guardia el
            // porcentaje sería una división por cero.
            camino <= 0.0 -> 1.0
            else -> ((actual - objetivo.notaInicial) / camino).coerceIn(0.0, 1.0)
        }

        return ProgresoDeObjetivo(
            objetivo = objetivo,
            notaActual = actual,
            ultimas = ultimas,
            fraccion = fraccion,
            avance = if (actual == null) 0.0 else actual - objetivo.notaInicial,
        )
    }

    /** El progreso de todos los objetivos de una temporada, en su orden. */
    fun deTemporada(
        temporada: LigaTemporada,
        partidos: List<LigaMatch>,
    ): List<ProgresoDeObjetivo> {
        val suyos = partidos.filter { temporada.contiene(it) }
        return temporada.objetivosDeGolpe.map { progreso(it, suyos) }
    }

    /**
     * El objetivo en el que menos se ha avanzado: la tarjeta de "principal área de
     * mejora" de la pantalla de inicio.
     *
     * Se elige por fracción de camino recorrido y no por nota más baja, y la diferencia
     * importa: el golpe con peor nota puede ser uno que el jugador ya está subiendo a
     * buen ritmo, y el que de verdad le bloquea es aquel en el que **no se mueve**. Los
     * ya cumplidos no compiten.
     */
    fun principalAreaDeMejora(progresos: List<ProgresoDeObjetivo>): ProgresoDeObjetivo? =
        progresos.filterNot { it.cumplido }.minByOrNull { it.fraccion }

    /**
     * Las notas de un golpe a lo largo de los partidos, de la más vieja a la más nueva.
     * Los partidos que no midieron ese golpe no aparecen.
     */
    fun notasDe(golpe: String, partidos: List<LigaMatch>): List<Double> = partidos
        .sortedBy { it.fecha }
        .mapNotNull { partido ->
            partido.golpesSesion?.firstOrNull { it.nombre.equals(golpe, ignoreCase = true) }?.nota
        }

    /**
     * Media de un golpe en los últimos [ultimos] partidos que lo midieron, o null si no
     * hay ninguno. Con esto se arman las comparativas del documento: el último partido
     * contra la media de 5 y contra la de 20.
     */
    fun media(golpe: String, partidos: List<LigaMatch>, ultimos: Int): Double? {
        val notas = notasDe(golpe, partidos).takeLast(ultimos)
        return if (notas.isEmpty()) null else notas.average()
    }
}
