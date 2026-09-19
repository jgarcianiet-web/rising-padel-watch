package com.risingpadel.core.level

import com.risingpadel.core.model.HealthMetrics
import com.risingpadel.core.model.HeartRateZones
import com.risingpadel.core.model.PadelSession
import com.risingpadel.core.model.Platform
import com.risingpadel.core.model.PlayerProfile
import com.risingpadel.core.model.Shot
import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType
import com.risingpadel.core.model.SourceInfo
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DimensionesDeNivelTest {

    private fun golpe(
        type: ShotType = ShotType.FOREHAND,
        speedKmh: Float = 45f,
        sweptDeg: Float = 200f,
        confidence: Float = 0.9f,
    ) = Shot(
        offsetMs = 0,
        type = type,
        racketSpeedKmh = speedKmh,
        impactG = 5f,
        confidence = confidence,
        features = ShotFeatures(
            sweptAngleDeg = sweptDeg,
            peakGyroRadS = speedKmh / 2.34f,
            elevationDeg = 20f,
            axialRotationRadS = 3f,
            swingDurationMs = 300,
        ),
    )

    private fun sesion(
        golpes: List<Shot> = emptyList(),
        minutos: Int = 75,
        health: HealthMetrics = HealthMetrics.EMPTY,
    ) = PadelSession(
        sessionId = "s1",
        source = SourceInfo(Platform.WEAROS, "pixel-watch", "1.0"),
        startedAtEpochMs = 0,
        endedAtEpochMs = minutos * 60_000L,
        profile = PlayerProfile(),
        shots = golpes,
        health = health,
    )

    /** Zonas que cubren toda la sesión, para que la cobertura no sea lo que falla. */
    private fun zonas(minutos: Int, vararg reparto: Pair<String, Int>): HealthMetrics {
        val total = reparto.sumOf { (_, segundos) -> segundos }
        require(total == minutos * 60) { "el reparto debe cubrir la sesión entera" }
        return HealthMetrics(zones = HeartRateZones(reparto.toMap()))
    }

    private fun velocidadMedia(type: ShotType): Float {
        val banda = LevelConfig.DEFAULT_BANDS.getValue(type)
        return (banda.speedAtLevel1 + banda.speedAtLevel7) / 2
    }

    private fun anguloIdeal(type: ShotType): Float =
        LevelConfig.DEFAULT_BANDS.getValue(type).idealSweptDeg

    private fun golpesDe(type: ShotType, cuantos: Int, speedKmh: Float = velocidadMedia(type)) =
        List(cuantos) { golpe(type = type, speedKmh = speedKmh, sweptDeg = anguloIdeal(type)) }

    // --- lo que NO se mide: el corazón de esta clase ---

    /**
     * Previene la regresión que más daño haría: que alguien añada "toma de decisiones"
     * con una fórmula de velocidad y arco disfrazada de táctica. El reloj no sabe dónde
     * estaba la bola ni dónde el rival.
     */
    @Test
    fun `la toma de decisiones no existe como dimension porque el reloj no la puede ver`() {
        assertTrue(
            DimensionDeNivel.entries.none { it.name.contains("DECISI") },
            "ninguna dimensión puede llamarse toma de decisiones: ${DimensionDeNivel.entries}",
        )
    }

    /** La técnica sería `SessionLevel.overall` con otro nombre; duplicarla es mentir dos veces. */
    @Test
    fun `la tecnica no se duplica como dimension aparte`() {
        assertTrue(DimensionDeNivel.entries.none { it.name.contains("TECNIC") })
    }

    @Test
    fun `solo hay seis dimensiones y son las sostenibles con sensores`() {
        assertEquals(
            listOf(
                DimensionDeNivel.ATAQUE,
                DimensionDeNivel.DEFENSA,
                DimensionDeNivel.JUEGO_DE_RED,
                DimensionDeNivel.JUEGO_DE_FONDO,
                DimensionDeNivel.CONSISTENCIA,
                DimensionDeNivel.RENDIMIENTO_FISICO,
            ),
            DimensionDeNivel.entries.toList(),
        )
    }

    // --- dimensiones de golpeo ---

    @Test
    fun `el ataque sale de smash vibora y bandeja`() {
        val dimensiones = DimensionesDeNivel.de(
            sesion(golpesDe(ShotType.SMASH, 4) + golpesDe(ShotType.BANDEJA, 4))
        )

        assertNotNull(dimensiones.ataque)
        // Solo los golpes de ataque tienen dato: lo demás no se juega a rellenar.
        assertNull(dimensiones.defensa)
        assertNull(dimensiones.juegoDeRed)
        assertNull(dimensiones.juegoDeFondo)
    }

    @Test
    fun `la defensa sale de los globos que es el golpe defensivo del padel`() {
        val dimensiones = DimensionesDeNivel.de(
            sesion(golpesDe(ShotType.FOREHAND_LOB, 5) + golpesDe(ShotType.BACKHAND_LOB, 5))
        )

        assertNotNull(dimensiones.defensa)
        assertNull(dimensiones.ataque)
    }

    @Test
    fun `el juego de red sale de las dos voleas`() {
        val dimensiones = DimensionesDeNivel.de(
            sesion(
                golpesDe(ShotType.FOREHAND_VOLLEY, 3) + golpesDe(ShotType.BACKHAND_VOLLEY, 3)
            )
        )

        assertNotNull(dimensiones.juegoDeRed)
        assertNull(dimensiones.juegoDeFondo)
    }

    @Test
    fun `el juego de fondo sale de derecha y reves`() {
        val dimensiones = DimensionesDeNivel.de(
            sesion(golpesDe(ShotType.FOREHAND, 10) + golpesDe(ShotType.BACKHAND, 10))
        )

        assertNotNull(dimensiones.juegoDeFondo)
        assertNull(dimensiones.juegoDeRed)
    }

    /**
     * La bandeja y el remate se juegan en la red, pero cuentan una sola vez, en ataque.
     * Si alimentaran también el juego de red, los dos ejes serían el mismo número con
     * dos nombres y la rueda aparentaría medir dos cosas independientes.
     */
    @Test
    fun `los golpes altos cuentan en ataque y no tambien en juego de red`() {
        val dimensiones = DimensionesDeNivel.de(sesion(golpesDe(ShotType.BANDEJA, 12)))

        assertNotNull(dimensiones.ataque)
        assertNull(dimensiones.juegoDeRed)
    }

    /**
     * El saque no es peloteo de fondo ni juego de red. Meterlo en cualquiera de los dos
     * ensuciaría esa dimensión; su nota ya está en `SessionLevel.byShotType`.
     */
    @Test
    fun `el saque no entra en ninguna dimension`() {
        val dimensiones = DimensionesDeNivel.de(sesion(golpesDe(ShotType.SERVE, 30)))

        assertNull(dimensiones.ataque)
        assertNull(dimensiones.defensa)
        assertNull(dimensiones.juegoDeRed)
        assertNull(dimensiones.juegoDeFondo)
    }

    @Test
    fun `un jugador que remata mejor de lo que voleaa saca mas nota en ataque`() {
        val dimensiones = DimensionesDeNivel.de(
            sesion(
                // Remates muy rápidos y voleas con swing largo, que es el error de la red.
                List(8) { golpe(type = ShotType.SMASH, speedKmh = 92f, sweptDeg = 210f) } +
                    List(8) {
                        golpe(type = ShotType.FOREHAND_VOLLEY, speedKmh = 11f, sweptDeg = 120f)
                    }
            )
        )

        val ataque = dimensiones.ataque
        val red = dimensiones.juegoDeRed
        assertNotNull(ataque)
        assertNotNull(red)
        assertTrue(ataque > red, "ataque $ataque debería superar a red $red")
    }

    // --- mínimos: antes en silencio que inventado ---

    @Test
    fun `con menos golpeos que el minimo la dimension no se reporta`() {
        val justo = DimensionesDeNivel.de(sesion(golpesDe(ShotType.SMASH, 5)))
        val unoMenos = DimensionesDeNivel.de(sesion(golpesDe(ShotType.SMASH, 4)))

        assertNotNull(justo.ataque)
        assertNull(unoMenos.ataque)
    }

    /**
     * El mínimo es del grupo y no de cada tipo: tres remates y cuatro bandejas son
     * ataque de sobra que contar, aunque ninguno de los dos llegue a cinco por separado.
     */
    @Test
    fun `el minimo se cuenta sobre el grupo entero y no sobre cada tipo`() {
        val dimensiones = DimensionesDeNivel.de(
            sesion(golpesDe(ShotType.SMASH, 3) + golpesDe(ShotType.BANDEJA, 4))
        )

        assertNotNull(dimensiones.ataque)
    }

    /** Un golpeo que el clasificador no supo identificar no puede sostener una dimensión. */
    @Test
    fun `los golpeos mal clasificados no cuentan para llegar al minimo`() {
        val dimensiones = DimensionesDeNivel.de(
            sesion(List(20) { golpe(type = ShotType.SMASH, confidence = 0.2f) })
        )

        assertNull(dimensiones.ataque)
    }

    @Test
    fun `una sesion vacia no reporta ninguna dimension y no revienta`() {
        val dimensiones = DimensionesDeNivel.de(sesion())

        assertTrue(dimensiones.medidas.isEmpty())
        assertFalse(dimensiones.hayAlgoQueEnsenar)
    }

    @Test
    fun `las medidas solo traen las dimensiones con dato`() {
        val dimensiones = DimensionesDeNivel.de(sesion(golpesDe(ShotType.FOREHAND, 20)))

        assertEquals(
            setOf(DimensionDeNivel.JUEGO_DE_FONDO, DimensionDeNivel.CONSISTENCIA),
            dimensiones.medidas.keys,
        )
        assertTrue(dimensiones.hayAlgoQueEnsenar)
    }

    // --- consistencia: reutilizada, no recalculada ---

    /**
     * Si alguien reimplementara la regularidad aquí, los dos números se separarían al
     * tocar uno solo. Esta dimensión es la del estimador reescalada a 1-7 y nada más.
     */
    @Test
    fun `la consistencia es la del estimador reescalada a la escala de nivel`() {
        val golpes = golpesDe(ShotType.FOREHAND, 20)
        val esperada = LevelEstimator(LevelConfig.current).estimate(golpes).consistency

        val consistencia = DimensionesDeNivel.de(sesion(golpes)).consistencia

        assertNotNull(consistencia)
        assertEquals(1f + esperada * 6f, consistencia, 0.05f)
    }

    /**
     * Con un golpeo por tipo el estimador devuelve un 0,5 de relleno. Ese relleno vale
     * dentro del cálculo global, pero enseñado como "tu consistencia es un 4" sería un
     * número inventado con cara de medida.
     */
    @Test
    fun `sin golpeos repetidos del mismo tipo no hay consistencia que ensenar`() {
        val sueltos = listOf(
            golpe(type = ShotType.FOREHAND),
            golpe(type = ShotType.BACKHAND),
            golpe(type = ShotType.SMASH),
            golpe(type = ShotType.BANDEJA),
            golpe(type = ShotType.SERVE),
        )

        assertNull(DimensionesDeNivel.de(sesion(sueltos)).consistencia)
    }

    @Test
    fun `el jugador regular saca mas consistencia que el irregular`() {
        val regular = DimensionesDeNivel.de(
            sesion(List(40) { golpe(speedKmh = 46f) })
        ).consistencia
        val irregular = DimensionesDeNivel.de(
            sesion(List(40) { i -> golpe(speedKmh = if (i % 2 == 0) 30f else 62f) })
        ).consistencia

        assertNotNull(regular)
        assertNotNull(irregular)
        assertTrue(regular > irregular, "regular $regular vs irregular $irregular")
    }

    // --- rendimiento físico ---

    /** Sin permiso de salud no llega pulso, y sin pulso no hay nada honesto que decir. */
    @Test
    fun `sin datos de salud no hay rendimiento fisico`() {
        assertNull(DimensionesDeNivel.de(sesion(golpesDe(ShotType.FOREHAND, 40))).rendimientoFisico)
    }

    @Test
    fun `en una sesion demasiado corta no se habla de esfuerzo sostenido`() {
        val corta = sesion(
            golpes = golpesDe(ShotType.FOREHAND, 40),
            minutos = 15,
            health = zonas(15, "z4" to 15 * 60),
        )

        assertNull(DimensionesDeNivel.de(corta).rendimientoFisico)
    }

    /**
     * Diez minutos de pulso en una hora describen diez minutos —normalmente los del
     * principio, los más suaves—, no la sesión.
     */
    @Test
    fun `si el pulso solo cubre un rato de la sesion no se reporta`() {
        val malCubierta = sesion(
            golpes = golpesDe(ShotType.FOREHAND, 40),
            minutos = 60,
            health = HealthMetrics(zones = HeartRateZones(mapOf("z4" to 10 * 60))),
        )

        assertNull(DimensionesDeNivel.de(malCubierta).rendimientoFisico)
    }

    @Test
    fun `mas tiempo en zonas altas da mas rendimiento fisico`() {
        val suave = DimensionesDeNivel.de(
            sesion(minutos = 60, health = zonas(60, "z1" to 30 * 60, "z2" to 30 * 60))
        ).rendimientoFisico
        val duro = DimensionesDeNivel.de(
            sesion(minutos = 60, health = zonas(60, "z4" to 30 * 60, "z5" to 30 * 60))
        ).rendimientoFisico

        assertNotNull(suave)
        assertNotNull(duro)
        assertTrue(duro > suave, "duro $duro debería superar a suave $suave")
    }

    @Test
    fun `una sesion entera en zona uno se queda en el suelo de la escala`() {
        val dimensiones = DimensionesDeNivel.de(
            sesion(minutos = 60, health = zonas(60, "z1" to 60 * 60))
        )

        assertEquals(1f, dimensiones.rendimientoFisico)
    }

    @Test
    fun `una sesion entera por encima del noventa por ciento llega al techo`() {
        val dimensiones = DimensionesDeNivel.de(
            sesion(minutos = 60, health = zonas(60, "z5" to 60 * 60))
        )

        assertEquals(7f, dimensiones.rendimientoFisico)
    }

    /** El físico no depende de los golpeos: se puede reportar sin un solo golpe puntuado. */
    @Test
    fun `el rendimiento fisico se reporta aunque no haya golpeos puntuables`() {
        val dimensiones = DimensionesDeNivel.de(
            sesion(
                golpes = List(30) { golpe(type = ShotType.UNKNOWN) },
                minutos = 60,
                health = zonas(60, "z3" to 60 * 60),
            )
        )

        assertNotNull(dimensiones.rendimientoFisico)
        assertNull(dimensiones.juegoDeFondo)
    }

    // --- escala común ---

    /**
     * Las seis dimensiones se pintan en el mismo eje: si una se saliera de 1-7 la rueda
     * quedaría deformada y el jugador leería un nivel que no existe.
     */
    @Test
    fun `ninguna dimension se sale de la escala de uno a siete`() {
        val bestial = DimensionesDeNivel.de(
            sesion(
                golpes = ShotType.entries.filter { it != ShotType.UNKNOWN }.flatMap { tipo ->
                    List(10) { golpe(type = tipo, speedKmh = 500f, sweptDeg = anguloIdeal(tipo)) }
                },
                minutos = 90,
                health = zonas(90, "z5" to 90 * 60),
            )
        )
        val flojisimo = DimensionesDeNivel.de(
            sesion(
                golpes = ShotType.entries.filter { it != ShotType.UNKNOWN }.flatMap { tipo ->
                    List(10) { golpe(type = tipo, speedKmh = 1f, sweptDeg = 1f) }
                },
                minutos = 90,
                health = zonas(90, "z1" to 90 * 60),
            )
        )

        for (dimensiones in listOf(bestial, flojisimo)) {
            assertEquals(6, dimensiones.medidas.size)
            for ((dimension, valor) in dimensiones.medidas) {
                assertTrue(valor in 1f..7f, "$dimension se fue a $valor")
            }
        }
    }

    @Test
    fun `valor devuelve lo mismo que el campo de cada dimension`() {
        val dimensiones = DimensionesDeNivel.de(
            sesion(
                golpes = golpesDe(ShotType.FOREHAND, 10) + golpesDe(ShotType.SMASH, 10),
                minutos = 60,
                health = zonas(60, "z3" to 60 * 60),
            )
        )

        assertEquals(dimensiones.ataque, dimensiones.valor(DimensionDeNivel.ATAQUE))
        assertEquals(dimensiones.juegoDeFondo, dimensiones.valor(DimensionDeNivel.JUEGO_DE_FONDO))
        assertEquals(dimensiones.consistencia, dimensiones.valor(DimensionDeNivel.CONSISTENCIA))
        assertEquals(
            dimensiones.rendimientoFisico,
            dimensiones.valor(DimensionDeNivel.RENDIMIENTO_FISICO),
        )
        assertEquals(dimensiones.defensa, dimensiones.valor(DimensionDeNivel.DEFENSA))
        assertEquals(dimensiones.juegoDeRed, dimensiones.valor(DimensionDeNivel.JUEGO_DE_RED))
    }
}
