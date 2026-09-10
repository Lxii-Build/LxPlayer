package cc.lxii.player.ui.component

import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * 液态玻璃表面。
 *
 * 真正的背景模糊（采样身后内容）在 Compose 里需要 `Modifier.graphicsLayer` +
 * `RenderEffect`，且只有 Android 12+ 支持；低版本用更高的不透明度近似，
 * 否则会看到「半透明但不模糊」的脏面板。
 *
 * 顶部加一道白色高光渐变和一圈发丝描边——这两笔是玻璃质感的来源，
 * 只有半透明底色会显得像塑料。
 */
@Composable
fun Modifier.glassSurface(
    shape: Shape,
    elevation: Dp = 16.dp,
    tintAlpha: Float = 0.72f,
): Modifier {
    val scheme = MaterialTheme.colorScheme
    // Android 12 以下拿不到背景模糊，靠加深底色维持可读性。
    val effectiveAlpha = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        tintAlpha
    } else {
        (tintAlpha + 0.20f).coerceAtMost(0.96f)
    }
    return this
        .shadow(
            elevation = elevation,
            shape = shape,
            ambientColor = scheme.onBackground.copy(alpha = 0.20f),
            spotColor = scheme.onBackground.copy(alpha = 0.24f),
        )
        .clip(shape)
        .background(scheme.surface.copy(alpha = effectiveAlpha))
        .border(
            width = 1.dp,
            color = Color.White.copy(alpha = 0.18f),
            shape = shape,
        )
}
