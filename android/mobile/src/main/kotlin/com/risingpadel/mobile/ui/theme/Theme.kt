package com.risingpadel.mobile.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// La paleta de la marca, la misma que iOS y que el icono: azul de pista como color
// principal, lima de pelota como acento, y en oscuro el navy profundo del icono.
private val Pista = Color(0xFF1E56A8)
private val PistaClaro = Color(0xFF5B93E8)
private val Lima = Color(0xFF8FA50F)
private val LimaNeon = Color(0xFFCDE94F)

private val LightColors = lightColorScheme(
    primary = Pista,
    secondary = Lima,
    tertiary = LimaNeon,
    background = Color(0xFFF2F5F9),
    surface = Color(0xFFFFFFFF),
    onBackground = Color(0xFF0E2038),
    onSurface = Color(0xFF0E2038),
)

private val DarkColors = darkColorScheme(
    primary = PistaClaro,
    secondary = LimaNeon,
    tertiary = LimaNeon,
    background = Color(0xFF0A1626),
    surface = Color(0xFF13233C),
    surfaceVariant = Color(0xFF1A2C48),
    onBackground = Color(0xFFEAF0F7),
    onSurface = Color(0xFFEAF0F7),
)

@Composable
fun RisingPadelTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    // Nada de colores dinámicos del sistema: la app y su icono son una marca, y en
    // cada móvil se tiene que ver igual — como en iOS.
    val colorScheme = if (darkTheme) DarkColors else LightColors
    MaterialTheme(colorScheme = colorScheme, content = content)
}
