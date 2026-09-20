package com.risingpadel.core.liga

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AnalisisDeParejaTest {

    private var siguiente = 0L

    private fun partido(
        companero: String = "",
        resultado: String = "victoria",
        nivel: Double? = 4.0,
        posicion: String = "reves",
        volumen: List<Pair<String, Int>>? = null,
    ): LigaMatch {
        siguiente += 1
        return LigaMatch(
            id = siguiente,
            fecha = "2026-09-%02d".format((siguiente % 28) + 1),
            resultado = resultado,
            posicion = posicion,
            companero = companero,
            nivelBand = nivel,
            golpesVolumen = volumen?.map { LigaGolpeVolumen(it.first, it.second) },
        )
    }

    private fun partidos(cuantos: Int, bloque: () -> LigaMatch) = List(cuantos) { bloque() }

    // MARK: Rendimiento conjunto

    @Test
    fun `el rendimiento conjunto cuenta los partidos con esa pareja y solo esos`() {
        val liga = partidos(5) { partido(companero = "Marta") } +
            partidos(5) { partido(companero = "Luis", resultado = "derrota") }
        val analisis = AnalisisDeParejas.de("Marta", liga)

        assertEquals(5, analisis.juntos.partidos)
        assertEquals(5, analisis.juntos.victorias)
        assertEquals(100, analisis.juntos.pctVictorias)
        assertEquals(4.0, assertNotNull(analisis.juntos.nivelMedio), 0.001)
        assertTrue(analisis.suficiente)
    }

    @Test
    fun `por debajo del minimo hay recuento pero no porcentaje ni nivel medio`() {
        // Previene el "100 % de victorias" sobre dos partidos. El recuento sí se da: es
        // un hecho, y "lleváis 2 juntos" es justo lo que hay que poder decir.
        val analisis = AnalisisDeParejas.de("Marta", partidos(2) { partido(companero = "Marta") })

        assertEquals(2, analisis.juntos.partidos)
        assertEquals(2, analisis.juntos.victorias)
        assertNull(analisis.juntos.pctVictorias)
        assertNull(analisis.juntos.nivelMedio)
        assertTrue(!analisis.suficiente)
        assertEquals(3, analisis.partidosQueFaltan)
    }

    @Test
    fun `un entreno sin resultado no cuenta como derrota`() {
        // Antes se guardaba como derrota: un entreno bajaba el porcentaje de victorias
        // con esa pareja sin que nadie hubiera perdido nada.
        val liga = partidos(5) { partido(companero = "Marta") } +
            partido(companero = "Marta", resultado = "sin resultado")
        val juntos = AnalisisDeParejas.de("Marta", liga).juntos

        assertEquals(6, juntos.partidos)
        assertEquals(5, juntos.conResultado)
        assertEquals(100, juntos.pctVictorias)
    }

    @Test
    fun `un partido sin nivel medido no entra en la media como un cero`() {
        // Un partido apuntado a mano (sin reloj) no significa que ese día jugaras a
        // nivel cero: significa que no hay dato.
        val liga = partidos(5) { partido(companero = "Marta", nivel = 4.0) } +
            partido(companero = "Marta", nivel = null)
        val juntos = AnalisisDeParejas.de("Marta", liga).juntos

        assertEquals(6, juntos.partidos)
        assertEquals(5, juntos.conNivel)
        assertEquals(4.0, assertNotNull(juntos.nivelMedio), 0.001)
    }

    @Test
    fun `el minimo del nivel se mide sobre los partidos que lo traen, no sobre el total`() {
        // Cinco partidos juntos de los que dos midieron nivel son una media de dos
        // partidos. El recuento de arriba dice cinco y aun así no hay muestra.
        val liga = partidos(2) { partido(companero = "Marta", nivel = 4.0) } +
            partidos(3) { partido(companero = "Marta", nivel = null) }
        val juntos = AnalisisDeParejas.de("Marta", liga).juntos

        assertEquals(5, juntos.partidos)
        assertEquals(2, juntos.conNivel)
        assertNull(juntos.nivelMedio)
    }

    @Test
    fun `el rendimiento del companero no se inventa`() {
        // El ejemplo del documento pone una nota para los dos jugadores; la app solo
        // tiene el reloj de su dueño. Deducirla del resultado sería un número inventado
        // con aspecto de dato. El hueco existe y está vacío hasta que haya dos cuentas.
        val analisis = AnalisisDeParejas.de("Marta", partidos(10) { partido(companero = "Marta") })
        assertNull(analisis.juntos.nivelMedioDelCompanero)
    }

    // MARK: Con esa pareja contra con cualquier otra

    @Test
    fun `la comparacion exige el minimo a los dos lados`() {
        // Comparar contra tres partidos con otros es comparar contra nada.
        val pocos = partidos(5) { partido(companero = "Marta") } +
            partidos(3) { partido(companero = "Luis") }
        assertNull(AnalisisDeParejas.de("Marta", pocos).comparacion)

        val suficientes = pocos + partidos(2) { partido(companero = "Luis") }
        assertNotNull(AnalisisDeParejas.de("Marta", suficientes).comparacion)
    }

    @Test
    fun `un partido sin companero apuntado no entra en la base de comparacion`() {
        // No es un partido "con otra persona": es un partido del que no se sabe con quién
        // fue, y bien pudo ser con ella. Meterlo en la base decidiría por el jugador.
        val liga = partidos(5) { partido(companero = "Marta") } +
            partidos(5) { partido(companero = "") }
        assertNull(AnalisisDeParejas.de("Marta", liga).comparacion)

        val conOtros = liga + partidos(5) { partido(companero = "Luis") }
        val comparacion = assertNotNull(AnalisisDeParejas.de("Marta", conOtros).comparacion)
        assertEquals(5, comparacion.sin.partidos)
    }

    @Test
    fun `el veredicto lo decide el nivel, no el porcentaje de victorias`() {
        // Con Marta pierde siempre y juega a 4,5; con los demás gana siempre y juega a
        // 3,5. Ganar depende de quién estaba al otro lado de la red y la app no sabe el
        // nivel de los rivales; el nivel de sesión se mide en su muñeca.
        val liga = partidos(5) { partido(companero = "Marta", resultado = "derrota", nivel = 4.5) } +
            partidos(5) { partido(companero = "Luis", resultado = "victoria", nivel = 3.5) }
        val comparacion = assertNotNull(AnalisisDeParejas.de("Marta", liga).comparacion)

        assertEquals(VeredictoDePareja.MEJOR, comparacion.veredicto)
        assertEquals(1.0, assertNotNull(comparacion.deltaNivel), 0.001)
        assertEquals(-100, comparacion.deltaPctVictorias)
    }

    @Test
    fun `una diferencia menor de una decima es empate, no una mejora`() {
        // El nivel se guarda redondeado a una décima: un delta de 0,05 es ruido de
        // redondeo con pinta de hallazgo.
        val liga = partidos(5) { partido(companero = "Marta", nivel = 4.0) } +
            partidos(5) { partido(companero = "Luis", nivel = 3.95) }
        val comparacion = assertNotNull(AnalisisDeParejas.de("Marta", liga).comparacion)
        assertEquals(VeredictoDePareja.IGUAL, comparacion.veredicto)
    }

    @Test
    fun `sin nivel a alguno de los dos lados no hay veredicto, y no es un empate`() {
        // "No juegas mejor ni peor" y "no lo sé" no se pueden enseñar igual.
        val liga = partidos(5) { partido(companero = "Marta", nivel = 4.0) } +
            partidos(5) { partido(companero = "Luis", nivel = null) }
        val comparacion = assertNotNull(AnalisisDeParejas.de("Marta", liga).comparacion)

        assertNull(comparacion.veredicto)
        assertNull(comparacion.deltaNivel)
    }

    // MARK: Reparto de golpes

    @Test
    fun `el reparto compara cuota y no volumen bruto`() {
        // Con Marta los partidos son el doble de largos: da el doble de todo. Si se
        // comparara volumen, cada golpe saldría como "+100 % con Marta" cuando lo único
        // que cambió fue la duración. La cuota se normaliza sola.
        val liga = partidos(5) {
            partido(companero = "Marta", volumen = listOf("Derecha" to 100, "Bandeja" to 50))
        } + partidos(5) {
            partido(companero = "Luis", volumen = listOf("Derecha" to 50, "Bandeja" to 25))
        }
        val reparto = AnalisisDeParejas.de("Marta", liga).reparto
        val derecha = assertNotNull(reparto.firstOrNull { it.golpe == "Derecha" })

        assertEquals(100.0, derecha.porPartidoCon, 0.001)
        assertEquals(2.0 / 3, derecha.cuotaCon, 0.001)
        assertEquals(0.0, assertNotNull(derecha.diferencia), 0.001)
    }

    @Test
    fun `el golpe que mas destaca con esa pareja sale primero`() {
        // Es lo que el jugador viene a leer: con ella asume la defensa (más globos) y
        // con los demás ataca (más remates).
        val liga = partidos(5) {
            partido(companero = "Marta", volumen = listOf("Globo de derecha" to 60, "Remate" to 40))
        } + partidos(5) {
            partido(companero = "Luis", volumen = listOf("Globo de derecha" to 20, "Remate" to 80))
        }
        val reparto = AnalisisDeParejas.de("Marta", liga).reparto

        assertEquals("Globo de derecha", reparto.first().golpe)
        assertEquals(40, reparto.first().diferenciaEnPuntos)
        assertEquals("Remate", reparto.last().golpe)
        assertEquals(-40, reparto.last().diferenciaEnPuntos)
    }

    @Test
    fun `un partido sin golpes medidos no entra, pero un golpe ausente de uno medido si es cero`() {
        // Las dos mitades de la regla. Un partido apuntado a mano no es un partido de
        // cero golpes: no se midió. Dentro de uno que sí trae volumen, en cambio, un
        // golpe que no aparece es un cero de verdad — el reloj estuvo puesto y no vio
        // ninguno, así que promediarlo sobre los cinco partidos es correcto.
        val conMarta = listOf(
            partido(companero = "Marta", volumen = listOf("Derecha" to 10, "Bandeja" to 5)),
        ) + partidos(4) { partido(companero = "Marta", volumen = listOf("Derecha" to 10)) } +
            partidos(3) { partido(companero = "Marta", volumen = null) }
        val reparto = AnalisisDeParejas.de("Marta", conMarta).reparto

        // 50 derechas en 5 partidos medidos, no en los 8 jugados.
        assertEquals(10.0, assertNotNull(reparto.firstOrNull { it.golpe == "Derecha" }).porPartidoCon, 0.001)
        // 5 bandejas repartidas entre los 5 medidos: 1 por partido, no 5.
        assertEquals(1.0, assertNotNull(reparto.firstOrNull { it.golpe == "Bandeja" }).porPartidoCon, 0.001)
    }

    @Test
    fun `sin partidos medidos suficientes el reparto se calla`() {
        val liga = partidos(4) {
            partido(companero = "Marta", volumen = listOf("Derecha" to 10))
        } + partidos(4) { partido(companero = "Marta", volumen = null) }
        assertEquals(emptyList(), AnalisisDeParejas.de("Marta", liga).reparto)
    }

    @Test
    fun `sin base con otros companeros el reparto no inventa la comparacion`() {
        // La cuota con esa pareja sí se puede dar; la diferencia contra el resto no.
        // Un null aquí y un cero significan cosas opuestas.
        val liga = partidos(5) {
            partido(companero = "Marta", volumen = listOf("Derecha" to 10))
        }
        val reparto = AnalisisDeParejas.de("Marta", liga).reparto

        assertEquals(1, reparto.size)
        assertEquals(1.0, reparto.first().cuotaCon, 0.001)
        assertNull(reparto.first().cuotaSin)
        assertNull(reparto.first().diferencia)
    }

    @Test
    fun `el reparto cruza los golpes aunque cambie la grafia`() {
        // Los partidos importados de la app Expo traen los nombres como los escribió
        // quien los metió a mano. Si no se cruzaran, "bandeja" con los demás contaría
        // como cero y saldría un "+100 % de bandejas con Marta" que no ha pasado.
        val liga = partidos(5) {
            partido(companero = "Marta", volumen = listOf("Bandeja" to 10))
        } + partidos(5) { partido(companero = "Luis", volumen = listOf("bandeja" to 10)) }
        val reparto = AnalisisDeParejas.de("Marta", liga).reparto

        assertEquals("Bandeja", reparto.first().golpe)
        assertEquals(0.0, assertNotNull(reparto.first().diferencia), 0.001)
    }

    // MARK: Equilibrio por posición

    @Test
    fun `el lado habitual solo se afirma con cuatro de cada cinco partidos del mismo lado`() {
        val fijo = partidos(4) { partido(companero = "Marta", posicion = "derecha") } +
            partido(companero = "Marta", posicion = "reves")
        assertEquals("derecha", AnalisisDeParejas.de("Marta", fijo).posicion.ladoHabitual)

        // Con un 60/40 el sitio os lo vais repartiendo: decir "juegas de derecha" sería
        // redondear una costumbre que no existe.
        val repartido = partidos(3) { partido(companero = "Marta", posicion = "derecha") } +
            partidos(2) { partido(companero = "Marta", posicion = "reves") }
        val equilibrio = AnalisisDeParejas.de("Marta", repartido).posicion
        assertNull(equilibrio.ladoHabitual)
        assertEquals(0.6, assertNotNull(equilibrio.cuotaDerecha), 0.001)
    }

    @Test
    fun `el equilibrio por posicion calla la cuota por debajo del minimo`() {
        val liga = partidos(4) { partido(companero = "Marta", posicion = "derecha") }
        val equilibrio = AnalisisDeParejas.de("Marta", liga).posicion

        assertEquals(4, equilibrio.enDerecha)
        assertEquals(4, equilibrio.partidos)
        assertNull(equilibrio.cuotaDerecha)
        assertNull(equilibrio.ladoHabitual)
    }

    // MARK: Mejor y peor compañero

    @Test
    fun `el mejor companero se elige por nivel medio y exige el minimo`() {
        // Quien te saca el mejor juego, no con quien más ganas. Y el compañero
        // deslumbrante de tres partidos no compite: tres partidos no son una muestra.
        val liga = partidos(5) { partido(companero = "Marta", nivel = 4.5, resultado = "derrota") } +
            partidos(5) { partido(companero = "Luis", nivel = 3.5, resultado = "victoria") } +
            partidos(3) { partido(companero = "Ana", nivel = 7.0) }

        assertEquals("Marta", assertNotNull(AnalisisDeParejas.mejorCompanero(liga)).nombre)
        assertEquals("Luis", assertNotNull(AnalisisDeParejas.peorCompanero(liga)).nombre)
        assertEquals(listOf("Marta", "Luis"), AnalisisDeParejas.ranking(liga).map { it.nombre })
    }

    @Test
    fun `con un solo companero con muestra no hay peor companero`() {
        // El único que tienes no es "el peor" de nada, y enseñarlo a la vez como mejor y
        // como peor suena a reproche hacia una persona real.
        val liga = partidos(5) { partido(companero = "Marta") } +
            partidos(3) { partido(companero = "Luis") }

        assertEquals("Marta", assertNotNull(AnalisisDeParejas.mejorCompanero(liga)).nombre)
        assertNull(AnalisisDeParejas.peorCompanero(liga))
    }

    @Test
    fun `sin nivel medido no hay ranking, y no se cae al porcentaje de victorias`() {
        // Caer al porcentaje cambiaría calladamente lo que significa "mejor compañero".
        val liga = partidos(5) { partido(companero = "Marta", nivel = null) } +
            partidos(5) { partido(companero = "Luis", nivel = null, resultado = "derrota") }
        assertEquals(emptyList(), AnalisisDeParejas.ranking(liga))
        assertNull(AnalisisDeParejas.mejorCompanero(liga))
    }

    // MARK: Nombres

    @Test
    fun `el companero se reconoce sin mayusculas y dentro de un texto libre`() {
        // `companero` es un campo de texto: hay quien apunta "Marta y Juan" cuando juega
        // con dos parejas distintas a lo largo del día.
        val liga = partidos(3) { partido(companero = "marta") } +
            partidos(2) { partido(companero = "Marta y Juan") }
        val analisis = AnalisisDeParejas.de("MARTA", liga)

        assertEquals(5, analisis.juntos.partidos)
        assertEquals("MARTA", analisis.companero)
    }

    @Test
    fun `el selector enseña a todos los companeros, tambien a los que no llegan al minimo`() {
        // Esconderlos haría imposible ver cuántos partidos os faltan para analizarlo.
        val liga = partidos(5) { partido(companero = "Marta") } +
            partidos(2) { partido(companero = "Luis") }
        assertEquals(listOf("Marta", "Luis"), AnalisisDeParejas.companeros(liga))
    }
}
