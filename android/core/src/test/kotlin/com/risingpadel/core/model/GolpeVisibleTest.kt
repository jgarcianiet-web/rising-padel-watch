package com.risingpadel.core.model

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class GolpeVisibleTest {

    @Test
    fun `la vibora se pliega dentro de la bandeja`() {
        assertEquals(GolpeVisible.BANDEJA, GolpeVisible.de(ShotType.VIBORA))
        assertEquals(GolpeVisible.BANDEJA, GolpeVisible.de(ShotType.BANDEJA))
    }

    @Test
    fun `la volea pierde el lado`() {
        assertEquals(GolpeVisible.VOLEA, GolpeVisible.de(ShotType.FOREHAND_VOLLEY))
        assertEquals(GolpeVisible.VOLEA, GolpeVisible.de(ShotType.BACKHAND_VOLLEY))
    }

    @Test
    fun `el globo es un golpe de primera y tiene su sitio`() {
        assertEquals(GolpeVisible.GLOBO, GolpeVisible.de(ShotType.LOB))
        assertEquals("Globo", GolpeVisible.GLOBO.etiqueta)
    }

    @Test
    fun `lo que el reloj no supo clasificar no se le enseña a nadie`() {
        assertNull(GolpeVisible.de(ShotType.UNKNOWN))
    }

    @Test
    fun `el repertorio visible son siete golpes`() {
        // Los cinco del MVP (derecha, revés, volea, bandeja, remate) más el globo, más
        // el saque, que se queda porque el detector lo saca 5 de 5 desde la firma del
        // brazo armado.
        assertEquals(7, GolpeVisible.entries.size)
    }

    @Test
    fun `las notas se promedian al plegar y los recuentos se suman`() {
        val notas = mapOf(
            ShotType.BANDEJA to 3.0f,
            ShotType.VIBORA to 3.4f,
            ShotType.FOREHAND to 4.0f,
            ShotType.UNKNOWN to 6.9f,
        )
        val agrupadas = GolpeVisible.agruparNotas(notas)
        assertEquals(3.2f, agrupadas[GolpeVisible.BANDEJA]!!, 0.001f)
        assertEquals(4.0f, agrupadas[GolpeVisible.DERECHA]!!, 0.001f)
        // Sin clasificar no se enseña: no puede aparecer como un golpe más.
        assertEquals(2, agrupadas.size)

        val recuentos = mapOf(
            ShotType.BANDEJA to 12,
            ShotType.VIBORA to 3,
            ShotType.FOREHAND_VOLLEY to 4,
            ShotType.BACKHAND_VOLLEY to 6,
            ShotType.SMASH to 0,
        )
        val contados = GolpeVisible.agruparRecuentos(recuentos)
        assertEquals(15, contados[GolpeVisible.BANDEJA])
        assertEquals(10, contados[GolpeVisible.VOLEA])
        // Un tipo con cero golpes no ocupa sitio en la ficha.
        assertNull(contados[GolpeVisible.REMATE])
    }

    @Test
    fun `el orden es el del repertorio, no el del mapa de entrada`() {
        // La ficha del partido tiene que salir siempre en el mismo orden, venga como
        // venga el mapa: si no, dos partidos del mismo jugador se leen distinto.
        val notas = mapOf(
            ShotType.SERVE to 3f,
            ShotType.SMASH to 3f,
            ShotType.FOREHAND to 3f,
        )
        assertEquals(
            listOf(GolpeVisible.DERECHA, GolpeVisible.REMATE, GolpeVisible.SAQUE),
            GolpeVisible.agruparNotas(notas).keys.toList(),
        )
    }
}
