package com.risingpadel.core.band

import com.risingpadel.core.model.GolpeVisible
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Leer los números de una captura de otra app.
 *
 * El riesgo de todo esto no es no leer: es **leer mal y que parezca bien**. Un 3,5 que
 * era un 8,5 entra en la liga con la misma pinta que un dato medido y produce una curva
 * de evolución falsa que nadie cuestiona meses después. Por eso la mitad de estos tests
 * comprueban que un número dudoso se queda FUERA en vez de colarse, y que cada número
 * que entra viaja con la línea de la que salió para poder enseñarla.
 */
class LecturaDeCapturaTest {

    @Test
    fun `el rotulo y el numero en lineas distintas se juntan`() {
        // Es la disposición normal de una app: el rótulo pequeño encima y el número
        // grande debajo. Buscar solo en la misma línea no encontraría nada.
        val leida = LecturaDeCaptura.leer(listOf("Nivel de la sesión", "3,5"))
        assertEquals(3.5, assertNotNull(leida.nivelSesion).valor)
        assertEquals("3,5", leida.nivelSesion?.origen)
    }

    @Test
    fun `la coma es decimal`() {
        // En español "3,5" es tres y medio. Tratarlo como dos números daría un nivel 3
        // y un 5 suelto rondando por ahí.
        assertEquals(listOf(3.5), LecturaDeCaptura.numerosDe("3,5"))
        assertEquals(listOf(3.5), LecturaDeCaptura.numerosDe("3.5"))
    }

    @Test
    fun `el maximo de la escala no es un dato del jugador`() {
        // "3,5/7" es un nivel sobre siete. El 7 es la escala y meterlo como dato daría
        // un recuento de golpes de 7 salido de la nada.
        assertEquals(listOf(3.5), LecturaDeCaptura.numerosDe("3,5/7"))
        assertEquals(listOf(4.0), LecturaDeCaptura.numerosDe("Nivel 4 / 10"))
    }

    @Test
    fun `un nivel imposible no se trae`() {
        // Si en la línea del nivel se lee 3500, es que el reconocedor se comió la coma o
        // cogió otra cosa. Traerlo sería meter un nivel de 3500 en la liga.
        val leida = LecturaDeCaptura.leer(listOf("Nivel", "3500"))
        assertNull(leida.nivelSesion)
        assertTrue(leida.sinEntender.contains("3500"))
    }

    @Test
    fun `el pulso maximo no se come el pulso medio`() {
        // El orden de búsqueda importa: si se buscara el rótulo corto primero, la línea
        // del máximo se consumiría como media y el máximo quedaría vacío.
        val leida = LecturaDeCaptura.leer(
            listOf("Pulso medio", "142 ppm", "Pulso máximo", "178 ppm")
        )
        assertEquals(142.0, assertNotNull(leida.pulsoMedio).valor)
        assertEquals(178.0, assertNotNull(leida.pulsoMax).valor)
    }

    @Test
    fun `una captura de resumen entera`() {
        val leida = LecturaDeCaptura.leer(
            listOf(
                "PADEL BAND",
                "Sesión del 12 oct",
                "Nivel",
                "3,8",
                "Golpes",
                "284",
                "Duración",
                "92 min",
                "Pulso medio",
                "138",
                "Calorías",
                "612",
            )
        )
        assertEquals(3.8, leida.nivelSesion?.valor)
        assertEquals(284.0, leida.totalGolpes?.valor)
        assertEquals(92.0, leida.duracionMin?.valor)
        assertEquals(138.0, leida.pulsoMedio?.valor)
        assertEquals(612.0, leida.calorias?.valor)
        assertTrue(!leida.vacia)
    }

    @Test
    fun `los golpes con nota y recuento en la misma linea`() {
        // "Bandeja 3,5 · 24": el primero lleva decimales, así que es la nota; el segundo
        // es entero y es el recuento.
        val leida = LecturaDeCaptura.leer(listOf("Bandeja 3,5 · 24", "Remate 4,1 · 12"))
        assertEquals(2, leida.golpes.size)

        val bandeja = assertNotNull(leida.golpes.firstOrNull { it.golpe == GolpeVisible.BANDEJA })
        assertEquals(3.5, bandeja.nota?.valor)
        assertEquals(24.0, bandeja.cantidad?.valor)
    }

    @Test
    fun `un golpe con un solo numero se interpreta por su forma`() {
        // Con decimales es nota; entero es recuento. Es una heurística, y por eso el
        // número viaja con su línea para que se pueda corregir de un vistazo.
        val conNota = LecturaDeCaptura.leer(listOf("Derecha 3,2"))
        assertEquals(3.2, conNota.golpes.first().nota?.valor)
        assertNull(conNota.golpes.first().cantidad)

        val conCuenta = LecturaDeCaptura.leer(listOf("Derecha 48"))
        assertNull(conCuenta.golpes.first().nota)
        assertEquals(48.0, conCuenta.golpes.first().cantidad?.valor)
    }

    @Test
    fun `una volea no se confunde con una derecha`() {
        // "Volea de derecha" contiene "derecha". Buscar los golpes sueltos antes que los
        // compuestos convertiría todas las voleas en derechas y reveses — y el jugador
        // vería su volea de revés contada como revés, que es un golpe distinto.
        assertEquals(
            GolpeVisible.VOLEA_DERECHA,
            LecturaDeCaptura.golpeDe(LecturaDeCaptura.normalizar("Volea de derecha"))
        )
        assertEquals(
            GolpeVisible.VOLEA_REVES,
            LecturaDeCaptura.golpeDe(LecturaDeCaptura.normalizar("VOLEA DE REVÉS"))
        )
        assertEquals(
            GolpeVisible.DERECHA,
            LecturaDeCaptura.golpeDe(LecturaDeCaptura.normalizar("Derecha"))
        )
    }

    @Test
    fun `volea sin el de tambien se reconoce`() {
        // Media aplicación lo escribe sin preposición.
        assertEquals(
            GolpeVisible.VOLEA_REVES,
            LecturaDeCaptura.golpeDe(LecturaDeCaptura.normalizar("Volea revés"))
        )
    }

    @Test
    fun `los acentos y las mayusculas no importan`() {
        assertEquals("reves", LecturaDeCaptura.normalizar("Revés"))
        assertEquals("duracion", LecturaDeCaptura.normalizar("DURACIÓN"))
        assertEquals("nivel de sesion", LecturaDeCaptura.normalizar("  Nivel   de  Sesión  "))
    }

    @Test
    fun `los golpes salen en el orden del repertorio y no en el de la captura`() {
        // Así la pantalla de confirmación se lee siempre igual, venga la captura como
        // venga: el jugador aprende dónde mirar una vez.
        val leida = LecturaDeCaptura.leer(
            listOf("Saque 2,9", "Bandeja 3,5", "Derecha 3,1")
        )
        assertEquals(
            listOf(GolpeVisible.DERECHA, GolpeVisible.BANDEJA, GolpeVisible.SAQUE),
            leida.golpes.map { it.golpe }
        )
    }

    @Test
    fun `lo que no se entiende se guarda para poder ensenarlo`() {
        // Si al jugador le falta un dato que él sí ve en su captura, aquí está la línea
        // que no se supo leer. Sin esto, el dato desaparecido no tiene explicación.
        val leida = LecturaDeCaptura.leer(listOf("Resumen semanal", "Comparte tu sesión"))
        assertTrue(leida.vacia)
        assertEquals(listOf("Resumen semanal", "Comparte tu sesión"), leida.sinEntender)
    }

    @Test
    fun `una captura sin numeros no inventa ceros`() {
        // Lo que no se lee se queda fuera. Un cero diría "jugó y no dio ni un golpe".
        val leida = LecturaDeCaptura.leer(listOf("Nivel", "Golpes", "Duración"))
        assertNull(leida.nivelSesion)
        assertNull(leida.totalGolpes)
        assertNull(leida.duracionMin)
        assertTrue(leida.vacia)
    }

    @Test
    fun `lineas vacias y espacios no estorban`() {
        val leida = LecturaDeCaptura.leer(listOf("", "   ", "Nivel", "", "3,4"))
        assertEquals(3.4, leida.nivelSesion?.valor)
    }
}
