package com.risingpadel.core.video

import com.risingpadel.core.model.ShotType
import com.risingpadel.core.video.SincronizacionDeVideo.GolpeEnTiempo
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Casar el vídeo con el reloj.
 *
 * El test que de verdad importa aquí no es el del caso bonito: es el de los golpes
 * pegados. Dos golpes de una tanda van a segundo y medio, así que un desfase de dos
 * segundos empareja cada marca con el golpe SIGUIENTE y produce un informe limpio y
 * completamente falso. Un emparejamiento mal alineado es peor que ninguno porque parece
 * correcto, y de ahí salen los dos requisitos que se comprueban abajo: respetar el orden
 * y ser uno a uno.
 */
class SincronizacionDeVideoTest {

    private val base = 1_760_000_000_000L

    private fun golpes(vararg segundos: Double, tipo: ShotType? = null) =
        segundos.map { GolpeEnTiempo(base + (it * 1000).toLong(), tipo) }

    @Test
    fun `sin desfase cada marca casa con su golpe`() {
        val video = golpes(1.0, 3.0, 5.0, 7.0)
        val reloj = golpes(1.0, 3.0, 5.0, 7.0)
        val cruce = SincronizacionDeVideo.cruzar(video, reloj, desfaseMs = 0)

        assertEquals(4, cruce.pares.size)
        assertTrue(cruce.soloEnVideo.isEmpty())
        assertTrue(cruce.soloEnReloj.isEmpty())
        assertEquals(1.0, cruce.cobertura)
    }

    @Test
    fun `sin corregir el desfase el emparejamiento sale corrido, y eso es el peligro`() {
        // El reloj va 1,8 s por delante y los golpes van a 1,5 s. Al no corregir, cada
        // marca cae a 300 ms del golpe ANTERIOR — dentro de la ventana — así que salen
        // cuatro pares con buena pinta que están todos corridos un golpe. Esta es la
        // trampa entera de este fichero, y se afirma aquí para que quede documentada:
        // el número de pares NO basta para fiarse, hay que mirar el resto.
        val video = golpes(1.0, 2.5, 4.0, 5.5, 7.0)
        val reloj = golpes(2.8, 4.3, 5.8, 7.3, 8.8)

        val corrido = SincronizacionDeVideo.cruzar(video, reloj, desfaseMs = 0)
        assertEquals(4, corrido.pares.size)
        // Todos los restos pegados al borde de la ventana: la señal de que está corrido.
        assertTrue(
            corrido.pares.all { abs(it.restoMs) >= 250 },
            "restos: ${corrido.pares.map { it.restoMs }}"
        )
        // Y está corrido de verdad: la marca 1 casa con el golpe 0.
        assertEquals(
            listOf(1 to 0, 2 to 1, 3 to 2, 4 to 3),
            corrido.pares.map { it.indiceVideo to it.indiceReloj }
        )

        // Con el desfase bueno: los cinco, y cuadrando al milisegundo.
        val bueno = SincronizacionDeVideo.cruzar(video, reloj, desfaseMs = 1_800)
        assertEquals(5, bueno.pares.size)
        assertTrue(bueno.pares.all { it.restoMs == 0L }, "restos: ${bueno.pares.map { it.restoMs }}")
        assertEquals(
            listOf(0 to 0, 1 to 1, 2 to 2, 3 to 3, 4 to 4),
            bueno.pares.map { it.indiceVideo to it.indiceReloj }
        )
    }

    @Test
    fun `el desfase automatico lo encuentra`() {
        val video = golpes(1.0, 2.5, 4.0, 5.5, 7.0, 9.0, 11.0)
        val reloj = golpes(2.8, 4.3, 5.8, 7.3, 8.8, 10.8, 12.8)

        val (desfase, cuenta) = SincronizacionDeVideo.estimarDesfaseMs(video, reloj)
        assertEquals(1_800L, desfase, "desfase: $desfase")
        assertEquals(7, cuenta)
    }

    @Test
    fun `con golpes pegados y mal alineado no se empareja de mentira`() {
        // ESTE es el test importante. Golpes cada 1,5 s y un desfase real de 1,5 s: si el
        // emparejador aceptara desplazarse un golpe entero, encontraría pares "perfectos"
        // casando cada marca con la siguiente. Sin corregir el desfase, la respuesta
        // honesta es que no cuadra casi nada.
        val video = golpes(0.0, 1.5, 3.0, 4.5, 6.0)
        val reloj = golpes(1.5, 3.0, 4.5, 6.0, 7.5)

        val sinCorregir = SincronizacionDeVideo.cruzar(video, reloj, desfaseMs = 0)
        // Las cuatro marcas del final caen justo encima del golpe anterior, así que SÍ
        // emparejan — y eso es correcto aritméticamente. Lo que no puede pasar es que
        // además se inventen pares: uno a uno y en orden.
        assertEquals(4, sinCorregir.pares.size)
        assertEquals(1, sinCorregir.soloEnVideo.size)
        assertEquals(1, sinCorregir.soloEnReloj.size)
        // Y cada índice aparece una sola vez en cada lado.
        assertEquals(
            sinCorregir.pares.size,
            sinCorregir.pares.map { it.indiceVideo }.distinct().size
        )
        assertEquals(
            sinCorregir.pares.size,
            sinCorregir.pares.map { it.indiceReloj }.distinct().size
        )
    }

    @Test
    fun `el emparejamiento respeta el orden`() {
        // Si la marca i casa con el golpe j, la marca i+1 no puede casar con uno anterior:
        // sería el tiempo andando hacia atrás. Es el error clásico de un voraz.
        val video = golpes(1.0, 1.4, 5.0)
        val reloj = golpes(1.2, 1.5, 5.1)
        val cruce = SincronizacionDeVideo.cruzar(video, reloj, desfaseMs = 0)

        val porVideo = cruce.pares.sortedBy { it.indiceVideo }
        for (k in 1 until porVideo.size) {
            assertTrue(
                porVideo[k].indiceReloj > porVideo[k - 1].indiceReloj,
                "pares desordenados: ${porVideo.map { it.indiceVideo to it.indiceReloj }}"
            )
        }
    }

    @Test
    fun `un golpe que el reloj no vio sale como solo en video`() {
        // Es la mitad del informe que de verdad mide el detector: lo que se le escapó.
        val video = golpes(1.0, 2.5, 4.0)
        val reloj = golpes(1.0, 4.0)
        val cruce = SincronizacionDeVideo.cruzar(video, reloj, desfaseMs = 0)

        assertEquals(2, cruce.pares.size)
        assertEquals(listOf(1), cruce.soloEnVideo)
        assertTrue(cruce.soloEnReloj.isEmpty())
    }

    @Test
    fun `un golpe que el reloj se invento sale como solo en reloj`() {
        val video = golpes(1.0, 4.0)
        val reloj = golpes(1.0, 2.5, 4.0)
        val cruce = SincronizacionDeVideo.cruzar(video, reloj, desfaseMs = 0)

        assertEquals(2, cruce.pares.size)
        assertEquals(listOf(1), cruce.soloEnReloj)
    }

    @Test
    fun `una claqueta da el desfase`() {
        val desfase = SincronizacionDeVideo.desfaseConUnaAncla(
            marcaEpochMs = base + 2_000,
            golpeEpochMs = base + 3_800,
        )
        assertEquals(1_800L, desfase)
    }

    @Test
    fun `dos claquetas corrigen la deriva`() {
        // Diez minutos de vídeo en los que el reloj corre un 0,1 % más rápido: al final
        // son 600 ms, el doble de la ventana de emparejado. Sin escala, los golpes del
        // final se quedan fuera.
        val escalaReal = 1.001
        val marca1 = base + 10_000
        val marca2 = base + 610_000
        val golpe1 = base + (10_000 * escalaReal).toLong() + 1_000
        val golpe2 = base + (610_000 * escalaReal).toLong() + 1_000

        val resultado = assertNotNull(
            SincronizacionDeVideo.desfaseConDosAnclas(marca1, golpe1, marca2, golpe2)
        )
        val (desfase, escala) = resultado
        assertEquals(escalaReal, escala, 0.0001)

        // Con esa escala y ese desfase, una marca del final cae sobre su golpe.
        val marcaFinal = base + 600_000
        val golpeFinal = base + (600_000 * escalaReal).toLong() + 1_000
        val cruce = SincronizacionDeVideo.cruzar(
            listOf(GolpeEnTiempo(marcaFinal)),
            listOf(GolpeEnTiempo(golpeFinal)),
            desfaseMs = desfase,
            escala = escala,
        )
        assertEquals(1, cruce.pares.size, "resto: ${cruce.pares.firstOrNull()?.restoMs}")
    }

    @Test
    fun `dos claquetas pegadas no valen`() {
        // Con los dos puntos a cinco segundos, la escala sale de dividir por casi nada y
        // cualquier error al señalar el fotograma se convierte en una deriva inventada.
        assertNull(
            SincronizacionDeVideo.desfaseConDosAnclas(
                base, base + 1_000, base + 5_000, base + 6_000
            )
        )
    }

    @Test
    fun `el acierto de tipo solo se calcula cuando hay tipos`() {
        val video = golpes(1.0, 3.0).map { it.copy(tipo = ShotType.BANDEJA) }
        val relojBien = golpes(1.0, 3.0).map { it.copy(tipo = ShotType.BANDEJA) }
        val relojMal = listOf(
            GolpeEnTiempo(base + 1_000, ShotType.BANDEJA),
            GolpeEnTiempo(base + 3_000, ShotType.VIBORA),
        )

        val cruceBien = SincronizacionDeVideo.cruzar(video, relojBien, desfaseMs = 0)
        assertEquals(1.0, cruceBien.aciertoDeTipo(video, relojBien))

        val cruceMal = SincronizacionDeVideo.cruzar(video, relojMal, desfaseMs = 0)
        assertEquals(0.5, cruceMal.aciertoDeTipo(video, relojMal))

        // Sin tipos en el vídeo no se puede hablar de acierto: null, no cero. Un cero
        // diría que el reloj falla en todo cuando lo que pasa es que no se sabe.
        val sinTipo = golpes(1.0, 3.0)
        val cruceSinTipo = SincronizacionDeVideo.cruzar(sinTipo, relojBien, desfaseMs = 0)
        assertNull(cruceSinTipo.aciertoDeTipo(sinTipo, relojBien))
    }

    @Test
    fun `el resto mediano distingue un cuadre bueno de uno corrido`() {
        // El número de pares no basta para fiarse: los dos cruces de abajo tienen cuatro
        // y cinco pares respectivamente, y uno está corrido un golpe entero. Lo que los
        // separa es el resto.
        val video = golpes(1.0, 2.5, 4.0, 5.5, 7.0)
        val reloj = golpes(2.8, 4.3, 5.8, 7.3, 8.8)

        val corrido = SincronizacionDeVideo.cruzar(video, reloj, desfaseMs = 0)
        val bueno = SincronizacionDeVideo.cruzar(video, reloj, desfaseMs = 1_800)

        assertEquals(300L, corrido.restoMedianoMs)
        assertEquals(0L, bueno.restoMedianoMs)
        assertNull(SincronizacionDeVideo.cruzar(emptyList(), reloj, desfaseMs = 0).restoMedianoMs)
    }

    @Test
    fun `listas vacias no revientan`() {
        val cruce = SincronizacionDeVideo.cruzar(emptyList(), golpes(1.0), desfaseMs = 0)
        assertTrue(cruce.pares.isEmpty())
        assertEquals(listOf(0), cruce.soloEnReloj)
        assertEquals(0.0, cruce.cobertura)
        assertEquals(0L to 0, SincronizacionDeVideo.estimarDesfaseMs(emptyList(), emptyList()))
    }
}
