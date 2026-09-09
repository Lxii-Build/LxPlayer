package cc.lxii.player.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/** Material 色板里没有对应槽位的语义色，用一个额外的 local 传递。 */
data class LxExtraColors(
    val muted: Color,
    val liked: Color,
    val stage: Color,
)

val LocalLxExtraColors = staticCompositionLocalOf {
    LxExtraColors(
        muted = LxColors.lightMuted,
        liked = LxColors.liked,
        stage = LxColors.stage,
    )
}

private val LightScheme = lightColorScheme(
    primary = LxColors.lightPrimary,
    onPrimary = LxColors.lightOnPrimary,
    background = LxColors.lightBackground,
    onBackground = LxColors.lightOnBackground,
    surface = LxColors.lightBackground,
    onSurface = LxColors.lightOnBackground,
    surfaceVariant = LxColors.lightSurfaceVariant,
    onSurfaceVariant = LxColors.lightMuted,
    secondaryContainer = LxColors.lightSurfaceVariant,
    outline = LxColors.lightOutline,
    error = LxColors.destructiveLight,
)

private val DarkScheme = darkColorScheme(
    primary = LxColors.darkPrimary,
    onPrimary = LxColors.darkOnPrimary,
    background = LxColors.darkBackground,
    onBackground = LxColors.darkOnBackground,
    surface = LxColors.darkBackground,
    onSurface = LxColors.darkOnBackground,
    surfaceVariant = LxColors.darkSurfaceVariant,
    onSurfaceVariant = LxColors.darkMuted,
    secondaryContainer = LxColors.darkSurfaceVariant,
    outline = LxColors.darkOutline,
    error = LxColors.destructiveDark,
)

@Composable
fun LxPlayerTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val scheme = if (darkTheme) DarkScheme else LightScheme
    val extras = LxExtraColors(
        muted = if (darkTheme) LxColors.darkMuted else LxColors.lightMuted,
        liked = LxColors.liked,
        stage = LxColors.stage,
    )
    CompositionLocalProvider(LocalLxExtraColors provides extras) {
        MaterialTheme(
            colorScheme = scheme,
            typography = LxTypography,
            shapes = LxShapes,
            content = content,
        )
    }
}
