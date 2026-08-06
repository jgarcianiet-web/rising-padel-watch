package com.risingpadel.mobile.data

import com.risingpadel.core.model.PadelSession
import kotlinx.serialization.Serializable

/**
 * La copia de seguridad entera: el historial de sesiones y la liga, en un JSON.
 *
 * Vive en el servidor de la comunidad, un hueco por usuario, y hace que reinstalar la
 * app no borre nada (recuperando la cuenta con el código, porque en Android la
 * desinstalación sí borra el token). La copia es por plataforma: los enums de iOS y
 * Android no serializan igual, así que al cambiar de sistema lo que se comparte es la
 * cuenta, no el historial local.
 */
@Serializable
data class CopiaSeguridad(
    val version: Int = 1,
    val creadaEpochMs: Long,
    val sesiones: List<PadelSession>,
    /** El estado de la liga tal cual, el mismo shape que exportar en la pestaña Liga. */
    val ligaJson: String? = null,
)
