package com.risingpadel.core.liga

import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class LigaModelsTest {

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    @Test
    fun `un backup de la app Expo importa sin transformacion`() {
        // Recorte real del shape del backup: campos de la web-app vieja, strings en el
        // perfil, y un partido sin la mitad de los campos nuevos.
        val backup = """
            {
              "matches": [
                {"id": 1754000000000, "fecha": "2026-07-12", "tipo": "competitivo",
                 "resultado": "victoria", "sets": "6-4, 7-6(7-3)",
                 "objetivos": [true, false, true], "nivelBand": 3.4}
              ],
              "objetivos": ["Menos de 5 errores no forzados", "Ganar el 60% de puntos en la red",
                            "Actitud: no protestar ningún punto"],
              "perfil": {"nivelPlaytomic": "2.75", "nivelObjetivo": "3.5"},
              "analisis": {"lectura": "Buena racha", "foco": "Sube tras el globo"}
            }
        """.trimIndent()

        val state = json.decodeFromString(LigaState.serializer(), backup)
        assertEquals(1, state.matches.size)
        val match = state.matches.first()
        assertEquals("victoria", match.resultado)
        assertEquals("reves", match.posicion)
        assertTrue(match.bienJugado)
        assertEquals("2.75", state.perfil.nivelPlaytomic)
        assertEquals("Sube tras el globo", state.analisis?.foco)

        // Y la ida y vuelta no pierde nada.
        val reexportado = json.encodeToString(LigaState.serializer(), state)
        assertEquals(state, json.decodeFromString(LigaState.serializer(), reexportado))
    }

    @Test
    fun `la racha cuenta bien jugados consecutivos desde el mas reciente`() {
        fun partido(fecha: String, vararg objetivos: Boolean) =
            LigaMatch(id = fecha.hashCode().toLong(), fecha = fecha, objetivos = objetivos.toList())

        val matches = listOf(
            partido("2026-07-01", true, true, false),   // bien jugado
            partido("2026-07-08", false, false, true),  // no — corta la racha vieja
            partido("2026-07-15", true, true, true),    // bien jugado
            partido("2026-07-22", true, false, true),   // bien jugado
        )
        assertEquals(2, LigaMetrics.racha(matches))
        assertEquals(2, LigaMetrics.mejorRacha(matches))
        assertEquals(0, LigaMetrics.pctVictorias(matches))
    }

    @Test
    fun `el nivel de sesion cae a la media de la curva si falta el directo`() {
        val match = LigaMatch(id = 1, bandInicio = 3.0, bandFin = 4.0)
        assertEquals(3.5, LigaMetrics.nivelDeSesion(match))
        assertEquals(null, LigaMetrics.nivelDeSesion(LigaMatch(id = 2)))
    }
}
