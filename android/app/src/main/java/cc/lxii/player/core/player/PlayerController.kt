package cc.lxii.player.core.player

import android.content.Context
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import cc.lxii.player.core.player.policy.QueuePolicy
import cc.lxii.player.core.player.policy.RepeatMode
import cc.lxii.player.core.player.policy.RepeatPolicy
import cc.lxii.player.core.player.policy.SleepTimerMode
import cc.lxii.player.core.player.policy.SleepTimerPolicy
import cc.lxii.player.core.player.policy.SleepTimerState
import cc.lxii.player.core.player.policy.QueueMutation
import cc.lxii.player.core.player.policy.WakeMode
import cc.lxii.player.core.player.policy.WakeModePolicy
import cc.lxii.player.core.source.AudioQuality
import cc.lxii.player.core.source.MusicSource
import cc.lxii.player.core.source.SongUrlResult
import cc.lxii.player.data.model.Track
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

sealed interface PlayerEvent {
    data class ResolveFailed(val track: Track, val reason: String) : PlayerEvent
    data object QueueEmptied : PlayerEvent
}

/**
 * 播放总控。单例，直接向 UI 暴露 StateFlow，不再套一层播放 ViewModel——
 * 播放状态是进程级的，套 ViewModel 只会多一层转发。
 *
 * 队列由这里持有，播放器一次只拿一个 MediaItem：每首歌都要先解析地址，
 * 把整张列表塞给播放器就没法在每首歌播放前插入解析步骤。
 * 代价是没有无缝衔接（gapless），这是明确接受的取舍。
 */
@UnstableApi
class PlayerController private constructor(
    private val context: Context,
    private val source: MusicSource,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private var player: ExoPlayer? = null
    private var playJob: Job? = null
    private var tickerJob: Job? = null

    /** 单调递增的解析令牌，连点切歌时用来丢弃迟到的旧解析结果。 */
    private var requestToken = 0L

    private var shuffleSnapshot: QueueMutation? = null

    private val _queue = MutableStateFlow<List<Track>>(emptyList())
    val queue: StateFlow<List<Track>> = _queue.asStateFlow()

    private val _currentIndex = MutableStateFlow(-1)
    val currentIndex: StateFlow<Int> = _currentIndex.asStateFlow()

    private val _currentTrack = MutableStateFlow<Track?>(null)
    val currentTrack: StateFlow<Track?> = _currentTrack.asStateFlow()

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()

    private val _positionMs = MutableStateFlow(0L)
    val positionMs: StateFlow<Long> = _positionMs.asStateFlow()

    private val _durationMs = MutableStateFlow(0L)
    val durationMs: StateFlow<Long> = _durationMs.asStateFlow()

    private val _repeatMode = MutableStateFlow(RepeatMode.OFF)
    val repeatMode: StateFlow<RepeatMode> = _repeatMode.asStateFlow()

    private val _shuffleEnabled = MutableStateFlow(false)
    val shuffleEnabled: StateFlow<Boolean> = _shuffleEnabled.asStateFlow()

    private val _pendingLoad = MutableStateFlow(false)
    val pendingLoad: StateFlow<Boolean> = _pendingLoad.asStateFlow()

    private val _playbackSpeed = MutableStateFlow(1.0f)
    val playbackSpeed: StateFlow<Float> = _playbackSpeed.asStateFlow()

    private val _sleepTimer = MutableStateFlow<SleepTimerState?>(null)
    val sleepTimer: StateFlow<SleepTimerState?> = _sleepTimer.asStateFlow()

    private val _events = MutableSharedFlow<PlayerEvent>(extraBufferCapacity = 8)
    val events: SharedFlow<PlayerEvent> = _events.asSharedFlow()

    /**
     * 保证播放器已创建。
     *
     * 从界面点播放时服务可能还没 onCreate，如果这里空等就会把这次播放吞掉。
     * 播放器由控制器持有，服务只负责挂 MediaSession 和前台通知。
     */
    @Synchronized
    fun ensurePlayer(): ExoPlayer {
        player?.let { return it }
        val created = PlayerFactory.build(context)
        attach(created)
        return created
    }

    fun attach(exoPlayer: ExoPlayer) {
        if (player === exoPlayer) return
        player?.removeListener(listener)
        player = exoPlayer
        exoPlayer.addListener(listener)
        startTicker()
    }

    fun detach() {
        tickerJob?.cancel()
        player?.removeListener(listener)
        player = null
    }

    private val listener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            _isPlaying.value = isPlaying
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            if (playbackState == Player.STATE_READY) {
                _pendingLoad.value = false
                player?.duration?.takeIf { it != C.TIME_UNSET }?.let { _durationMs.value = it }
            }
            if (playbackState == Player.STATE_ENDED) {
                onTrackCompleted()
            }
        }
    }

    private fun onTrackCompleted() {
        val timer = _sleepTimer.value
        if (SleepTimerPolicy.shouldStop(timer, System.currentTimeMillis(), trackEnded = true)) {
            stop()
            _sleepTimer.value = null
            return
        }
        val next = RepeatPolicy.nextIndexOnCompletion(
            currentIndex = _currentIndex.value,
            queueSize = _queue.value.size,
            repeatMode = _repeatMode.value,
        )
        if (next == null) {
            _isPlaying.value = false
        } else {
            playAt(next)
        }
    }

    private fun startTicker() {
        tickerJob?.cancel()
        tickerJob = scope.launch {
            while (true) {
                val active = player
                if (active != null) {
                    _positionMs.value = active.currentPosition.coerceAtLeast(0L)
                    active.duration.takeIf { it != C.TIME_UNSET }?.let { _durationMs.value = it }
                    val timer = _sleepTimer.value
                    if (timer != null &&
                        timer.mode == SleepTimerMode.COUNTDOWN &&
                        SleepTimerPolicy.shouldStop(timer, System.currentTimeMillis(), false)
                    ) {
                        stop()
                        _sleepTimer.value = null
                    }
                }
                delay(PlayerBufferConfig.POSITION_TICK_MS)
            }
        }
    }

    fun playQueue(tracks: List<Track>, startIndex: Int) {
        if (tracks.isEmpty()) return
        _queue.value = tracks
        shuffleSnapshot = null
        _shuffleEnabled.value = false
        playAt(startIndex.coerceIn(0, tracks.lastIndex))
    }

    fun playAt(index: Int) {
        val tracks = _queue.value
        if (index !in tracks.indices) return
        val track = tracks[index]
        _currentIndex.value = index
        _currentTrack.value = track

        playJob?.cancel()
        requestToken += 1
        val token = requestToken
        _pendingLoad.value = true
        _positionMs.value = 0L

        playJob = scope.launch {
            val result = withContext(Dispatchers.IO) {
                source.resolve(track, AudioQuality.STANDARD)
            }
            // 迟到的解析结果必须丢弃，否则会把已经翻过去的歌切回来。
            if (!RequestTokenGuard.shouldApply(token, requestToken)) return@launch

            when (result) {
                is SongUrlResult.Failure -> {
                    _pendingLoad.value = false
                    _events.tryEmit(PlayerEvent.ResolveFailed(track, result.reason))
                }
                is SongUrlResult.Success -> {
                    val active = ensurePlayer()
                    active.setWakeMode(WakeModePolicy.forUrl(result.url).toMedia3())
                    active.setMediaItem(buildMediaItem(track, result))
                    active.prepare()
                    active.playWhenReady = true
                }
            }
        }
    }

    private fun buildMediaItem(track: Track, resolved: SongUrlResult.Success): MediaItem =
        MediaItem.Builder()
            .setMediaId(track.globalId)
            .setUri(resolved.url)
            .apply {
                resolved.mimeType?.takeIf { it.isNotBlank() }?.let { setMimeType(it) }
                // 缓存键与会轮换的签名 URL 解耦：URL 换了参数，缓存仍然命中。
                resolved.cacheKeyOverride?.takeIf { it.isNotBlank() }?.let { setCustomCacheKey(it) }
            }
            .build()

    fun playPause() {
        val active = player ?: return
        if (active.isPlaying) active.pause() else active.play()
    }

    fun next() {
        RepeatPolicy.manualNextIndex(_currentIndex.value, _queue.value.size)?.let(::playAt)
    }

    fun previous() {
        RepeatPolicy.manualPreviousIndex(_currentIndex.value, _queue.value.size)?.let(::playAt)
    }

    fun seekTo(positionMs: Long) {
        player?.seekTo(positionMs.coerceAtLeast(0L))
        _positionMs.value = positionMs.coerceAtLeast(0L)
    }

    fun stop() {
        playJob?.cancel()
        player?.stop()
        _isPlaying.value = false
        _pendingLoad.value = false
    }

    fun cycleRepeat() {
        _repeatMode.value = RepeatPolicy.next(_repeatMode.value)
    }

    fun setShuffle(enabled: Boolean) {
        if (enabled == _shuffleEnabled.value) return
        if (enabled) {
            val mutation = QueuePolicy.shuffled(
                _queue.value,
                _currentIndex.value,
                seed = System.nanoTime(),
            )
            shuffleSnapshot = mutation
            apply(mutation)
        } else {
            val snapshot = shuffleSnapshot
            if (snapshot != null) apply(QueuePolicy.restore(snapshot))
            shuffleSnapshot = null
        }
        _shuffleEnabled.value = enabled
    }

    fun insertNext(track: Track) {
        val wasEmpty = _queue.value.isEmpty()
        apply(QueuePolicy.insertNext(_queue.value, _currentIndex.value, track))
        if (wasEmpty) playAt(0)
    }

    fun addToEnd(track: Track) {
        val wasEmpty = _queue.value.isEmpty()
        apply(QueuePolicy.addToEnd(_queue.value, _currentIndex.value, track))
        if (wasEmpty) playAt(0)
    }

    fun removeAt(index: Int) {
        val wasCurrent = index == _currentIndex.value
        val mutation = QueuePolicy.remove(_queue.value, _currentIndex.value, index)
        apply(mutation)
        when {
            mutation.queue.isEmpty() -> {
                stop()
                _currentTrack.value = null
                _events.tryEmit(PlayerEvent.QueueEmptied)
            }
            wasCurrent -> playAt(mutation.currentIndex)
        }
    }

    fun move(from: Int, to: Int) {
        apply(QueuePolicy.move(_queue.value, _currentIndex.value, from, to))
    }

    fun setSpeed(speed: Float) {
        val clamped = speed.coerceIn(0.5f, 2.0f)
        _playbackSpeed.value = clamped
        player?.playbackParameters = PlaybackParameters(clamped, 1.0f)
    }

    fun armSleepTimer(minutes: Int, mode: SleepTimerMode) {
        _sleepTimer.value = SleepTimerPolicy.arm(System.currentTimeMillis(), minutes, mode)
    }

    fun cancelSleepTimer() {
        _sleepTimer.value = null
    }

    private fun apply(mutation: QueueMutation) {
        _queue.value = mutation.queue
        _currentIndex.value = mutation.currentIndex
        _currentTrack.value = mutation.queue.getOrNull(mutation.currentIndex)
    }

    private fun WakeMode.toMedia3(): Int = when (this) {
        WakeMode.NETWORK -> C.WAKE_MODE_NETWORK
        WakeMode.LOCAL -> C.WAKE_MODE_LOCAL
        WakeMode.NONE -> C.WAKE_MODE_NONE
    }

    companion object {
        @Volatile
        private var instance: PlayerController? = null

        fun get(context: Context, source: MusicSource): PlayerController =
            instance ?: synchronized(this) {
                instance ?: PlayerController(context.applicationContext, source).also {
                    instance = it
                }
            }

        fun peek(): PlayerController? = instance
    }
}
