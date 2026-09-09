package cc.lxii.player.ui.nowplaying

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.QueueMusic
import androidx.compose.material.icons.outlined.Repeat
import androidx.compose.material.icons.outlined.RepeatOne
import androidx.compose.material.icons.outlined.Shuffle
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cc.lxii.player.core.player.policy.RepeatMode
import cc.lxii.player.core.lyrics.LyricLine
import cc.lxii.player.data.model.Track
import cc.lxii.player.ui.component.CoverArt
import cc.lxii.player.ui.component.formatDuration
import cc.lxii.player.ui.theme.LxColors
import cc.lxii.player.ui.theme.LxRadius
import cc.lxii.player.ui.theme.rememberCoverAccent

/**
 * 播放页。
 *
 * 台面固定纯黑（不随主题变化），背景是封面主色的径向渐变。
 * 进度条无滑块、右侧显示剩余时间——参考实现的 Apple Music 语汇。
 */
@Composable
fun NowPlayingScreen(
    track: Track?,
    playing: Boolean,
    positionMs: Long,
    durationMs: Long,
    repeatMode: RepeatMode,
    shuffleEnabled: Boolean,
    liked: Boolean,
    lyrics: List<LyricLine>,
    onTogglePlay: () -> Unit,
    onNext: () -> Unit,
    onPrevious: () -> Unit,
    onSeek: (Long) -> Unit,
    onCycleRepeat: () -> Unit,
    onToggleShuffle: () -> Unit,
    onToggleLike: () -> Unit,
    onOpenQueue: () -> Unit,
    onCollapse: () -> Unit,
    modifier: Modifier = Modifier,
) {
    if (track == null) return

    var scrubbing by remember { mutableStateOf(false) }
    var scrubValue by remember { mutableFloatStateOf(0f) }
    // 方形封面与黑胶唱盘之间切换，点封面即切。
    var vinylMode by remember { mutableStateOf(false) }
    // 左右滑动在封面页与歌词页之间切换。
    val stagePagerState = rememberPagerState(pageCount = { 2 })

    // 背景色来自当前封面，换歌时 800ms 交叉淡入。
    val accent by rememberCoverAccent(track.coverUri)

    val progress = if (durationMs > 0) {
        (positionMs.toFloat() / durationMs.toFloat()).coerceIn(0f, 1f)
    } else {
        0f
    }
    val sliderValue = if (scrubbing) scrubValue else progress
    val remainingMs = (durationMs - positionMs).coerceAtLeast(0L)

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(LxColors.stage)
            // 上方一团封面色的径向光，而不是整屏线性渐变——
            // 参考实现的观感来自「顶部一盏灯」，线性渐变会把整个台面染均匀。
            .background(
                Brush.radialGradient(
                    colors = listOf(
                        accent.copy(alpha = 0.55f),
                        accent.copy(alpha = 0.18f),
                        Color.Transparent,
                    ),
                    center = Offset(0.5f, 0f),
                    radius = 1600f,
                ),
            )
            .background(
                Brush.verticalGradient(
                    0f to Color.Transparent,
                    0.75f to accent.copy(alpha = 0.10f),
                    1f to accent.copy(alpha = 0.22f),
                ),
            ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(horizontal = 24.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = onCollapse) {
                    Icon(
                        Icons.Outlined.ExpandMore,
                        contentDescription = "收起",
                        tint = Color.White,
                    )
                }
                Spacer(Modifier.weight(1f))
                IconButton(onClick = onOpenQueue) {
                    Icon(
                        Icons.Outlined.QueueMusic,
                        contentDescription = "播放队列",
                        tint = Color.White,
                    )
                }
            }

            Spacer(Modifier.weight(0.35f))

            HorizontalPager(
                state = stagePagerState,
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
            ) { page ->
                if (page == 0) {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                                onClick = { vinylMode = !vinylMode },
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (vinylMode) {
                            VinylStage(coverUri = track.coverUri, playing = playing)
                        } else {
                            CoverArt(
                                uri = track.coverUri,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .aspectRatio(1f)
                                    .shadow(
                                        elevation = 28.dp,
                                        shape = RoundedCornerShape(LxRadius.stageCover),
                                        ambientColor = Color.Black,
                                        spotColor = Color.Black,
                                    ),
                                radius = LxRadius.stageCover,
                            )
                        }
                    }
                } else {
                    LyricsPane(
                        lines = lyrics,
                        positionMs = positionMs,
                        onSeekTo = onSeek,
                    )
                }
            }

            Spacer(Modifier.height(32.dp))

            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = track.title,
                        color = Color.White,
                        fontSize = 26.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        text = track.artist,
                        color = Color.White.copy(alpha = 0.5f),
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Medium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                IconButton(onClick = onToggleLike) {
                    Icon(
                        imageVector = if (liked) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder,
                        contentDescription = if (liked) "取消喜欢" else "喜欢",
                        tint = if (liked) LxColors.liked else Color.White.copy(alpha = 0.7f),
                    )
                }
            }

            Spacer(Modifier.height(20.dp))

            Slider(
                value = sliderValue,
                onValueChange = {
                    scrubbing = true
                    scrubValue = it
                },
                onValueChangeFinished = {
                    if (durationMs > 0) onSeek((scrubValue * durationMs).toLong())
                    scrubbing = false
                },
                colors = SliderDefaults.colors(
                    activeTrackColor = Color.White.copy(alpha = 0.8f),
                    inactiveTrackColor = Color.White.copy(alpha = 0.2f),
                    thumbColor = Color.Transparent,
                ),
            )
            Row(modifier = Modifier.fillMaxWidth()) {
                Text(
                    text = formatDuration(positionMs),
                    color = Color.White.copy(alpha = 0.6f),
                    fontSize = 11.sp,
                )
                Spacer(Modifier.weight(1f))
                Text(
                    text = "-${formatDuration(remainingMs)}",
                    color = Color.White.copy(alpha = 0.6f),
                    fontSize = 11.sp,
                    textAlign = TextAlign.End,
                )
            }

            Spacer(Modifier.height(24.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceEvenly,
            ) {
                IconButton(onClick = onToggleShuffle, modifier = Modifier.size(48.dp)) {
                    Icon(
                        Icons.Outlined.Shuffle,
                        contentDescription = "随机播放",
                        tint = if (shuffleEnabled) Color.White else Color.White.copy(alpha = 0.45f),
                    )
                }
                IconButton(onClick = onPrevious, modifier = Modifier.size(60.dp)) {
                    Icon(
                        Icons.Filled.SkipPrevious,
                        contentDescription = "上一首",
                        tint = Color.White,
                        modifier = Modifier.size(40.dp),
                    )
                }
                IconButton(onClick = onTogglePlay, modifier = Modifier.size(72.dp)) {
                    Icon(
                        if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                        contentDescription = if (playing) "暂停" else "播放",
                        tint = Color.White,
                        modifier = Modifier.size(56.dp),
                    )
                }
                IconButton(onClick = onNext, modifier = Modifier.size(60.dp)) {
                    Icon(
                        Icons.Filled.SkipNext,
                        contentDescription = "下一首",
                        tint = Color.White,
                        modifier = Modifier.size(40.dp),
                    )
                }
                IconButton(onClick = onCycleRepeat, modifier = Modifier.size(48.dp)) {
                    Icon(
                        imageVector = if (repeatMode == RepeatMode.ONE) Icons.Outlined.RepeatOne
                        else Icons.Outlined.Repeat,
                        contentDescription = "循环模式",
                        tint = if (repeatMode == RepeatMode.OFF) Color.White.copy(alpha = 0.45f)
                        else Color.White,
                    )
                }
            }

            Spacer(Modifier.weight(0.4f))
        }
    }
}
