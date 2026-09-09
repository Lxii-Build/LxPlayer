package cc.lxii.player.core.player.policy

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SleepTimerPolicyTest {

    @Test
    fun remainingMs_countsDownAndNeverGoesNegative() {
        val state = SleepTimerPolicy.arm(nowMs = 1_000L, minutes = 15, mode = SleepTimerMode.COUNTDOWN)
        assertEquals(15 * 60_000L, SleepTimerPolicy.remainingMs(state, nowMs = 1_000L))
        assertEquals(0L, SleepTimerPolicy.remainingMs(state, nowMs = 1_000L + 15 * 60_000L + 5_000L))
    }

    @Test
    fun countdown_stopsAtDeadlineEvenMidTrack() {
        val state = SleepTimerPolicy.arm(nowMs = 0L, minutes = 1, mode = SleepTimerMode.COUNTDOWN)
        assertFalse(SleepTimerPolicy.shouldStop(state, nowMs = 59_000L, trackEnded = false))
        assertTrue(SleepTimerPolicy.shouldStop(state, nowMs = 60_000L, trackEnded = false))
    }

    @Test
    fun finishCurrent_waitsForTrackEndAfterDeadline() {
        val state = SleepTimerPolicy.arm(
            nowMs = 0L,
            minutes = 1,
            mode = SleepTimerMode.COUNTDOWN_FINISH_CURRENT,
        )
        assertFalse(SleepTimerPolicy.shouldStop(state, nowMs = 60_000L, trackEnded = false))
        assertTrue(SleepTimerPolicy.shouldStop(state, nowMs = 60_000L, trackEnded = true))
    }

    @Test
    fun disarmedOrNullNeverStops() {
        assertFalse(SleepTimerPolicy.shouldStop(null, nowMs = 10_000L, trackEnded = true))
        val state = SleepTimerPolicy.arm(0L, 1, SleepTimerMode.COUNTDOWN).copy(armed = false)
        assertFalse(SleepTimerPolicy.shouldStop(state, nowMs = 60_000L, trackEnded = true))
    }

    @Test
    fun presetsAreTheDocumentedSet() {
        assertEquals(listOf(15, 30, 45, 60, 90), SleepTimerPolicy.presetMinutes)
    }
}
