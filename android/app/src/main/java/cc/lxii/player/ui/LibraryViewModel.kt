package cc.lxii.player.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.media3.common.util.UnstableApi
import cc.lxii.player.core.lyrics.LyricLine
import cc.lxii.player.core.lyrics.LyricsRepository
import cc.lxii.player.core.player.PlayerController
import cc.lxii.player.core.source.LocalMusicSource
import cc.lxii.player.data.model.Track
import cc.lxii.player.data.prefs.SettingsStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
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
@UnstableApi
class LibraryViewModel(
    private val source: LocalMusicSource,
    private val player: PlayerController,
    private val settings: SettingsStore,
    private val lyricsRepository: LyricsRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(LibraryUiState())
    val state: StateFlow<LibraryUiState> = _state.asStateFlow()

    private val _featuredIndex = MutableStateFlow(0)
    val featuredIndex: StateFlow<Int> = _featuredIndex.asStateFlow()

    val likedIds: StateFlow<Set<String>> = settings.likedTracks
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptySet())

    private val _lyrics = MutableStateFlow<List<LyricLine>>(emptyList())
    val lyrics: StateFlow<List<LyricLine>> = _lyrics.asStateFlow()

    /**
     * 跟随当前曲目加载歌词。
     *
     * 换歌先清空再加载：留着上一首的歌词滚动，比没有歌词更让人困惑。
     */
    fun loadLyricsFor(track: Track?) {
        _lyrics.value = emptyList()
        if (track == null) return
        viewModelScope.launch {
            val loaded = runCatching { lyricsRepository.load(track) }.getOrDefault(emptyList())
            // 加载期间可能又换了歌，确认还是同一首才应用。
            if (player.currentTrack.value?.globalId == track.globalId) {
                _lyrics.value = loaded
            }
        }
    }

    fun toggleLike(track: Track) {
        viewModelScope.launch { settings.toggleLiked(track.globalId) }
    }

    /** 每日推荐：按扫描顺序整表播放。 */
    fun playDaily() {
        val tracks = _state.value.tracks
        if (tracks.isEmpty()) return
        player.playQueue(tracks, 0)
    }

    /** 私人 FM：随机起点 + 打开随机播放。 */
    fun playShuffled() {
        val tracks = _state.value.tracks
        if (tracks.isEmpty()) return
        player.playQueue(tracks, tracks.indices.random())
        player.setShuffle(true)
    }

    /**
     * 直接注入曲目列表，仅供测试。
     *
     * 正常路径的列表来自 MediaStore 扫描，测试环境里没有真实媒体库，
     * 于是「滑动推荐卡联动切歌」这条最容易出错的逻辑就无法覆盖。
     */
    @androidx.annotation.VisibleForTesting
    fun setTracksForTesting(tracks: List<Track>) {
        _state.value = _state.value.copy(
            loading = false,
            permissionGranted = true,
            tracks = tracks,
            error = null,
        )
    }

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
        val previous = _featuredIndex.value
        // 换页是纯 UI 状态，先更新再判断是否联动播放。
        // 早先写成「列表为空就整个返回」，连下标都不更新——
        // 空库时卡片会卡住不动，而这本该只是「没歌可联动」而已。
        _featuredIndex.value = index
        if (tracks.isEmpty()) return

        val currentId = player.currentTrack.value?.id ?: return
        // 按稳定 id 判断当前曲目是否在推荐列表里。
        // 参考实现按索引判断，随机播放打乱队列后就会错位切到别的歌。
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
        private val settings: SettingsStore,
        private val lyricsRepository: LyricsRepository,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            LibraryViewModel(source, player, settings, lyricsRepository) as T
    }
}
