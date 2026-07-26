package com.risingpadel.core.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI

data class HttpResponse(
    val code: Int,
    val body: String,
    val headers: Map<String, List<String>> = emptyMap(),
) {
    fun header(name: String): String? =
        headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value?.firstOrNull()
}

/** Se lanza ante fallos de red. Los códigos HTTP no son excepciones: son [HttpResponse]. */
class HttpTransportException(message: String, cause: Throwable? = null) : IOException(message, cause)

/**
 * Abstracción mínima de HTTP. Existe para poder testear el cliente de la liga y la cola
 * de sincronización sin red ni servidor.
 */
interface HttpTransport {
    suspend fun request(
        method: String,
        url: String,
        headers: Map<String, String>,
        body: String?,
    ): HttpResponse
}

/**
 * Implementación sobre `HttpURLConnection`. Sin dependencias externas: funciona igual en
 * el JVM de los tests y en Android sin arrastrar OkHttp al reloj.
 */
class JdkHttpTransport(
    private val connectTimeoutMs: Int = 15_000,
    private val readTimeoutMs: Int = 30_000,
) : HttpTransport {

    override suspend fun request(
        method: String,
        url: String,
        headers: Map<String, String>,
        body: String?,
    ): HttpResponse = withContext(Dispatchers.IO) {
        val connection = try {
            (URI(url).toURL().openConnection() as HttpURLConnection)
        } catch (e: Exception) {
            throw HttpTransportException("No se pudo abrir la conexión a $url", e)
        }
        try {
            connection.requestMethod = method
            connection.connectTimeout = connectTimeoutMs
            connection.readTimeout = readTimeoutMs
            headers.forEach { (key, value) -> connection.setRequestProperty(key, value) }

            if (body != null) {
                connection.doOutput = true
                connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            }

            val code = connection.responseCode
            val stream = if (code in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
            HttpResponse(code = code, body = text, headers = connection.headerFields.orEmpty())
        } catch (e: HttpTransportException) {
            throw e
        } catch (e: Exception) {
            throw HttpTransportException("Fallo de red en $method $url: ${e.message}", e)
        } finally {
            connection.disconnect()
        }
    }
}
