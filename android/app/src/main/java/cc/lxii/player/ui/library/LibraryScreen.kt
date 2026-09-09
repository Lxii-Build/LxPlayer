package cc.lxii.player.ui.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import cc.lxii.player.data.model.Track
import cc.lxii.player.ui.LibraryUiState
import cc.lxii.player.ui.component.TrackRow
import cc.lxii.player.ui.theme.LocalLxExtraColors

@Composable
fun LibraryScreen(
    state: LibraryUiState,
    currentTrackId: String?,
    isPlaying: Boolean,
    likedIds: Set<String>,
    onPlayTrack: (Track) -> Unit,
    onToggleLike: (Track) -> Unit,
    onRefresh: () -> Unit,
    contentPadding: PaddingValues,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.fillMaxWidth(),
        contentPadding = contentPadding,
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        item {
            Column(
                modifier = Modifier
                    .statusBarsPadding()
                    .padding(horizontal = 20.dp)
                    .padding(top = 24.dp, bottom = 8.dp),
            ) {
                Text(
                    text = "音乐库",
                    style = MaterialTheme.typography.headlineLarge,
                )
                Text(
                    text = "本地共 ${state.tracks.size} 首",
                    style = MaterialTheme.typography.bodyLarge,
                    color = LocalLxExtraColors.current.muted,
                )
            }
        }

        if (state.tracks.isEmpty()) {
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp, vertical = 48.dp),
                ) {
                    Text(
                        text = state.error ?: "没有扫描到本地音乐",
                        style = MaterialTheme.typography.bodyLarge,
                        color = LocalLxExtraColors.current.muted,
                    )
                    TextButton(onClick = onRefresh) { Text("重新扫描") }
                }
            }
        } else {
            items(state.tracks, key = { it.globalId }) { track ->
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
}
