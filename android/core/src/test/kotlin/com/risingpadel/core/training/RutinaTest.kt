package com.risingpadel.core.training

import com.risingpadel.core.model.ShotType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class RutinaTest {

    private val corta = Rutina(
        id = "test",
        nombre = "Corta",
        proposito = "Dos pasos para probar",
        pasos = listOf(
            PasoDeRutina(ShotType.FOREHAND, 3),
            PasoDeRutina(ShotType.SMASH, 2),
        ),
    )

    @Test
    fun `los golpes del tipo que toca suman y los demas no`() {
        val curso = RutinaEnCurso(corta)

        assertEquals(EventoDeRutina.CUENTA, curso.onShot(ShotType.FOREHAND))
        assertEquals(EventoDeRutina.NO_CUENTA, curso.onShot(ShotType.BACKHAND))
        assertEquals(EventoDeRutina.CUENTA, curso.onShot(ShotType.FOREHAND))

        val progreso = curso.progreso!!
        assertEquals(2, progreso.hechos)
        assertEquals(1, progreso.fueraDeTipo)
        assertEquals(1, progreso.restantes)
    }

    @Test
    fun `un golpe sin clasificar nunca completa un ejercicio`() {
        val curso = RutinaEnCurso(corta)
        repeat(5) { curso.onShot(ShotType.UNKNOWN) }
        assertEquals(0, curso.progreso!!.hechos)
        assertEquals(ShotType.FOREHAND, curso.progreso!!.paso.type)
    }

    @Test
    fun `al completar el paso se pasa solo al siguiente`() {
        val curso = RutinaEnCurso(corta)
        curso.onShot(ShotType.FOREHAND)
        curso.onShot(ShotType.FOREHAND)
        assertEquals(EventoDeRutina.PASO_COMPLETADO, curso.onShot(ShotType.FOREHAND))

        val progreso = curso.progreso!!
        assertEquals(ShotType.SMASH, progreso.paso.type)
        assertEquals(1, progreso.indice)
        assertEquals(0, progreso.hechos, "el contador arranca de cero en cada ejercicio")
        assertEquals(0, progreso.fueraDeTipo, "y los golpes sueltos del paso anterior no se arrastran")
    }

    @Test
    fun `el ultimo paso termina la rutina`() {
        val curso = RutinaEnCurso(corta)
        repeat(3) { curso.onShot(ShotType.FOREHAND) }
        curso.onShot(ShotType.SMASH)
        assertEquals(EventoDeRutina.TERMINADA, curso.onShot(ShotType.SMASH))

        assertTrue(curso.terminada)
        assertNull(curso.progreso, "una rutina terminada no tiene paso en curso")
        assertEquals(5, curso.golpesValidos)
    }

    @Test
    fun `terminada no sigue contando`() {
        val curso = RutinaEnCurso(corta)
        repeat(3) { curso.onShot(ShotType.FOREHAND) }
        repeat(2) { curso.onShot(ShotType.SMASH) }

        assertEquals(EventoDeRutina.YA_TERMINADA, curso.onShot(ShotType.FOREHAND))
        assertEquals(5, curso.golpesValidos)
    }

    @Test
    fun `saltar un paso lo cierra con lo que llevara`() {
        // La máquina se queda sin bolas a mitad: hay que poder seguir.
        val curso = RutinaEnCurso(corta)
        curso.onShot(ShotType.FOREHAND)
        assertEquals(EventoDeRutina.PASO_COMPLETADO, curso.saltarPaso())

        assertEquals(ShotType.SMASH, curso.progreso!!.paso.type)
        assertEquals(1, curso.golpesValidos, "lo que se hizo antes de saltar cuenta")
    }

    @Test
    fun `saltar el ultimo paso termina la rutina`() {
        val curso = RutinaEnCurso(corta)
        curso.saltarPaso()
        assertEquals(EventoDeRutina.TERMINADA, curso.saltarPaso())
        assertTrue(curso.terminada)
    }

    @Test
    fun `el resumen dice cuanto se hizo de cada ejercicio`() {
        val curso = RutinaEnCurso(corta)
        curso.onShot(ShotType.FOREHAND)
        curso.onShot(ShotType.FOREHAND)
        curso.saltarPaso()
        curso.onShot(ShotType.SMASH)

        val resumen = curso.resumen()
        assertEquals(2, resumen.size)
        assertEquals(ShotType.FOREHAND to 2, resumen[0].first.type to resumen[0].second)
        assertEquals(ShotType.SMASH to 1, resumen[1].first.type to resumen[1].second)
    }

    @Test
    fun `una rutina recien empezada no tiene nada hecho`() {
        val curso = RutinaEnCurso(corta)
        assertEquals(0, curso.golpesValidos)
        assertEquals(0f, curso.progreso!!.fraccion, 0.001f)
        assertEquals(2, curso.progreso!!.totalPasos)
    }

    @Test
    fun `las rutinas de fabrica estan bien formadas`() {
        assertTrue(Rutina.DE_FABRICA.isNotEmpty())
        assertEquals(
            Rutina.DE_FABRICA.map { it.id }.distinct().size,
            Rutina.DE_FABRICA.size,
            "dos rutinas con el mismo id se pisarían al guardarlas",
        )
        for (rutina in Rutina.DE_FABRICA) {
            assertTrue(rutina.pasos.isNotEmpty(), "${rutina.id} no tiene ejercicios")
            assertTrue(rutina.golpesTotales > 0)
            assertTrue(
                rutina.pasos.none { it.type == ShotType.UNKNOWN },
                "${rutina.id} pide un golpe que nadie puede dar a propósito",
            )
        }
    }
}
