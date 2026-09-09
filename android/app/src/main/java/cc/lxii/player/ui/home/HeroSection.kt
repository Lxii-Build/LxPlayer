package cc.lxii.player.ui.home

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Radio
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import cc.lxii.player.data.model.Track
import cc.lxii.player.ui.component.CoverArt
import cc.lxii.player.ui.theme.LocalLxExtraColors
import cc.lxii.player.ui.theme.LxRadius
import java.util.Calendar

/**
 * 首页 Hero 区：每日推荐 + 私人 FM。
 *
 * 两张卡都不用边框，靠渐变与阴影分层——这是参考实现的做法：
 * 首页的视觉重量集中在这一区，用描边会把它压成普通列表项。
 */
@Composable
fun HeroSection(
    tracks: List<Track>,
    onPlayDaily: () -> Unit,
    onPlayShuffled: () -> Unit,
    modifier: Modifier = Modifier,
) {
    if (tracks.isEmpty()) return

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        DailyRecommendCard(tracks = tracks, onPlay = onPlayDaily)
        PersonalRadioCard(track = tracks.first(), count = tracks.size, onPlay = onPlayShuffled)
    }
}

@Composable
private fun DailyRecommendCard(tracks: List<Track>, onPlay: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(160.dp)
            .clip(RoundedCornerShape(LxRadius.hero))
            .background(
                Brush.linearGradient(
                    listOf(
                        scheme.primary.copy(alpha = 0.16f),
                        scheme.background,
                        scheme.surfaceVariant.copy(alpha = 0.55f),
                    ),
                ),
            )
            .clickable(onClick = onPlay),
    ) {
        // 右侧倾斜封面拼贴：一眼看出「这里面有一批歌」，
        // 比放一张大图更能表达「合集」。
        Row(
            modifier = Modifier
                .align(Alignment.CenterEnd)
                .padding(end = 8.dp)
                .rotate(5.7f)
                .alpha(0.40f),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            tracks.take(4).chunked(2).forEach { column ->
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    column.forEach { track ->
                        CoverArt(
                            uri = track.coverUri,
                            modifier = Modifier.size(64.dp),
                            radius = 12.dp,
                        )
                    }
                }
            }
        }
        // 左侧压一层背景色渐变，保证文字压在拼贴上依然清晰。
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.horizontalGradient(
                        0f to scheme.background.copy(alpha = 0.95f),
                        0.55f to scheme.background.copy(alpha = 0.35f),
                        1f to Color.Transparent,
                    ),
                ),
        )
        Column(
            modifier = Modifier
                .align(Alignment.CenterStart)
                .padding(start = 20.dp, end = 120.dp),
        ) {
            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(scheme.primary)
                    .padding(horizontal = 10.dp, vertical = 3.dp),
            ) {
                Text(
                    text = todayLabel(),
                    style = MaterialTheme.typography.labelSmall,
                    color = scheme.onPrimary,
                )
            }
            Spacer(Modifier.height(8.dp))
            Text(
                text = "每日推荐",
                style = MaterialTheme.typography.headlineLarge,
                color = scheme.onBackground,
            )
            Spacer(Modifier.height(2.dp))
            Text(
                text = "${tracks.size} 首本地音乐",
                style = MaterialTheme.typography.bodySmall,
                color = LocalLxExtraColors.current.muted,
            )
        }
        Box(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(start = 20.dp, bottom = 16.dp)
                .size(44.dp)
                .clip(CircleShape)
                .background(scheme.primary),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Filled.PlayArrow,
                contentDescription = "播放每日推荐",
                tint = scheme.onPrimary,
            )
        }
    }
}

@Composable
private fun PersonalRadioCard(track: Track, count: Int, onPlay: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    // 呼吸动画暗示这是「一直放下去」的电台，而不是一张固定歌单。
    val transition = rememberInfiniteTransition(label = "radio")
    val pulse by transition.animateFloat(
        initialValue = 0.55f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1400, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "radio-pulse",
    )

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(96.dp)
            .clip(RoundedCornerShape(LxRadius.hero))
            .background(scheme.surfaceVariant)
            .clickable(onClick = onPlay),
    ) {
        // 用封面自身作底再压一层半透明，得到「模糊玻璃后的封面」观感。
        CoverArt(
            uri = track.coverUri,
            modifier = Modifier
                .fillMaxSize()
                .alpha(0.35f),
            radius = LxRadius.hero,
        )
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(scheme.background.copy(alpha = 0.62f)),
        )
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CoverArt(
                uri = track.coverUri,
                modifier = Modifier.size(64.dp),
                radius = LxRadius.card,
            )
            Column(
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = 14.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Outlined.Radio,
                        contentDescription = null,
                        modifier = Modifier
                            .size(14.dp)
                            .alpha(pulse),
                        tint = scheme.primary,
                    )
                    Spacer(Modifier.size(6.dp))
                    Text(
                        text = "私人 FM",
                        style = MaterialTheme.typography.labelSmall,
                        color = scheme.primary,
                    )
                }
                Spacer(Modifier.height(4.dp))
                Text(
                    text = "随机播放全部",
                    style = MaterialTheme.typography.titleMedium,
                    color = scheme.onBackground,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = "共 $count 首",
                    style = MaterialTheme.typography.bodySmall,
                    color = LocalLxExtraColors.current.muted,
                )
            }
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(scheme.primary),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.PlayArrow,
                    contentDescription = "随机播放",
                    tint = scheme.onPrimary,
                )
            }
        }
    }
}

private fun todayLabel(): String {
    val calendar = Calendar.getInstance()
    val month = calendar.get(Calendar.MONTH) + 1
    val day = calendar.get(Calendar.DAY_OF_MONTH)
    return "$month 月 $day 日"
}
