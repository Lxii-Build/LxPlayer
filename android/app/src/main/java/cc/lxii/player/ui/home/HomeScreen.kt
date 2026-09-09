package cc.lxii.player.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import cc.lxii.player.data.model.Track
import cc.lxii.player.ui.LibraryUiState
import cc.lxii.player.ui.component.CoverCard
import cc.lxii.player.ui.component.TrackRow
import cc.lxii.player.ui.theme.LocalLxExtraColors
import java.util.Calendar

@Composable
fun HomeScreen(
    state: LibraryUiState,
    featuredIndex: Int,
    currentTrackId: String?,
    isPlaying: Boolean,
    likedIds: Set<String>,
    onFeaturedIndexChange: (Int) -> Unit,
    onPlayTrack: (Track) -> Unit,
    onPlayDaily: () -> Unit,
    onPlayShuffled: () -> Unit,
    onToggleLike: (Track) -> Unit,
    onRefresh: () -> Unit,
    onRequestPermission: () -> Unit,
    contentPadding: PaddingValues,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.fillMaxWidth(),
        contentPadding = contentPadding,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        item {
            Column(
                modifier = Modifier
                    .statusBarsPadding()
                    .padding(horizontal = 20.dp)
                    .padding(top = 24.dp),
            ) {
                Text(
                    text = greeting(),
                    style = MaterialTheme.typography.headlineLarge,
                    color = MaterialTheme.colorScheme.onBackground,
                )
                Text(
                    text = "每日推荐",
                    style = MaterialTheme.typography.bodyLarge,
                    color = LocalLxExtraColors.current.muted,
                )
            }
        }

        when {
            !state.permissionGranted && !state.loading -> item {
                EmptyBlock(
                    title = "需要读取本地音乐的权限",
                    action = "授予权限",
                    onAction = onRequestPermission,
                )
            }

            state.loading -> item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(288.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    CircularProgressIndicator()
                }
            }

            state.error != null -> item {
                EmptyBlock(
                    title = state.error,
                    action = "重试",
                    onAction = onRefresh,
                )
            }

            state.tracks.isEmpty() -> item {
                EmptyBlock(
                    title = "这台设备上还没有本地音乐",
                    action = "重新扫描",
                    onAction = onRefresh,
                )
            }

            else -> {
                item {
                    RecommendationCard(
                        tracks = state.tracks,
                        featuredIndex = featuredIndex,
                        onIndexChange = onFeaturedIndexChange,
                        onPlay = onPlayTrack,
                        modifier = Modifier
                            .padding(horizontal = 20.dp)
                            .padding(top = 36.dp),
                    )
                }

                item {
                    HeroSection(
                        tracks = state.tracks,
                        onPlayDaily = onPlayDaily,
                        onPlayShuffled = onPlayShuffled,
                        modifier = Modifier
                            .padding(horizontal = 20.dp)
                            .padding(top = 24.dp),
                    )
                }

                item {
                    SectionHeader(title = "热门单曲")
                    LazyRow(
                        contentPadding = PaddingValues(horizontal = 20.dp),
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        itemsIndexed(
                            state.tracks.take(10),
                            key = { _, track -> track.globalId },
                        ) { index, track ->
                            CoverCard(
                                track = track,
                                rank = index + 1,
                                onClick = { onPlayTrack(track) },
                            )
                        }
                    }
                }

                item {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 20.dp)
                            .padding(top = 28.dp, bottom = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = "每日歌曲",
                            style = MaterialTheme.typography.headlineMedium,
                            color = MaterialTheme.colorScheme.onBackground,
                            modifier = Modifier.weight(1f),
                        )
                        TextButton(onClick = onRefresh) { Text("刷新") }
                    }
                }

                // 跳过第 0 首：它就是推荐卡上那首，列表里再出现一次是重复信息。
                items(state.tracks.drop(1), key = { it.globalId }) { track ->
                    TrackRow(
                        track = track,
                        isCurrent = track.id == currentTrackId,
                        isPlaying = isPlaying,
                        liked = track.globalId in likedIds,
                        onClick = { onPlayTrack(track) },
                        onToggleLike = { onToggleLike(track) },
                        modifier = Modifier.padding(horizontal = 12.dp),
                    )
                }
            }
        }

        item { Spacer(Modifier.height(12.dp)) }
    }
}

/** 区块标题：左侧一道主色竖条 + 重字重标题，与参考实现的分区手法一致。 */
@Composable
private fun SectionHeader(title: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp)
            .padding(top = 28.dp, bottom = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(width = 4.dp, height = 20.dp)
                .background(
                    MaterialTheme.colorScheme.primary,
                    RoundedCornerShape(2.dp),
                ),
        )
        Text(
            text = title,
            style = MaterialTheme.typography.headlineMedium,
            color = MaterialTheme.colorScheme.onBackground,
            modifier = Modifier.padding(start = 10.dp),
        )
    }
}

@Composable
private fun EmptyBlock(title: String, action: String, onAction: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp)
            .padding(top = 48.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.bodyLarge,
            color = LocalLxExtraColors.current.muted,
        )
        TextButton(onClick = onAction) { Text(action) }
    }
}

private fun greeting(): String = when (Calendar.getInstance().get(Calendar.HOUR_OF_DAY)) {
    in 5..10 -> "早上好"
    in 11..13 -> "中午好"
    in 14..17 -> "下午好"
    in 18..22 -> "晚上好"
    else -> "夜深了"
}
