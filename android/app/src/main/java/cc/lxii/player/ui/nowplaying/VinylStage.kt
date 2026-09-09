package cc.lxii.player.ui.nowplaying

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import cc.lxii.player.ui.component.CoverArt

/** 唱盘与唱臂的测试标记，供几何断言读取布局坐标。 */
object VinylStageTags {
    const val DISC = "vinyl-disc"
    const val TONEARM = "vinyl-tonearm"
}

/**
 * 黑胶唱盘。
 *
 * 唱片匀速旋转（18 秒一圈），唱臂在播放时落到 24°、暂停时抬回 4°。
 * 唱臂用角度动画而不是位移：真实唱臂是绕支点转的，用平移会看着很假。
 */
@Composable
fun VinylStage(
    coverUri: String?,
    playing: Boolean,
    modifier: Modifier = Modifier,
) {
    val transition = rememberInfiniteTransition(label = "vinyl")
    val spin by transition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 18_000, easing = LinearEasing),
        ),
        label = "vinyl-spin",
    )
    val armAngle by animateFloatAsState(
        targetValue = if (playing) 24f else 4f,
        animationSpec = tween(durationMillis = 520),
        label = "tonearm",
    )

    BoxWithConstraints(
        modifier = modifier
            .fillMaxWidth()
            .aspectRatio(1f),
        contentAlignment = Alignment.Center,
    ) {
        val side = minOf(maxWidth, maxHeight)

        Box(
            modifier = Modifier
                .size(side * 0.86f)
                .clip(CircleShape)
                .testTag(VinylStageTags.DISC),
            contentAlignment = Alignment.Center,
        ) {
            // 底盘与外圈都用 Canvas 画在圆内。
            // Modifier.border(shape = CircleShape) 会把描边渲染进方形布局盒，
            // 圆外四角可能残留可见像素，唱盘会变成「带角的圆」。
            Canvas(modifier = Modifier.fillMaxSize()) {
                drawCircle(
                    brush = Brush.radialGradient(
                        colors = listOf(Color(0xFF2A2A2A), Color(0xFF0E0E0E)),
                        center = Offset(size.width * 0.35f, size.height * 0.3f),
                        radius = size.minDimension * 0.75f,
                    ),
                )
                val stroke = size.minDimension * 0.03f
                drawCircle(
                    color = Color.White.copy(alpha = 0.15f),
                    radius = size.minDimension / 2f - stroke / 2f,
                    style = Stroke(width = stroke),
                )
            }
            CoverArt(
                uri = coverUri,
                modifier = Modifier
                    .size(side * 0.56f)
                    .rotate(spin)
                    .clip(CircleShape),
                radius = side * 0.28f,
            )
            // 中心轴：一个小亮点，暗示这是可旋转的唱盘而不是圆形封面。
            Canvas(modifier = Modifier.size(side * 0.06f)) {
                drawCircle(color = Color(0xFFE5E5E5))
            }
        }

        // 唱臂锚在右上角，绕自身左端旋转。
        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(top = side * 0.04f, end = side * 0.06f)
                .size(width = side * 0.42f, height = side * 0.42f)
                .testTag(VinylStageTags.TONEARM),
        ) {
            Canvas(
                modifier = Modifier
                    .fillMaxSize()
                    .rotate(armAngle),
            ) {
                val pivot = Offset(size.width * 0.92f, size.height * 0.08f)
                val head = Offset(size.width * 0.30f, size.height * 0.74f)
                drawLine(
                    color = Color.White.copy(alpha = 0.55f),
                    start = pivot,
                    end = head,
                    strokeWidth = size.minDimension * 0.035f,
                )
                drawCircle(
                    color = Color.White.copy(alpha = 0.75f),
                    radius = size.minDimension * 0.075f,
                    center = pivot,
                )
                drawCircle(
                    color = Color.White.copy(alpha = 0.85f),
                    radius = size.minDimension * 0.045f,
                    center = head,
                )
            }
        }
    }
}
