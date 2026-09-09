package cc.lxii.player.ui.search

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import cc.lxii.player.data.model.Track
import cc.lxii.player.ui.component.TrackRow
import cc.lxii.player.ui.theme.LocalLxExtraColors

@Composable
fun SearchScreen(
    tracks: List<Track>,
    currentTrackId: String?,
    isPlaying: Boolean,
    onPlayTrack: (Track) -> Unit,
    contentPadding: PaddingValues,
    modifier: Modifier = Modifier,
) {
    var query by remember { mutableStateOf("") }
    val results = remember(query, tracks) { filterTracks(tracks, query) }

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
                    .padding(top = 24.dp, bottom = 12.dp),
            ) {
                Text(text = "搜索", style = MaterialTheme.typography.headlineLarge)
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 12.dp),
                    placeholder = { Text("搜索歌曲、歌手、专辑") },
                    leadingIcon = { Icon(Icons.Outlined.Search, contentDescription = null) },
                    singleLine = true,
                    shape = RoundedCornerShape(percent = 50),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                        unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                    ),
                )
            }
        }

        if (query.isNotBlank() && results.isEmpty()) {
            item {
                Text(
                    text = "没有匹配的结果",
                    style = MaterialTheme.typography.bodyLarge,
                    color = LocalLxExtraColors.current.muted,
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 32.dp),
                )
            }
        }

        items(results, key = { it.globalId }) { track ->
            TrackRow(
                track = track,
                isCurrent = track.id == currentTrackId,
                isPlaying = isPlaying,
                onClick = { onPlayTrack(track) },
                modifier = Modifier.padding(horizontal = 12.dp),
            )
        }
    }
}

/**
 * 本地搜索。
 *
 * 抽成顶层函数是为了能在 JVM 里直接测：搜索是「输入什么能找到什么」的行为契约，
 * 不该只能靠手点验证。
 */
fun filterTracks(tracks: List<Track>, query: String): List<Track> {
    val keyword = query.trim()
    if (keyword.isEmpty()) return emptyList()
    return tracks.filter { track ->
        track.title.contains(keyword, ignoreCase = true) ||
            track.artist.contains(keyword, ignoreCase = true) ||
            track.album.contains(keyword, ignoreCase = true)
    }
}
