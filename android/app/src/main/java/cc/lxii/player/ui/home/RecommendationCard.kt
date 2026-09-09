package cc.lxii.player.ui.home

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import cc.lxii.player.data.model.Track
import cc.lxii.player.ui.theme.LocalLxExtraColors
import cc.lxii.player.ui.theme.LxRadius

/**
 * 首页推荐卡。
 *
 * 交互刻意不用 HorizontalPager：参考手感是「拖动时卡片不跟手，松手越过阈值后整卡换一张」，
 * Pager 给的是跟手滚动的另一种手感。阈值判定全部委托给 [SwipeGesturePolicy]（已有单测覆盖），
 * 这里只负责把手势事件换算成 dp 并驱动动画。
 */
@Composable
fun RecommendationCard(
    tracks: List<Track>,
    featuredIndex: Int,
    onIndexChange: (Int) -> Unit,
    onPlay: (Track) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (tracks.isEmpty()) return
    val featured = tracks.getOrNull(featuredIndex) ?: return

    val density = LocalDensity.current
    val enter = remember { Animatable(1f) }
    // 记录最近一次滑动方向，入场动画要从滑动来的那一侧进入。
    val lastDirection = remember { intArrayOf(0) }

    LaunchedEffect(featuredIndex) {
        enter.snapTo(0f)
        enter.animateTo(1f, animationSpec = tween(SwipeGesturePolicy.ENTER_DURATION_MS))
    }

    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(LxRadius.featuredCard),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Box(
            modifier = Modifier
                .padding(20.dp)
                .pointerInput(tracks.size, featuredIndex) {
                    awaitEachGesture {
                        awaitFirstDown(requireUnconsumed = false)
                        var dx = 0f
                        var dy = 0f
                        var committed = false
                        var abandoned = false

                        while (true) {
                            val event = awaitPointerEvent()
                            val change = event.changes.firstOrNull() ?: break
                            if (!change.pressed) break

                            dx += change.positionChange().x
                            dy += change.positionChange().y

                            if (committed || abandoned) continue

                            val dxDp = with(density) { dx.toDp().value }
                            val dyDp = with(density) { dy.toDp().value }
                            when (val decision = SwipeGesturePolicy.decide(dxDp, dyDp)) {
                                SwipeDecision.FAIL_TO_VERTICAL -> abandoned = true
                                SwipeDecision.COMMIT_NEXT, SwipeDecision.COMMIT_PREV -> {
                                    committed = true
                                    val direction = SwipeGesturePolicy.directionOf(decision)
                                    lastDirection[0] = direction
                                    onIndexChange(
                                        SwipeGesturePolicy.wrapIndex(
                                            featuredIndex,
                                            direction,
                                            tracks.size,
                                        ),
                                    )
                                }
                                // 已激活但未到提交阈值：消费事件防止外层滚动抢走手势，
                                // 但不移动卡片——参考实现拖动时卡片是静止的。
                                SwipeDecision.PENDING -> change.consume()
                                SwipeDecision.IGNORE -> Unit
                            }
                        }
                    }
                },
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .defaultMinSize(minHeight = FanStackHeight)
                    .graphicsLayer {
                        alpha = enter.value
                        translationX = with(density) {
                            (SwipeGesturePolicy.ENTER_OFFSET_DP * lastDirection[0] *
                                (1f - enter.value)).dp.toPx()
                        }
                    },
                verticalAlignment = Alignment.Bottom,
            ) {
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .padding(end = 16.dp),
                ) {
                    Text(
                        text = "为你推荐",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.primary,
                    )
                    Spacer(Modifier.height(12.dp))
                    Text(
                        text = featured.title,
                        style = MaterialTheme.typography.titleLarge,
                        color = MaterialTheme.colorScheme.onBackground,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        text = featured.artist,
                        style = MaterialTheme.typography.bodyLarge,
                        color = LocalLxExtraColors.current.muted,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Spacer(Modifier.height(20.dp))
                    Button(
                        onClick = { onPlay(featured) },
                        modifier = Modifier.height(48.dp),
                        shape = RoundedCornerShape(percent = 50),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.primary,
                            contentColor = MaterialTheme.colorScheme.onPrimary,
                        ),
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(
                            horizontal = 20.dp,
                        ),
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Icon(Icons.Filled.PlayArrow, contentDescription = null)
                            Text("播放", style = MaterialTheme.typography.titleSmall)
                        }
                    }
                }

                FanCoverStack(
                    tracks = tracks,
                    featuredIndex = featuredIndex,
                    modifier = Modifier.width(FanStackWidth),
                )
            }
        }
    }
}
