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
    fun `la volea conserva el lado`() {
        // Cuesta acierto de tabla (85 % a 76 % en la tanda de 42) y se mantiene igual:
        // tener floja la volea de derecha no es lo mismo que tenerla de revés, y sin
        // esa distinción la app no sirve para entrenar.
        assertEquals(GolpeVisible.VOLEA_DERECHA, GolpeVisible.de(ShotType.FOREHAND_VOLLEY))
        assertEquals(GolpeVisible.VOLEA_REVES, GolpeVisible.de(ShotType.BACKHAND_VOLLEY))
    }

    @Test
    fun `el globo es un golpe de primera y tambien lleva lado`() {
        assertEquals(GolpeVisible.GLOBO_DERECHA, GolpeVisible.de(ShotType.FOREHAND_LOB))
        assertEquals(GolpeVisible.GLOBO_REVES, GolpeVisible.de(ShotType.BACKHAND_LOB))
        assertEquals("Globo de derecha", GolpeVisible.GLOBO_DERECHA.etiqueta)
    }

    @Test
    fun `lo que el reloj no supo clasificar no se le enseña a nadie`() {
        assertNull(GolpeVisible.de(ShotType.UNKNOWN))
    }

    @Test
    fun `el repertorio visible son nueve golpes`() {
        // Derecha, revés, las dos voleas, los dos globos, bandeja, remate y saque. La
        // única familia plegada es víbora dentro de bandeja.
        assertEquals(9, GolpeVisible.entries.size)
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
        assertEquals(4, contados[GolpeVisible.VOLEA_DERECHA])
        assertEquals(6, contados[GolpeVisible.VOLEA_REVES])
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
