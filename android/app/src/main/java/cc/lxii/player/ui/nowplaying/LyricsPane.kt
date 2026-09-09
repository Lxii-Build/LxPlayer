package cc.lxii.player.ui.nowplaying

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cc.lxii.player.core.lyrics.LyricLine
import cc.lxii.player.core.lyrics.LrcParser

/**
 * 播放页歌词区。
 *
 * 当前行纯白加粗、其余 white/30——靠明度差建立焦点，而不是给非当前行上色，
 * 那样会和封面取色背景打架。
 *
 * 自动滚动让当前行停在容器中部：滚到顶部会让人不断往下找，
 * 停在中间才有「跟着唱」的感觉。用户手动滑动时不抢滚动位置。
 */
@Composable
fun LyricsPane(
    lines: List<LyricLine>,
    positionMs: Long,
    onSeekTo: (Long) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (lines.isEmpty()) {
        Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            androidx.compose.material3.Text(
                text = "没有找到歌词",
                color = Color.White.copy(alpha = 0.35f),
                fontSize = 14.sp,
            )
        }
        return
    }

    val listState = rememberLazyListState()
    val activeIndex = remember(lines, positionMs) {
        LrcParser.activeIndex(lines, positionMs)
    }

    LaunchedEffect(activeIndex) {
        if (activeIndex < 0) return@LaunchedEffect
        // 只有不在拖动时才接管滚动，否则会把用户的手势顶回去。
        if (listState.isScrollInProgress) return@LaunchedEffect
        val viewport = listState.layoutInfo.viewportSize.height
        val itemHeight = listState.layoutInfo.visibleItemsInfo
            .firstOrNull()?.size ?: 0
        val centerOffset = if (viewport > 0) -(viewport / 2 - itemHeight / 2) else 0
        runCatching {
            listState.animateScrollToItem(activeIndex, centerOffset)
        }
    }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        state = listState,
        contentPadding = PaddingValues(vertical = 120.dp),
    ) {
        itemsIndexed(lines, key = { index, line -> "$index-${line.startTimeMs}" }) { index, line ->
            val active = index == activeIndex
            val alpha by animateFloatAsState(
                targetValue = if (active) 1f else 0.30f,
                animationSpec = tween(durationMillis = 260),
                label = "lyric-alpha",
            )
            androidx.compose.material3.Text(
                text = line.text,
                color = Color.White.copy(alpha = alpha),
                fontSize = if (active) 22.sp else 18.sp,
                fontWeight = if (active) FontWeight.Bold else FontWeight.Medium,
                lineHeight = if (active) 30.sp else 26.sp,
                textAlign = TextAlign.Start,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        // 点歌词跳到那一句：找歌里某一段最快的方式。
                        onClick = { onSeekTo(line.startTimeMs) },
                    )
                    .padding(vertical = 10.dp),
            )
        }
    }
}
