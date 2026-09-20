package com.risingpadel.core.pista

import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sqrt

/**
 * Una lectura de posición del reloj.
 *
 * @param accuracyM el error que el propio sistema declara para esta lectura, en metros.
 *   No es un adorno: es el primer filtro, porque una lectura que se dice mala lo es.
 */
data class PuntoGeo(
    val latitud: Double,
    val longitud: Double,
    val accuracyM: Double = 0.0,
)

/** Dónde estaba el jugador dentro de la pista, en metros desde la esquina de origen. */
data class PosicionEnPista(val x: Double, val y: Double) {
    /** Las seis zonas gruesas del mapa de pista: fondo / medio / red, por lado. */
    val zona: String
        get() {
            val profundidad = when {
                y < LARGO / 6 -> "red"
                y < LARGO / 3 -> "medio"
                else -> "fondo"
            }
            return if (x < ANCHO / 2) "$profundidad izquierda" else "$profundidad derecha"
        }

    companion object {
        /** Medidas de reglamento de una pista de pádel, en metros. */
        const val LARGO = 20.0
        const val ANCHO = 10.0
    }
}

/**
 * La pista, situada sobre el mundo a partir de cuatro lecturas de GPS en sus esquinas.
 *
 * ## Para qué sirve esto de verdad: para medir si el GPS llega
 *
 * La pregunta "¿puede el reloj decir dónde estaba el jugador?" no se contesta con una
 * opinión sobre el GPS, se contesta con un número. Y hay una forma limpia de sacarlo:
 * **una pista de pádel mide 20×10 m por reglamento**, así que sus dimensiones son un
 * patrón de medida conocido. Si el jugador se planta en las cuatro esquinas y el reloj
 * toma una lectura en cada una, lo que falle al reconstruir ese rectángulo **es** el
 * error del GPS en esa pista concreta, con su multitrayecto, su techo y su día.
 *
 * Ese número es [errorMedioM], y es lo que decide qué se puede enseñar:
 *
 * - por debajo de ~1,5 m se pueden separar las seis zonas de [PosicionEnPista.zona];
 * - entre 1,5 y 3 m solo se sostiene "cerca de la red" contra "en el fondo";
 * - por encima de 3 m no se sostiene nada, y hay que decirlo en vez de pintar puntos.
 *
 * Las paredes de cristal y la malla metálica de una pista de pádel producen
 * multitrayecto —la señal rebota antes de llegar al reloj— y muchas pistas están
 * cubiertas, así que este número va a ser peor que el que da el GPS en campo abierto.
 * Por eso se mide en la pista de cada uno y no se supone.
 *
 * ## Cómo se ajusta
 *
 * Las cuatro lecturas se pasan a metros y se busca la rotación y el desplazamiento que
 * mejor las encajan sobre el rectángulo ideal (ajuste de Procrustes en dos dimensiones,
 * sin escalar: **la escala no se toca a propósito**, porque el tamaño de la pista lo da
 * el reglamento y no el GPS — dejar que la escala se ajuste escondería justo el error
 * que se quiere medir).
 */
data class CalibracionDePista(
    /** Latitud y longitud del centro de la pista: el origen del sistema local. */
    val centroLatitud: Double,
    val centroLongitud: Double,
    /** Giro de la pista respecto al norte, en radianes. */
    val rotacionRad: Double,
    /**
     * Cuánto se desvían de media las cuatro esquinas medidas respecto al rectángulo
     * ideal, en metros. **Es la cifra que dice si el mapa de pista se puede enseñar.**
     */
    val errorMedioM: Double,
    /** El peor error declarado por el sistema entre las cuatro lecturas. */
    val peorAccuracyM: Double,
) {

    /** Qué se puede enseñar con este error. Ver la cabecera de la clase. */
    val fiabilidad: Fiabilidad
        get() = when {
            errorMedioM <= 1.5 -> Fiabilidad.ZONAS
            errorMedioM <= 3.0 -> Fiabilidad.RED_O_FONDO
            else -> Fiabilidad.NINGUNA
        }

    enum class Fiabilidad {
        /** Las seis zonas de la pista. */
        ZONAS,

        /** Solo "cerca de la red" contra "en el fondo". */
        RED_O_FONDO,

        /** Nada. No se pinta un mapa con esto. */
        NINGUNA,
    }

    /**
     * Pasa una lectura del reloj a coordenadas de la pista, o null si cae claramente
     * fuera.
     *
     * El margen de 3 m no es generosidad: con el error del GPS, un jugador pegado a la
     * pared de fondo puede medirse un par de metros fuera, y descartar esa lectura
     * borraría justo los golpes de defensa.
     */
    fun aPista(punto: PuntoGeo): PosicionEnPista? {
        val (este, norte) = aMetros(punto, centroLatitud, centroLongitud)
        // Deshacer el giro de la pista: se rota en sentido contrario.
        val cosR = cos(-rotacionRad)
        val senR = kotlin.math.sin(-rotacionRad)
        val x = este * cosR - norte * senR + PosicionEnPista.ANCHO / 2
        val y = este * senR + norte * cosR + PosicionEnPista.LARGO / 2

        val margen = 3.0
        if (x < -margen || x > PosicionEnPista.ANCHO + margen) return null
        if (y < -margen || y > PosicionEnPista.LARGO + margen) return null
        return PosicionEnPista(x.coerceIn(0.0, PosicionEnPista.ANCHO), y.coerceIn(0.0, PosicionEnPista.LARGO))
    }

    companion object {

        /**
         * Calibra con las cuatro esquinas, **en orden**: fondo izquierda, fondo derecha,
         * red derecha, red izquierda (recorriendo la pista, no en aspa).
         *
         * Devuelve null con menos de cuatro lecturas: con tres esquinas el rectángulo
         * sale de una suposición, y una suposición es lo que este fichero existe para
         * evitar.
         */
        fun de(esquinas: List<PuntoGeo>): CalibracionDePista? {
            if (esquinas.size != 4) return null

            val centroLat = esquinas.sumOf { it.latitud } / 4
            val centroLon = esquinas.sumOf { it.longitud } / 4
            val medidas = esquinas.map { aMetros(it, centroLat, centroLon) }

            // El rectángulo ideal, centrado en el origen y en el mismo orden.
            val mitadAncho = PosicionEnPista.ANCHO / 2
            val mitadLargo = PosicionEnPista.LARGO / 2
            val ideal = listOf(
                -mitadAncho to -mitadLargo,
                mitadAncho to -mitadLargo,
                mitadAncho to mitadLargo,
                -mitadAncho to mitadLargo,
            )

            // Procrustes en 2D sin escala: el ángulo que mejor alinea las dos nubes sale
            // de la suma de productos cruzados contra la de productos escalares.
            var cruz = 0.0
            var escalar = 0.0
            for (i in 0 until 4) {
                val (mx, my) = medidas[i]
                val (ix, iy) = ideal[i]
                cruz += ix * my - iy * mx
                escalar += ix * mx + iy * my
            }
            val rotacion = atan2(cruz, escalar)

            // Con el giro puesto, lo que quede entre cada esquina medida y su ideal es
            // el error del GPS en esta pista.
            val cosR = cos(rotacion)
            val senR = kotlin.math.sin(rotacion)
            var sumaCuadrados = 0.0
            for (i in 0 until 4) {
                val (ix, iy) = ideal[i]
                val giradoX = ix * cosR - iy * senR
                val giradoY = ix * senR + iy * cosR
                val (mx, my) = medidas[i]
                sumaCuadrados += (giradoX - mx) * (giradoX - mx) + (giradoY - my) * (giradoY - my)
            }
            val error = sqrt(sumaCuadrados / 4)

            return CalibracionDePista(
                centroLatitud = centroLat,
                centroLongitud = centroLon,
                rotacionRad = rotacion,
                errorMedioM = error,
                peorAccuracyM = esquinas.maxOf { it.accuracyM },
            )
        }

        /** Metros al este y al norte desde un origen. Radio medio de la Tierra. */
        private const val RADIO_TIERRA_M = 6_371_000.0

        /**
         * Proyección plana alrededor del origen.
         *
         * A escala de veinte metros la curvatura de la Tierra no se nota —el error de
         * esta aproximación está en los micrómetros—, así que una proyección cilíndrica
         * simple sobra y evita arrastrar una biblioteca geodésica al reloj.
         */
        internal fun aMetros(punto: PuntoGeo, origenLat: Double, origenLon: Double): Pair<Double, Double> {
            val radianes = Math.PI / 180
            val norte = (punto.latitud - origenLat) * radianes * RADIO_TIERRA_M
            val este = (punto.longitud - origenLon) * radianes * RADIO_TIERRA_M *
                cos(origenLat * radianes)
            return este to norte
        }
    }
}
