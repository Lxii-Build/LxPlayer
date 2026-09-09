package cc.lxii.player.core.player.policy

/** 睡眠定时模式。 */
enum class SleepTimerMode {
    /** 到点立即停止。 */
    COUNTDOWN,

    /** 到点后等当前这首播完再停，避免在副歌中间被切断。 */
    COUNTDOWN_FINISH_CURRENT,
}

/** 睡眠定时状态。[deadlineMs] 与 [SleepTimerPolicy.remainingMs] 的 nowMs 使用同一时钟。 */
data class SleepTimerState(
    val mode: SleepTimerMode,
    val deadlineMs: Long,
    val armed: Boolean = true,
)

object SleepTimerPolicy {

    /** 可选时长（分钟）。 */
    val presetMinutes = listOf(15, 30, 45, 60, 90)

    fun arm(nowMs: Long, minutes: Int, mode: SleepTimerMode): SleepTimerState =
        SleepTimerState(mode, nowMs + minutes * 60_000L)

    /** 剩余毫秒，不为负。 */
    fun remainingMs(state: SleepTimerState?, nowMs: Long): Long {
        if (state == null || !state.armed) return 0L
        return (state.deadlineMs - nowMs).coerceAtLeast(0L)
    }

    /**
     * 现在是否应该停止播放。
     *
     * [SleepTimerMode.COUNTDOWN_FINISH_CURRENT] 到点后仍需等 [trackEnded]，
     * 这正是它与 [SleepTimerMode.COUNTDOWN] 的唯一区别。
     */
    fun shouldStop(state: SleepTimerState?, nowMs: Long, trackEnded: Boolean): Boolean {
        if (state == null || !state.armed) return false
        val expired = nowMs >= state.deadlineMs
        if (!expired) return false
        return when (state.mode) {
            SleepTimerMode.COUNTDOWN -> true
            SleepTimerMode.COUNTDOWN_FINISH_CURRENT -> trackEnded
        }
    }
}
