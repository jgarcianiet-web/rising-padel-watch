package com.risingpadel.core.level

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class LevelAnchorTest {

    private fun tabla(vararg puntos: Triple<Float, Float, Int>) = LevelAnchorTable(
        puntos = puntos.map { (nivel, medido, jugadores) ->
            AnchorPoint(nivelDeclarado = nivel, medidoMediana = medido, jugadores = jugadores)
        }
    )

    @Test
    fun `sin anclas suficientes no se traduce nada`() {
        // Una sola ancla no dibuja una curva.
        val una = tabla(Triple(3f, 3.5f, 10))
        assertTrue(!una.fiable)
        assertNull(una.equivalente(4f))

        // Dos anclas, pero una sostenida por un solo jugador: sigue sin valer.
        val floja = tabla(Triple(3f, 3.5f, 10), Triple(5f, 5.0f, 1))
        assertTrue(!floja.fiable)
    }

    @Test
    fun `entre dos anclas se interpola`() {
        // Los de nivel 3 miden 3.0 y los de nivel 5 miden 5.0: a mitad de camino,
        // nivel 4.
        val t = tabla(Triple(3f, 3.0f, 6), Triple(5f, 5.0f, 6))
        assertEquals(4f, t.equivalente(4.0f)!!, 0.01f)
        assertEquals(3.5f, t.equivalente(3.5f)!!, 0.01f)
    }

    @Test
    fun `la medicion y el nivel no tienen por que ir a la par`() {
        // El caso real: el reloj mide en su propia escala y los niveles declarados
        // están comprimidos arriba — de 4.5 a 6 medido solo hay medio nivel de juego.
        val t = tabla(
            Triple(2f, 2.0f, 5),
            Triple(4f, 4.5f, 8),
            Triple(4.5f, 6.0f, 5),
        )
        val equivalente = t.equivalente(5.25f)!!
        assertTrue(equivalente in 4f..4.5f, "esperaba entre 4 y 4.5: $equivalente")
    }

    @Test
    fun `fuera del rango medido no se extrapola`() {
        // Pegar más fuerte que el jugador más fuerte medido no te hace profesional.
        val t = tabla(Triple(3f, 3.0f, 6), Triple(5f, 5.0f, 6))
        assertEquals(5f, t.equivalente(9.0f)!!, 0.01f)
        assertEquals(3f, t.equivalente(0.5f)!!, 0.01f)
    }

    @Test
    fun `el percentil compara con la comunidad y necesita gente`() {
        val comunidad = listOf(2.0f, 2.5f, 3.0f, 3.2f, 3.8f, 4.1f, 4.4f, 5.0f, 5.5f, 6.0f)
        val lectura = LecturaDeNivel.calcular(4.2f, LevelAnchorTable(), comunidad)
        assertEquals(60, lectura.percentil) // 6 de 10 por debajo
        // Sin equivalencia: la tabla está vacía y no se inventa.
        assertNull(lectura.equivalente)

        // Con cuatro personas, un percentil no significa nada.
        val pocas = LecturaDeNivel.calcular(4.2f, LevelAnchorTable(), listOf(2f, 3f, 4f, 5f))
        assertNull(pocas.percentil)
    }

    @Test
    fun `la lectura completa junta medicion, equivalencia y percentil`() {
        val t = tabla(Triple(3f, 3.0f, 6), Triple(5f, 5.0f, 6))
        val comunidad = List(10) { 2.0f + it * 0.4f }
        val lectura = LecturaDeNivel.calcular(4.0f, t, comunidad)
        assertEquals(4.0f, lectura.medido)
        assertEquals(4.0f, lectura.equivalente!!, 0.01f)
        assertTrue(lectura.percentil!! > 0)
    }
}
