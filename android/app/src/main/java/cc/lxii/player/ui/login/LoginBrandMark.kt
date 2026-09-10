package cc.lxii.player.ui.login

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.MusicNote
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

/**
 * 登录页品牌区。
 *
 * 140dp 发光渐变圆 + 内圈描边 + 中心音符 + 右下角锁徽章。
 * 入场：整体淡入上移 800ms，圆本身用弹性弹簧从 0.8 弹到 1.0。
 *
 * 这套手法来自参考项目未登录占位页，而不是它的登录页本身——
 * 后者和我们现在的一样是纵向堆控件，不值得抄。
 */
@Composable
fun LoginBrandMark(
    modifier: Modifier = Modifier,
    animate: Boolean = true,
) {
    val scheme = MaterialTheme.colorScheme
    val scale = remember { Animatable(if (animate) 0.8f else 1f) }
    val rise = remember { Animatable(if (animate) 1f else 0f) }

    LaunchedEffect(animate) {
        if (!animate) return@LaunchedEffect
        launch {
            scale.animateTo(
                1f,
                animationSpec = spring(
                    dampingRatio = Spring.DampingRatioMediumBouncy,
                    stiffness = Spring.StiffnessLow,
                ),
            )
        }
        launch {
            rise.animateTo(
                0f,
                animationSpec = tween(durationMillis = 800, easing = LinearOutSlowInEasing),
            )
        }
    }

    Box(
        modifier = modifier
            .testTag(LoginBrandMarkTags.ROOT)
            .alpha(1f - rise.value * 0.4f)
            .offset(y = (rise.value * 16).dp)
            .size(140.dp)
            .scale(scale.value),
        contentAlignment = Alignment.Center,
    ) {
        // 外圈：渐变底 + 主色外发光。发光色必须是 primary 而不是黑，
        // 否则在深色背景上看不见。
        Box(
            modifier = Modifier
                .testTag(LoginBrandMarkTags.GLOW)
                .size(140.dp)
                .shadow(
                    elevation = 30.dp,
                    shape = CircleShape,
                    ambientColor = scheme.primary.copy(alpha = 0.22f),
                    spotColor = scheme.primary.copy(alpha = 0.18f),
                )
                .background(
                    Brush.linearGradient(
                        colors = listOf(
                            scheme.primary.copy(alpha = 0.18f),
                            scheme.tertiary.copy(alpha = 0.10f),
                        ),
                    ),
                    CircleShape,
                ),
        )
        // 内圈：一圈淡描边，把发光圆收成「徽章」而不是一团雾。
        Box(
            modifier = Modifier
                .size(120.dp)
                .border(
                    width = 2.dp,
                    color = scheme.primary.copy(alpha = 0.30f),
                    shape = CircleShape,
                ),
        )
        Icon(
            imageVector = Icons.Outlined.MusicNote,
            contentDescription = null,
            modifier = Modifier.size(60.dp),
            tint = scheme.primary,
        )
        // 右下角锁徽章：提示「这里是账号」而不是播放页。
        Box(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .offset(x = (-18).dp, y = (-18).dp)
                .size(36.dp)
                .shadow(8.dp, CircleShape)
                .background(scheme.surfaceVariant, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Outlined.Lock,
                contentDescription = null,
                modifier = Modifier.size(18.dp),
                tint = scheme.primary,
            )
        }
    }
}

object LoginBrandMarkTags {
    const val ROOT = "login-brand"
    const val GLOW = "login-brand-glow"
}
