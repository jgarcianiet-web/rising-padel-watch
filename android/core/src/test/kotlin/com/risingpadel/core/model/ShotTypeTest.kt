package com.risingpadel.core.model

import kotlin.test.Test
import kotlin.test.assertEquals

class ShotTypeTest {

    @Test
    fun `cada tipo sobrevive a la ida y vuelta por el contrato`() {
        ShotType.entries.forEach { type ->
            assertEquals(type, ShotType.fromWire(type.wireName))
        }
    }

    /** Sesiones de antes de separar los golpes altos: "overhead" los agrupaba todos. */
    @Test
    fun `el overhead legado se mapea a bandeja`() {
        assertEquals(ShotType.BANDEJA, ShotType.fromWire("overhead"))
    }

    @Test
    fun `un tipo desconocido cae a UNKNOWN en vez de romper`() {
        assertEquals(ShotType.UNKNOWN, ShotType.fromWire("globo"))
    }
}
