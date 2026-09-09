package cc.lxii.player.ui.component

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * 三条竖条均衡器。
 *
 * 当前播放行用它代替「正在播放」文案：动的三条杠比静态图标更能说明「就是这一首」。
 */
@Composable
fun EqBars(
    playing: Boolean,
    color: Color,
    modifier: Modifier = Modifier,
    width: Dp = 14.dp,
    height: Dp = 14.dp,
) {
    val transition = rememberInfiniteTransition(label = "eq")
    val phase by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 900, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "eq-phase",
    )

    Canvas(modifier = modifier.size(width, height)) {
        val barWidth = size.width / 5f
        val gap = barWidth
        val phases = floatArrayOf(0f, 0.33f, 0.66f)
        val mins = floatArrayOf(0.35f, 0.2f, 0.4f)
        val maxs = floatArrayOf(0.95f, 1.0f, 0.8f)
        for (i in 0 until 3) {
            val t = if (playing) {
                val p = (phase + phases[i]) % 1f
                val triangle = if (p < 0.5f) p * 2f else (1f - p) * 2f
                mins[i] + (maxs[i] - mins[i]) * triangle
            } else {
                mins[i]
            }
            val barHeight = size.height * t
            val x = i * (barWidth + gap)
            drawRoundRect(
                color = color,
                topLeft = Offset(x, size.height - barHeight),
                size = Size(barWidth, barHeight),
                cornerRadius = CornerRadius(barWidth / 2f, barWidth / 2f),
            )
        }
    }
}
