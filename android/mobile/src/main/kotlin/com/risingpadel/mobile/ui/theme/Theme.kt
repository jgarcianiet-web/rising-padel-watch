package com.risingpadel.mobile.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

private val PadelGreen = Color(0xFF1B7F5A)
private val PadelGreenLight = Color(0xFF7BE3A6)
private val PadelSand = Color(0xFFE8C57A)

private val LightColors = lightColorScheme(
    primary = PadelGreen,
    secondary = Color(0xFF4F6354),
    tertiary = PadelSand,
)

private val DarkColors = darkColorScheme(
    primary = PadelGreenLight,
    secondary = Color(0xFFB6CCBB),
    tertiary = PadelSand,
)

@Composable
fun RisingPadelTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val colorScheme = when {
        // En Android 12+ se respeta el color del sistema; la paleta propia es el respaldo.
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }

        darkTheme -> DarkColors
        else -> LightColors
    }
    MaterialTheme(colorScheme = colorScheme, content = content)
}
