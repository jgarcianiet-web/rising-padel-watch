package com.risingpadel.core.training

import com.risingpadel.core.model.Hand
import com.risingpadel.core.model.Platform
import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType
import java.io.File
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class TrainingSampleStoreTest {

    private val directory: File = Files.createTempDirectory("padel-training").toFile()
    private val file = File(directory, "muestras.jsonl")

    @AfterTest
    fun cleanup() {
        directory.deleteRecursively()
    }

    private fun sample(
        id: String = "s-1",
        label: ShotType = ShotType.FOREHAND,
        alias: String = "jugador-1",
    ) = TrainingSample(
        sampleId = id,
        label = label,
        recordedAtEpochMs = 1_785_002_652_000,
        playerAlias = alias,
        hand = Hand.RIGHT,
        watchWrist = Hand.RIGHT,
        platform = Platform.WEAROS,
        device = "Pixel Watch 3",
        sampleRateHz = 50,
        impactIndex = 2,
        offsetsMs = listOf(-40, -20, 0, 20, 40),
        accel = List(5) { listOf(0.1f, 0.2f, 0.3f) },
        gyro = List(5) { listOf(1f, 2f, 3f) },
        gravity = List(5) { listOf(0f, -1f, 0f) },
        heuristicFeatures = ShotFeatures(185f, 20f, 10f, 12f, 200),
        heuristicPrediction = ShotType.FOREHAND,
        heuristicConfidence = 0.9f,
    )

    @Test
    fun `guarda y recupera una muestra completa`() {
        val store = TrainingSampleStore(file)
        val original = sample()
        store.append(original)

        assertEquals(listOf(original), store.readAll())
    }

    @Test
    fun `cada muestra es una linea, para poder ir añadiendo`() {
        val store = TrainingSampleStore(file)
        store.append(sample("s-1"))
        store.append(sample("s-2"))
        store.append(sample("s-3"))

        assertEquals(3, file.readLines().count { it.isNotBlank() })
        assertEquals(3, store.count())
    }

    @Test
    fun `appendAll escribe una tanda entera de golpe`() {
        val store = TrainingSampleStore(file)
        store.appendAll(listOf(sample("s-1"), sample("s-2")))

        assertEquals(2, store.count())
    }

    @Test
    fun `appendAll con una lista vacia no crea el fichero`() {
        val store = TrainingSampleStore(file)
        store.appendAll(emptyList())

        assertFalse(store.exists)
    }

    @Test
    fun `una linea corrupta no se lleva por delante el resto del fichero`() {
        val store = TrainingSampleStore(file)
        store.append(sample("buena-1"))
        file.appendText("{ esto no es JSON válido\n")
        store.append(sample("buena-2"))

        // Es justo el caso de quedarse sin batería a mitad de escribir una línea.
        assertEquals(listOf("buena-1", "buena-2"), store.readAll().map { it.sampleId })
    }

    @Test
    fun `cuenta cuantas muestras hay de cada tipo`() {
        val store = TrainingSampleStore(file)
        store.append(sample("s-1", ShotType.FOREHAND))
        store.append(sample("s-2", ShotType.FOREHAND))
        store.append(sample("s-3", ShotType.BACKHAND))

        assertEquals(mapOf("forehand" to 2, "backhand" to 1), store.countsByLabel())
    }

    @Test
    fun `count no necesita parsear el fichero entero`() {
        val store = TrainingSampleStore(file)
        repeat(50) { store.append(sample("s-$it")) }

        // Es lo que se enseña en el reloj mientras se graba: tiene que ser barato.
        assertEquals(50, store.count())
    }

    @Test
    fun `clear borra todo`() {
        val store = TrainingSampleStore(file)
        store.append(sample())
        store.clear()

        assertFalse(store.exists)
        assertEquals(0, store.count())
        assertTrue(store.readAll().isEmpty())
    }

    @Test
    fun `un fichero que no existe se lee como vacio`() {
        val store = TrainingSampleStore(File(directory, "no-existe.jsonl"))

        assertEquals(0, store.count())
        assertTrue(store.readAll().isEmpty())
        assertEquals(0L, store.sizeBytes)
    }

    @Test
    fun `crea el directorio si hace falta`() {
        val anidado = File(directory, "a/b/c/muestras.jsonl")
        val store = TrainingSampleStore(anidado)
        store.append(sample())

        assertTrue(anidado.exists())
    }

    @Test
    fun `el tamaño del fichero permite avisar antes de llenar el reloj`() {
        val store = TrainingSampleStore(file)
        repeat(10) { store.append(sample("s-$it")) }

        assertTrue(store.sizeBytes > 0)
    }
}
