package cc.lxii.player.ui.component

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import cc.lxii.player.data.model.Track
import cc.lxii.player.ui.theme.LocalLxExtraColors
import cc.lxii.player.ui.theme.LxRadius

/**
 * 横向滚动用的封面卡。
 *
 * 参考实现的观感靠三件事叠出来：按下时封面放大、压一层半透明黑遮罩、
 * 遮罩上浮出白色圆形播放键。少任何一件都会显得平。
 * 桌面端那套是 hover 触发，触屏上只有按压态，所以绑到 pressed。
 */
@Composable
fun CoverCard(
    track: Track,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    width: Dp = 140.dp,
    rank: Int? = null,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val coverScale by animateFloatAsState(
        targetValue = if (pressed) 1.08f else 1f,
        animationSpec = tween(durationMillis = 400),
        label = "cover-scale",
    )
    val overlayAlpha by animateFloatAsState(
        targetValue = if (pressed) 1f else 0f,
        animationSpec = tween(durationMillis = 220),
        label = "cover-overlay",
    )

    Column(
        modifier = modifier
            .width(width)
            .clickable(
                interactionSource = interaction,
                indication = null,
                onClick = onClick,
            ),
    ) {
        Box(
            modifier = Modifier
                .size(width)
                .clip(androidx.compose.foundation.shape.RoundedCornerShape(LxRadius.cover)),
        ) {
            CoverArt(
                uri = track.coverUri,
                modifier = Modifier
                    .fillMaxSize()
                    .scale(coverScale),
                radius = LxRadius.cover,
            )
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .alpha(overlayAlpha)
                    .background(Color.Black.copy(alpha = 0.40f)),
                contentAlignment = Alignment.Center,
            ) {
                Box(
                    modifier = Modifier
                        .size(44.dp)
                        .clip(CircleShape)
                        .background(Color.White),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.Filled.PlayArrow,
                        contentDescription = "播放",
                        tint = Color.Black,
                    )
                }
            }
            if (rank != null) {
                Box(
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .padding(8.dp)
                        .clip(CircleShape)
                        // 前三名用主色强调，其余用半透明黑，让榜首一眼可见。
                        .background(
                            if (rank <= 3) MaterialTheme.colorScheme.primary.copy(alpha = 0.92f)
                            else Color.Black.copy(alpha = 0.60f),
                        )
                        .padding(horizontal = 8.dp, vertical = 2.dp),
                ) {
                    Text(
                        text = rank.toString(),
                        style = MaterialTheme.typography.labelSmall,
                        color = if (rank <= 3) MaterialTheme.colorScheme.onPrimary else Color.White,
                    )
                }
            }
        }
        Text(
            text = track.title,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onBackground,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 8.dp),
        )
        Text(
            text = track.artist,
            style = MaterialTheme.typography.bodySmall,
            color = LocalLxExtraColors.current.muted,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}
