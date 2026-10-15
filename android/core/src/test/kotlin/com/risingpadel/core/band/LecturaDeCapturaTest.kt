package com.risingpadel.core.band

import com.risingpadel.core.band.LecturaDeCaptura.Trozo
import com.risingpadel.core.model.GolpeVisible
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Leer los números de una captura de la Padel Band.
 *
 * **Las capturas de estos tests son reales** (oct 2026), transcritas con las posiciones
 * que tiene cada texto en pantalla. Eso importa: la primera versión de este lector
 * trabajaba con líneas sueltas y contra las pantallas de verdad no leía casi nada, porque
 * una app de móvil no apila rótulo y valor en una columna — los pone en rejilla, y a veces
 * el número va encima del rótulo.
 *
 * El riesgo de fondo no es no leer: es **leer mal y que parezca bien**. Un número torcido
 * entra en la liga con la misma pinta que uno medido. Por eso buena parte de estos tests
 * comprueba que un dato dudoso se queda fuera, y que cada número que entra viaja con el
 * texto del que salió.
 */
class LecturaDeCapturaTest {

    // ─── Pantalla "Actividad" (resumen de la sesión) ───
    //
    // Rejilla de dos columnas con el NÚMERO ENCIMA del rótulo:
    //
    //      407              8861
    //      Golpes           Pasos
    //      898              01:39:46
    //      K Cal            Tiempo
    private fun actividad() = listOf(
        Trozo("Archivo", 0.50, 0.05),
        Trozo("Posición en pista", 0.28, 0.12),
        Trozo("REVÉS", 0.28, 0.25),
        Trozo("DERECHA", 0.72, 0.25),
        Trozo("Aspectos destacados", 0.32, 0.35),
        Trozo("Mejor golpe", 0.20, 0.42),
        Trozo("REMATE", 0.85, 0.42),
        Trozo("Nivel sesión", 0.20, 0.48),
        Trozo("3.43", 0.88, 0.48),
        Trozo("Actividad", 0.18, 0.56),
        Trozo("407", 0.26, 0.64),
        Trozo("8861", 0.74, 0.64),
        Trozo("Golpes", 0.26, 0.68),
        Trozo("Pasos", 0.74, 0.68),
        Trozo("898", 0.26, 0.80),
        Trozo("01:39:46", 0.74, 0.80),
        Trozo("K Cal", 0.26, 0.84),
        Trozo("Tiempo", 0.74, 0.84),
    )

    @Test
    fun `el tiempo en formato reloj son minutos, no un uno`() {
        // ESTE es el test que más duele si falta. "01:39:46" leído como número suelto da
        // 1, y el partido entra en la liga durando un minuto — con toda la pinta de un
        // dato bueno. Son 99,8 minutos.
        val leida = LecturaDeCaptura.leerTrozos(actividad())
        val duracion = assertNotNull(leida.duracionMin)
        assertEquals(99.77, duracion.valor, 0.05)
        assertEquals("01:39:46", duracion.origen)
    }

    @Test
    fun `el numero encima del rotulo tambien se lee`() {
        // En las tarjetas de actividad el número va arriba y el rótulo debajo. Buscando
        // solo a la derecha y debajo, no se leería ninguna de las cuatro.
        val leida = LecturaDeCaptura.leerTrozos(actividad())
        assertEquals(407.0, leida.totalGolpes?.valor)
        assertEquals(898.0, leida.calorias?.valor)
        assertEquals(8861.0, leida.pasos?.valor)
    }

    @Test
    fun `cada tarjeta coge el numero de su columna y no el del vecino`() {
        // "Golpes" y "Pasos" están en la misma fila, y sus números también. Sin mirar la
        // columna, los 8861 pasos podrían acabar de golpes.
        val leida = LecturaDeCaptura.leerTrozos(actividad())
        assertEquals(407.0, leida.totalGolpes?.valor)
        assertEquals(8861.0, leida.pasos?.valor)
        assertEquals("407", leida.totalGolpes?.origen)
    }

    @Test
    fun `el nivel de sesion y el mejor golpe salen de su fila`() {
        val leida = LecturaDeCaptura.leerTrozos(actividad())
        assertEquals(3.43, leida.nivelSesion?.valor)
        assertEquals("REMATE", leida.mejorGolpe)
    }

    // ─── Pantalla de un golpe ("Bandeja") ───
    //
    // Rótulos en una fila y valores en la siguiente, en dos columnas:
    //
    //      Num. golpes      Calidad
    //      11               2.99
    private fun tarjetaDeGolpe(
        titulo: String, golpes: String, calidad: String
    ) = listOf(
        Trozo(titulo, 0.50, 0.07),
        Trozo(titulo, 0.15, 0.15),
        Trozo("Num. golpes", 0.29, 0.21),
        Trozo("Calidad", 0.70, 0.21),
        Trozo(golpes, 0.29, 0.27),
        Trozo(calidad, 0.70, 0.27),
        Trozo("VELOCIDAD MEDIA DE GOLPEO (KM/H)", 0.35, 0.38),
        Trozo("59", 0.50, 0.68),
        Trozo("KMH", 0.50, 0.73),
    )

    @Test
    fun `la tarjeta de un golpe da recuento y calidad`() {
        val leida = LecturaDeCaptura.leerTrozos(tarjetaDeGolpe("Bandeja", "11", "2.99"))
        val bandeja = assertNotNull(leida.golpes.firstOrNull())

        assertEquals(GolpeVisible.BANDEJA, bandeja.golpe)
        assertEquals(11.0, bandeja.cantidad?.valor)
        assertEquals(2.99, bandeja.nota?.valor)
        // Y cada número con el texto del que salió, para poder enseñarlo.
        assertEquals("11", bandeja.cantidad?.origen)
        assertEquals("2.99", bandeja.nota?.origen)
    }

    @Test
    fun `los rotulos de una fila casan con los valores de la siguiente por columna`() {
        // "Num. golpes" y "Calidad" van uno al lado del otro y sus valores debajo. Sin
        // mirar la columna, la calidad 2.99 podría acabar de recuento de golpes.
        val leida = LecturaDeCaptura.leerTrozos(tarjetaDeGolpe("Derecha", "86", "3.09"))
        val derecha = assertNotNull(leida.golpes.firstOrNull())
        assertEquals(86.0, derecha.cantidad?.valor)
        assertEquals(3.09, derecha.nota?.valor)
    }

    // ─── Pantalla del globo: dos tarjetas bajo un mismo título ───

    private fun pantallaDelGlobo() = listOf(
        Trozo("Globo", 0.50, 0.07),
        Trozo("Globo Rev.", 0.17, 0.15),
        Trozo("Num. golpes", 0.29, 0.21),
        Trozo("Calidad", 0.70, 0.21),
        Trozo("21", 0.29, 0.27),
        Trozo("3.19", 0.70, 0.27),
        Trozo("Globo Dcha.", 0.18, 0.38),
        Trozo("Num. golpes", 0.29, 0.44),
        Trozo("Calidad", 0.70, 0.44),
        Trozo("97", 0.29, 0.50),
        Trozo("3.48", 0.70, 0.50),
    )

    @Test
    fun `las abreviaturas Rev y Dcha son reves y derecha`() {
        // Es como lo escribe la app de verdad. Con los patrones largos solos, "Globo Rev."
        // no casaría con nada... o peor, casaría con "revés" a secas y el jugador vería su
        // globo de revés contado como un revés, que es otro golpe.
        val leida = LecturaDeCaptura.leerTrozos(pantallaDelGlobo())
        val porGolpe = leida.golpes.associateBy { it.golpe }

        val revés = assertNotNull(porGolpe[GolpeVisible.GLOBO_REVES])
        assertEquals(21.0, revés.cantidad?.valor)
        assertEquals(3.19, revés.nota?.valor)

        val derecha = assertNotNull(porGolpe[GolpeVisible.GLOBO_DERECHA])
        assertEquals(97.0, derecha.cantidad?.valor)
        assertEquals(3.48, derecha.nota?.valor)
    }

    @Test
    fun `el titulo de navegacion no se queda con los datos de la primera tarjeta`() {
        // La pantalla se titula "Globo" y debajo vienen "Globo Rev." y "Globo Dcha.". Sin
        // acotar cada nombre hasta el siguiente, ese "Globo" de arriba se habría llevado
        // el 21 y el 3,19 — un golpe que no existe con los datos de otro.
        val leida = LecturaDeCaptura.leerTrozos(pantallaDelGlobo())
        assertEquals(2, leida.golpes.size)
        assertTrue(leida.golpes.none { it.golpe == null }, "se ha colado un agregado")
    }

    @Test
    fun `la volea abreviada tampoco se confunde`() {
        val leida = LecturaDeCaptura.leerTrozos(
            listOf(
                Trozo("Volea Rev.", 0.17, 0.15),
                Trozo("Num. golpes", 0.29, 0.21),
                Trozo("Calidad", 0.70, 0.21),
                Trozo("74", 0.29, 0.27),
                Trozo("3.73", 0.70, 0.27),
            )
        )
        val volea = assertNotNull(leida.golpes.firstOrNull())
        assertEquals(GolpeVisible.VOLEA_REVES, volea.golpe)
        assertEquals(74.0, volea.cantidad?.valor)
    }

    // ─── Volumen de golpeos: el nombre y el número en la misma fila ───

    @Test
    fun `la lista de volumen da recuentos, y los agregados se quedan sin lado`() {
        // La pantalla de volumen no separa derecha de revés: dice "Volea 175". Partir ese
        // 175 por la mitad sería inventarse dos números, así que se guarda como "Volea" y
        // se dice que no tiene lado.
        val leida = LecturaDeCaptura.leerTrozos(
            listOf(
                Trozo("407", 0.50, 0.20),
                Trozo("GOLPES TOTALES", 0.50, 0.25),
                Trozo("Volea", 0.20, 0.35),
                Trozo("175", 0.85, 0.35),
                Trozo("Globo", 0.20, 0.41),
                Trozo("118", 0.85, 0.41),
                Trozo("Derecha", 0.20, 0.47),
                Trozo("86", 0.85, 0.47),
                Trozo("Bandeja", 0.20, 0.53),
                Trozo("11", 0.85, 0.53),
                Trozo("Revés", 0.20, 0.59),
                Trozo("9", 0.85, 0.59),
                Trozo("Remate", 0.20, 0.65),
                Trozo("8", 0.85, 0.65),
            )
        )
        assertEquals(407.0, leida.totalGolpes?.valor)

        val porNombre = leida.golpes.associateBy { it.nombre }
        assertEquals(86.0, porNombre["Derecha"]?.cantidad?.valor)
        assertEquals(11.0, porNombre["Bandeja"]?.cantidad?.valor)
        assertEquals(8.0, porNombre["Remate"]?.cantidad?.valor)

        // Volea y Globo, sin lado y dichos como tales.
        assertEquals(175.0, porNombre["Volea"]?.cantidad?.valor)
        assertNull(porNombre["Volea"]?.golpe)
        assertEquals(118.0, porNombre["Globo"]?.cantidad?.valor)
        assertNull(porNombre["Globo"]?.golpe)
    }

    @Test
    fun `los conocidos van delante de los agregados`() {
        // La pantalla de confirmación tiene que leerse siempre igual, venga la captura
        // como venga: primero el repertorio en su orden, los agregados detrás.
        val leida = LecturaDeCaptura.leerTrozos(
            listOf(
                Trozo("Volea", 0.20, 0.10), Trozo("175", 0.85, 0.10),
                Trozo("Derecha", 0.20, 0.20), Trozo("86", 0.85, 0.20),
            )
        )
        assertEquals(listOf("Derecha", "Volea"), leida.golpes.map { it.nombre })
    }

    // ─── Radar de calidad: el número ENCIMA del nombre ───

    @Test
    fun `el radar de calidad pone el numero encima del golpe`() {
        val leida = LecturaDeCaptura.leerTrozos(
            listOf(
                Trozo("CALIDAD POR GOLPE", 0.30, 0.10),
                Trozo("3.61", 0.50, 0.20), Trozo("VOLEA", 0.50, 0.25),
                Trozo("4.43", 0.20, 0.33), Trozo("REMATE", 0.20, 0.38),
                Trozo("2.99", 0.20, 0.60), Trozo("BANDEJA", 0.20, 0.65),
            )
        )
        val porNombre = leida.golpes.associateBy { it.nombre }
        assertEquals(3.61, porNombre["Volea"]?.nota?.valor)
        assertEquals(4.43, porNombre["Remate"]?.nota?.valor)
        assertEquals(2.99, porNombre["Bandeja"]?.nota?.valor)
        // Con decimales es nota, no recuento.
        assertNull(porNombre["Remate"]?.cantidad)
    }

    // ─── La media del jugador no es la calidad de un golpe ───

    @Test
    fun `la calidad media del jugador no se confunde con la de un golpe`() {
        // "Calidad Media Jugador" contiene "calidad". Buscando el rótulo corto primero,
        // la media del jugador se consumiría como si fuera la calidad de algún golpe.
        val leida = LecturaDeCaptura.leerTrozos(
            listOf(
                Trozo("PROGRESO DE LA SESIÓN", 0.30, 0.10),
                Trozo("Nivel Sesión", 0.30, 0.16),
                Trozo("Calidad Media Jugador", 0.70, 0.16),
                Trozo("3.45", 0.70, 0.22),
                Trozo("3.51", 0.90, 0.30),
            )
        )
        assertEquals(3.45, leida.mediaDelJugador?.valor)
    }

    // ─── Lo que no se da por bueno ───

    @Test
    fun `un nivel imposible no se trae`() {
        // Si en la línea del nivel se lee 3500, es que el reconocedor se comió la coma.
        // Traerlo metería un nivel de 3500 en la liga.
        val leida = LecturaDeCaptura.leer(listOf("Nivel", "3500"))
        assertNull(leida.nivelSesion)
        assertTrue(leida.sinEntender.contains("3500"))
    }

    @Test
    fun `la coma es decimal y la escala no es un dato`() {
        assertEquals(listOf(3.5), LecturaDeCaptura.numerosDe("3,5"))
        assertEquals(listOf(3.5), LecturaDeCaptura.numerosDe("3.5"))
        // "3,5/7": el 7 es el máximo de la escala, no un dato del jugador.
        assertEquals(listOf(3.5), LecturaDeCaptura.numerosDe("3,5/7"))
    }

    @Test
    fun `un texto con forma de reloj no da numeros sueltos`() {
        // Si "01:39:46" diera [1, 39, 46], cualquier búsqueda de número cerca se quedaría
        // con el 1. El tiempo solo lo lee quien sabe interpretarlo.
        assertEquals(emptyList(), LecturaDeCaptura.numerosDe("01:39:46"))
        assertEquals(99.77, assertNotNull(LecturaDeCaptura.minutosDe("01:39:46")), 0.05)
        assertEquals(92.0, LecturaDeCaptura.minutosDe("92 min"))
    }

    @Test
    fun `los acentos, las mayusculas y los puntos no importan`() {
        assertEquals("reves", LecturaDeCaptura.normalizar("Revés"))
        assertEquals("num golpes", LecturaDeCaptura.normalizar("Num. golpes"))
        assertEquals("volea rev", LecturaDeCaptura.normalizar("Volea Rev."))
        assertEquals("nivel de sesion", LecturaDeCaptura.normalizar("  Nivel   de  Sesión  "))
    }

    @Test
    fun `una volea sin abreviar tampoco se confunde con una derecha`() {
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
    fun `una captura sin numeros no inventa ceros`() {
        val leida = LecturaDeCaptura.leer(listOf("Nivel", "Golpes", "Tiempo"))
        assertNull(leida.nivelSesion)
        assertNull(leida.totalGolpes)
        assertNull(leida.duracionMin)
        assertTrue(leida.vacia)
    }

    @Test
    fun `lo que no se entiende se guarda para poder ensenarlo`() {
        val leida = LecturaDeCaptura.leer(listOf("Resumen semanal", "Comparte tu sesión"))
        assertTrue(leida.vacia)
        assertEquals(listOf("Resumen semanal", "Comparte tu sesión"), leida.sinEntender)
    }

    @Test
    fun `una captura vacia no revienta`() {
        assertTrue(LecturaDeCaptura.leerTrozos(emptyList()).vacia)
        assertTrue(LecturaDeCaptura.leer(listOf("", "   ")).vacia)
    }
}
