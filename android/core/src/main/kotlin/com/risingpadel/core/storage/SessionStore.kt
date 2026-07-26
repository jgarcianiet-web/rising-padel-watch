package com.risingpadel.core.storage

import com.risingpadel.core.model.PadelSession
import kotlinx.serialization.json.Json
import java.io.File

/** Persistencia local de sesiones. La liga es el destino final, no la fuente de verdad. */
interface SessionStore {
    fun all(): List<PadelSession>
    fun get(sessionId: String): PadelSession?
    fun upsert(session: PadelSession)
    fun delete(sessionId: String)
}

/**
 * Un fichero JSON por sesión.
 *
 * Un fichero por sesión y no una base de datos porque el acceso siempre es "todas" o
 * "una por id", el volumen es de decenas de sesiones al año, y así una sesión corrupta
 * no se lleva por delante el historial entero.
 *
 * Las escrituras son atómicas (fichero temporal + rename): si el móvil se apaga a mitad
 * de escritura, la sesión anterior sigue intacta.
 */
class FileSessionStore(
    private val directory: File,
    private val json: Json = defaultJson,
) : SessionStore {

    init {
        if (!directory.exists()) directory.mkdirs()
    }

    override fun all(): List<PadelSession> =
        directory.listFiles { file -> file.isFile && file.name.endsWith(EXTENSION) }
            .orEmpty()
            .mapNotNull { read(it) }
            .sortedByDescending { it.startedAtEpochMs }

    override fun get(sessionId: String): PadelSession? = read(fileFor(sessionId))

    override fun upsert(session: PadelSession) {
        val target = fileFor(session.sessionId)
        val temp = File(target.parentFile, "${target.name}.tmp")
        temp.writeText(json.encodeToString(PadelSession.serializer(), session))
        if (!temp.renameTo(target)) {
            // Algunos sistemas de ficheros no sobrescriben en rename.
            target.delete()
            check(temp.renameTo(target)) { "No se pudo guardar la sesión ${session.sessionId}" }
        }
    }

    override fun delete(sessionId: String) {
        fileFor(sessionId).delete()
    }

    private fun fileFor(sessionId: String) = File(directory, "${sanitize(sessionId)}$EXTENSION")

    private fun read(file: File): PadelSession? {
        if (!file.exists()) return null
        return runCatching { json.decodeFromString(PadelSession.serializer(), file.readText()) }
            .getOrNull()
    }

    /** El sessionId es un UUID generado por nosotros, pero nunca se construye una ruta con datos sin filtrar. */
    private fun sanitize(sessionId: String) = sessionId.replace(Regex("[^A-Za-z0-9_-]"), "_")

    companion object {
        private const val EXTENSION = ".session.json"

        val defaultJson = Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
        }
    }
}

/** Store en memoria para tests y para las previews de la UI. */
class InMemorySessionStore(initial: List<PadelSession> = emptyList()) : SessionStore {
    private val sessions = LinkedHashMap<String, PadelSession>()

    init {
        initial.forEach { sessions[it.sessionId] = it }
    }

    override fun all(): List<PadelSession> = sessions.values.sortedByDescending { it.startedAtEpochMs }

    override fun get(sessionId: String): PadelSession? = sessions[sessionId]

    override fun upsert(session: PadelSession) {
        sessions[session.sessionId] = session
    }

    override fun delete(sessionId: String) {
        sessions.remove(sessionId)
    }
}
