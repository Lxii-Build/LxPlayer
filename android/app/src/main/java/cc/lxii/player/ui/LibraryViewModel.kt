package cc.lxii.player.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import cc.lxii.player.core.player.PlayerController
import cc.lxii.player.core.source.LocalMusicSource
import cc.lxii.player.data.model.Track
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class LibraryUiState(
    val loading: Boolean = true,
    val tracks: List<Track> = emptyList(),
    val permissionGranted: Boolean = false,
    val error: String? = null,
)

/**
 * 音乐库与首页共用的状态。
 *
 * 播放状态不放这里——它在 [PlayerController] 里以 StateFlow 暴露，
 * 界面直接 collect，避免多一层转发导致状态不同步。
 */
class LibraryViewModel(
    private val source: LocalMusicSource,
    private val player: PlayerController,
) : ViewModel() {

    private val _state = MutableStateFlow(LibraryUiState())
    val state: StateFlow<LibraryUiState> = _state.asStateFlow()

    private val _featuredIndex = MutableStateFlow(0)
    val featuredIndex: StateFlow<Int> = _featuredIndex.asStateFlow()

    fun onPermissionResult(granted: Boolean) {
        _state.value = _state.value.copy(permissionGranted = granted)
        if (granted) refresh() else _state.value = _state.value.copy(loading = false)
    }

    fun refresh() {
        viewModelScope.launch {
            _state.value = _state.value.copy(loading = true, error = null)
            val result = runCatching { source.scanLibrary() }
            _state.value = result.fold(
                onSuccess = { tracks ->
                    _state.value.copy(loading = false, tracks = tracks, error = null)
                },
                onFailure = { throwable ->
                    _state.value.copy(
                        loading = false,
                        error = throwable.message ?: "扫描本地音乐失败",
                    )
                },
            )
            if (_featuredIndex.value >= _state.value.tracks.size) _featuredIndex.value = 0
        }
    }

    /**
     * 推荐卡换页。
     *
     * 若当前播放的曲目就在推荐列表里，滑动同时切换队列——复刻参考交互。
     * 判定按稳定 id 而非下标：随机播放会打乱队列顺序，下标随时失效。
     */
    fun onFeaturedIndexChange(index: Int) {
        val tracks = _state.value.tracks
        if (tracks.isEmpty()) return
        val previous = _featuredIndex.value
        _featuredIndex.value = index

        val currentId = player.currentTrack.value?.id ?: return
        if (tracks.none { it.id == currentId }) return
        val forward = (previous + 1).mod(tracks.size) == index
        if (forward) player.next() else player.previous()
    }

    fun playFromLibrary(track: Track) {
        val tracks = _state.value.tracks
        val index = tracks.indexOfFirst { it.id == track.id }.takeIf { it >= 0 } ?: return
        player.playQueue(tracks, index)
    }

    /** 推荐区之外的「每日歌曲」列表：跳过第 0 首，它已经在推荐卡上了。 */
    fun dailyTracks(): List<Track> = _state.value.tracks.drop(1)

    class Factory(
        private val source: LocalMusicSource,
        private val player: PlayerController,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            LibraryViewModel(source, player) as T
    }
}
