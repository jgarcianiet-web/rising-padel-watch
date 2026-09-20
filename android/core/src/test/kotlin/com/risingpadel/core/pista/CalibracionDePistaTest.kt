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

    /** Una pista perfecta, alineada al norte, centrada en un punto de Madrid. */
    private fun pistaPerfecta(
        lat: Double = 40.4168,
        lon: Double = -3.7038,
        ruidoEste: List<Double> = List(4) { 0.0 },
        ruidoNorte: List<Double> = List(4) { 0.0 },
    ): List<PuntoGeo> {
        val esquinas = listOf(
            -5.0 to -10.0,   // fondo izquierda
            5.0 to -10.0,    // fondo derecha
            5.0 to 10.0,     // red derecha
            -5.0 to 10.0,    // red izquierda
        )
        return esquinas.mapIndexed { i, (este, norte) ->
            desplazar(lat, lon, este + ruidoEste[i], norte + ruidoNorte[i])
        }
    }

    @Test
    fun `una pista medida sin error da error cero`() {
        val calibracion = assertNotNull(CalibracionDePista.de(pistaPerfecta()))
        assertTrue(calibracion.errorMedioM < 0.01, "error: ${calibracion.errorMedioM}")
        assertEquals(CalibracionDePista.Fiabilidad.ZONAS, calibracion.fiabilidad)
    }

    @Test
    fun `con tres esquinas no se calibra, porque la cuarta seria una suposicion`() {
        assertNull(CalibracionDePista.de(pistaPerfecta().take(3)))
    }

    @Test
    fun `un GPS con cuatro metros de error se ve como cuatro metros de error`() {
        // Este es el test que de verdad importa: si el GPS va mal, el número tiene que
        // decirlo. Un error que se disimula es peor que no medir nada, porque se acaba
        // pintando un mapa de puntos inventados.
        val calibracion = assertNotNull(
            CalibracionDePista.de(
                pistaPerfecta(
                    ruidoEste = listOf(4.0, -4.0, 4.0, -4.0),
                    ruidoNorte = listOf(-4.0, 4.0, 4.0, -4.0),
                )
            )
        )
        assertTrue(calibracion.errorMedioM > 3.0, "error: ${calibracion.errorMedioM}")
        assertEquals(CalibracionDePista.Fiabilidad.NINGUNA, calibracion.fiabilidad)
    }

    @Test
    fun `el ajuste no estira la pista para disimular el error`() {
        // Si el ajuste pudiera escalar, una pista medida como si fuera de 24×12 encajaría
        // "perfectamente" en el rectángulo ideal y el error saldría cero — escondiendo
        // justo lo que se quiere medir. El tamaño lo da el reglamento, no el GPS.
        val estirada = listOf(
            -6.0 to -12.0, 6.0 to -12.0, 6.0 to 12.0, -6.0 to 12.0,
        ).map { (este, norte) -> desplazar(40.4168, -3.7038, este, norte) }

        val calibracion = assertNotNull(CalibracionDePista.de(estirada))
        assertTrue(calibracion.errorMedioM > 1.5, "una pista un 20 % más grande no puede dar error cero: ${calibracion.errorMedioM}")
    }

    @Test
    fun `una pista girada se calibra igual de bien`() {
        // Las pistas no están orientadas al norte; el ajuste tiene que encontrar el giro.
        val giro = PI / 5
        val esquinas = listOf(
            -5.0 to -10.0, 5.0 to -10.0, 5.0 to 10.0, -5.0 to 10.0,
        ).map { (x, y) ->
            desplazar(
                40.4168, -3.7038,
                x * cos(giro) - y * kotlin.math.sin(giro),
                x * kotlin.math.sin(giro) + y * cos(giro),
            )
        }
        val calibracion = assertNotNull(CalibracionDePista.de(esquinas))
        assertTrue(calibracion.errorMedioM < 0.01, "error: ${calibracion.errorMedioM}")
        assertEquals(giro, calibracion.rotacionRad, 0.01)
    }

    @Test
    fun `el centro de la pista cae en el centro`() {
        val calibracion = assertNotNull(CalibracionDePista.de(pistaPerfecta()))
        val centro = assertNotNull(
            calibracion.aPista(PuntoGeo(calibracion.centroLatitud, calibracion.centroLongitud))
        )
        assertEquals(5.0, centro.x, 0.1)
        assertEquals(10.0, centro.y, 0.1)
    }

    @Test
    fun `las zonas parten la pista en red, medio y fondo por cada lado`() {
        assertEquals("red izquierda", PosicionEnPista(2.0, 1.0).zona)
        assertEquals("red derecha", PosicionEnPista(8.0, 1.0).zona)
        assertEquals("medio izquierda", PosicionEnPista(2.0, 5.0).zona)
        assertEquals("fondo derecha", PosicionEnPista(8.0, 18.0).zona)
    }

    @Test
    fun `un punto muy lejos de la pista no se coloca dentro`() {
        // Cien metros es la calle de al lado: colocarlo en el fondo de la pista sería
        // inventarse una posición.
        val calibracion = assertNotNull(CalibracionDePista.de(pistaPerfecta()))
        val lejos = desplazar(calibracion.centroLatitud, calibracion.centroLongitud, 100.0, 0.0)
        assertNull(calibracion.aPista(lejos))
    }

    @Test
    fun `un punto pegado a la pared de fondo se acepta aunque mida un poco fuera`() {
        // Con el error del GPS, un jugador defendiendo pegado al cristal puede medirse
        // dos metros fuera. Descartarlo borraría justo los golpes de defensa.
        val calibracion = assertNotNull(CalibracionDePista.de(pistaPerfecta()))
        val algoFuera = desplazar(calibracion.centroLatitud, calibracion.centroLongitud, 0.0, -12.0)
        val posicion = assertNotNull(calibracion.aPista(algoFuera))
        assertTrue(posicion.y <= 0.5, "debería quedar pegado al fondo: ${posicion.y}")
    }
}
