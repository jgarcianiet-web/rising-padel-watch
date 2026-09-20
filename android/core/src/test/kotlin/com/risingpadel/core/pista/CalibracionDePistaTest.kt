package com.risingpadel.core.pista

import kotlin.math.PI
import kotlin.math.cos
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * La pista como patrón de medida.
 *
 * La pregunta de fondo —"¿puede el GPS del reloj decir dónde estaba el jugador?"— no se
 * contesta con una opinión sobre el GPS. Una pista de pádel mide 20×10 m por reglamento,
 * así que lo que el reloj falle al reconstruir ese rectángulo desde sus cuatro esquinas
 * **es** el error del GPS en esa pista concreta. Estos tests comprueban que ese número
 * sale bien, incluido el caso en que sale malo: un error grande tiene que verse como
 * error grande, no colarse como una calibración razonable.
 */
class CalibracionDePistaTest {

    /** Metros → grados alrededor de un origen, para construir esquinas sintéticas. */
    private fun desplazar(lat: Double, lon: Double, esteM: Double, norteM: Double): PuntoGeo {
        val radio = 6_371_000.0
        val grados = 180 / PI
        return PuntoGeo(
            latitud = lat + (norteM / radio) * grados,
            longitud = lon + (esteM / (radio * cos(lat * PI / 180))) * grados,
        )
    }

    /**
     * Una pista perfecta, con su eje largo apuntando al este, centrada en un punto de
     * Madrid. El orden es el de `NOMBRES_DE_ESQUINA`: fondo cercano izquierda y derecha,
     * y luego el fondo contrario de derecha a izquierda.
     */
    private fun pistaPerfecta(
        lat: Double = 40.4168,
        lon: Double = -3.7038,
        ruidoEste: List<Double> = List(4) { 0.0 },
        ruidoNorte: List<Double> = List(4) { 0.0 },
    ): List<PuntoGeo> {
        val esquinas = listOf(
            -10.0 to -5.0,   // fondo cercano izquierda
            -10.0 to 5.0,    // fondo cercano derecha
            10.0 to 5.0,     // fondo contrario derecha
            10.0 to -5.0,    // fondo contrario izquierda
        )
        return esquinas.mapIndexed { i, (largo, ancho) ->
            desplazar(lat, lon, largo + ruidoEste[i], ancho + ruidoNorte[i])
        }
    }

    @Test
    fun `una pista medida sin error da error cero`() {
        val calibracion = assertNotNull(CalibracionGpsDePista.de(pistaPerfecta()))
        assertTrue(calibracion.errorMedioM < 0.01, "error: ${calibracion.errorMedioM}")
        assertEquals(CalibracionGpsDePista.Fiabilidad.ZONAS, calibracion.fiabilidad)
    }

    @Test
    fun `con tres esquinas no se calibra, porque la cuarta seria una suposicion`() {
        assertNull(CalibracionGpsDePista.de(pistaPerfecta().take(3)))
    }

    @Test
    fun `un GPS con cuatro metros de error se ve como cuatro metros de error`() {
        // Este es el test que de verdad importa: si el GPS va mal, el número tiene que
        // decirlo. Un error que se disimula es peor que no medir nada, porque se acaba
        // pintando un mapa de puntos inventados.
        val calibracion = assertNotNull(
            CalibracionGpsDePista.de(
                pistaPerfecta(
                    ruidoEste = listOf(4.0, -4.0, 4.0, -4.0),
                    ruidoNorte = listOf(-4.0, 4.0, 4.0, -4.0),
                )
            )
        )
        assertTrue(calibracion.errorMedioM > 3.0, "error: ${calibracion.errorMedioM}")
        assertEquals(CalibracionGpsDePista.Fiabilidad.NINGUNA, calibracion.fiabilidad)
    }

    @Test
    fun `el ajuste no estira la pista para disimular el error`() {
        // Si el ajuste pudiera escalar, una pista medida como si fuera de 24×12 encajaría
        // "perfectamente" en el rectángulo ideal y el error saldría cero — escondiendo
        // justo lo que se quiere medir. El tamaño lo da el reglamento, no el GPS.
        val estirada = listOf(
            -12.0 to -6.0, -12.0 to 6.0, 12.0 to 6.0, 12.0 to -6.0,
        ).map { (largo, ancho) -> desplazar(40.4168, -3.7038, largo, ancho) }

        val calibracion = assertNotNull(CalibracionGpsDePista.de(estirada))
        assertTrue(
            calibracion.errorMedioM > 1.5,
            "una pista un 20 % más grande no puede dar error cero: ${calibracion.errorMedioM}",
        )
    }

    @Test
    fun `una pista girada se calibra igual de bien`() {
        // Las pistas no están orientadas al norte; el ajuste tiene que encontrar el giro.
        val giro = PI / 5
        val esquinas = listOf(
            -10.0 to -5.0, -10.0 to 5.0, 10.0 to 5.0, 10.0 to -5.0,
        ).map { (x, y) ->
            desplazar(
                40.4168, -3.7038,
                x * cos(giro) - y * kotlin.math.sin(giro),
                x * kotlin.math.sin(giro) + y * cos(giro),
            )
        }
        val calibracion = assertNotNull(CalibracionGpsDePista.de(esquinas))
        assertTrue(calibracion.errorMedioM < 0.01, "error: ${calibracion.errorMedioM}")
        assertEquals(giro, calibracion.rotacionRad, 0.01)
    }

    @Test
    fun `el centro de la pista cae en la red`() {
        val calibracion = assertNotNull(CalibracionGpsDePista.de(pistaPerfecta()))
        val centro = assertNotNull(
            calibracion.aPista(PuntoGeo(calibracion.centroLatitud, calibracion.centroLongitud))
        )
        assertEquals(10.0, centro.x, 0.1)
        assertEquals(5.0, centro.y, 0.1)
        assertEquals(0.0, centro.distanciaALaRed, 0.1)
    }

    @Test
    fun `las zonas se miden contra la red y no contra una punta`() {
        // En una pista entera los DOS fondos son fondo. Contar la profundidad desde un
        // extremo pondría "fondo" en la mitad contraria de la red, que es justo donde
        // está el rival.
        assertEquals("red izquierda", PosicionGpsEnPista(9.0, 2.0).zona)
        assertEquals("red derecha", PosicionGpsEnPista(11.0, 8.0).zona)
        assertEquals("medio izquierda", PosicionGpsEnPista(5.0, 2.0).zona)
        assertEquals("fondo derecha", PosicionGpsEnPista(1.0, 8.0).zona)
        // El fondo contrario también es fondo.
        assertEquals("fondo derecha", PosicionGpsEnPista(19.0, 8.0).zona)
    }

    @Test
    fun `un punto muy lejos de la pista no se coloca dentro`() {
        // Cien metros es la calle de al lado: colocarlo en el fondo de la pista sería
        // inventarse una posición.
        val calibracion = assertNotNull(CalibracionGpsDePista.de(pistaPerfecta()))
        val lejos = desplazar(calibracion.centroLatitud, calibracion.centroLongitud, 100.0, 0.0)
        assertNull(calibracion.aPista(lejos))
    }

    @Test
    fun `un punto pegado a la pared de fondo se acepta aunque mida un poco fuera`() {
        // Con el error del GPS, un jugador defendiendo pegado al cristal puede medirse
        // dos metros fuera. Descartarlo borraría justo los golpes de defensa.
        val calibracion = assertNotNull(CalibracionGpsDePista.de(pistaPerfecta()))
        val algoFuera = desplazar(calibracion.centroLatitud, calibracion.centroLongitud, -12.0, 0.0)
        val posicion = assertNotNull(calibracion.aPista(algoFuera))
        assertTrue(posicion.x <= 0.5, "debería quedar pegado al fondo: ${posicion.x}")
    }
}
