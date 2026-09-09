package cc.lxii.player.core.player.policy

/** 循环模式。顺序固定为 关闭 → 单曲 → 列表，与通知栏按钮的循环切换一致。 */
enum class RepeatMode {
    OFF,
    ONE,
    ALL,
}

object RepeatPolicy {

    /** 点一次循环按钮的下一个状态。 */
    fun next(current: RepeatMode): RepeatMode = when (current) {
        RepeatMode.OFF -> RepeatMode.ONE
        RepeatMode.ONE -> RepeatMode.ALL
        RepeatMode.ALL -> RepeatMode.OFF
    }

    /**
     * 当前曲目播完后应该跳到哪个下标，返回 null 表示停止播放。
     *
     * 播放器一次只持有一个 MediaItem，所以「播完下一首」这件事必须由我们自己算，
     * 不能依赖播放器的列表推进。
     */
    fun nextIndexOnCompletion(
        currentIndex: Int,
        queueSize: Int,
        repeatMode: RepeatMode,
    ): Int? {
        if (queueSize <= 0 || currentIndex !in 0 until queueSize) return null
        return when (repeatMode) {
            RepeatMode.ONE -> currentIndex
            RepeatMode.ALL -> (currentIndex + 1) % queueSize
            RepeatMode.OFF -> (currentIndex + 1).takeIf { it < queueSize }
        }
    }

    /**
     * 手动点「下一首」应该跳到哪个下标。
     *
     * 与自动播完不同：用户主动点下一首时，即使循环关闭，到末尾也回到开头——
     * 用户的明确操作不该静默失效。
     */
    fun manualNextIndex(currentIndex: Int, queueSize: Int): Int? {
        if (queueSize <= 0) return null
        return (currentIndex + 1).mod(queueSize)
    }

    /** 手动点「上一首」。 */
    fun manualPreviousIndex(currentIndex: Int, queueSize: Int): Int? {
        if (queueSize <= 0) return null
        return (currentIndex - 1).mod(queueSize)
    }
}
