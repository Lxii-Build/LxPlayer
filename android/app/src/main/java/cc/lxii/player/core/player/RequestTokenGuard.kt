package cc.lxii.player.core.player

/**
 * 解析请求的单调令牌守卫。
 *
 * 用户连点下一首时，上一首歌的 URL 解析可能后到。如果后到的结果仍被应用，
 * 播放器会切回已经翻过去的那首歌。只有令牌仍是最新的解析结果才允许落地。
 */
object RequestTokenGuard {
    fun shouldApply(request: Long, latest: Long): Boolean = request == latest
}

/**
 * ExoPlayer LoadControl 参数。抽成常量是为了让 JVM 测试能钉住它们，
 * 而不必在 CI 里构造一个真实的 ExoPlayer。
 */
object PlayerBufferConfig {
    const val MIN_BUFFER_MS = 15_000
    const val MAX_BUFFER_MS = 30_000
    const val BUFFER_FOR_PLAYBACK_MS = 1_000
    const val BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS = 3_000
    const val BACK_BUFFER_MS = 60_000
    const val BACK_BUFFER_RETAIN_FROM_KEYFRAME = false
    const val CACHE_SIZE_BYTES = 512L * 1024L * 1024L
    const val POSITION_TICK_MS = 200L
}
