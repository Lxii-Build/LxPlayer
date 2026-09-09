package cc.lxii.player.core.player.policy

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RepeatPolicyTest {

    @Test
    fun next_cyclesOffOneAll() {
        assertEquals(RepeatMode.ONE, RepeatPolicy.next(RepeatMode.OFF))
        assertEquals(RepeatMode.ALL, RepeatPolicy.next(RepeatMode.ONE))
        assertEquals(RepeatMode.OFF, RepeatPolicy.next(RepeatMode.ALL))
    }

    @Test
    fun completion_oneRepeatsSameIndex() {
        assertEquals(1, RepeatPolicy.nextIndexOnCompletion(1, 3, RepeatMode.ONE))
    }

    @Test
    fun completion_allWrapsToStart() {
        assertEquals(0, RepeatPolicy.nextIndexOnCompletion(2, 3, RepeatMode.ALL))
    }

    @Test
    fun completion_offStopsAtEnd() {
        assertNull(RepeatPolicy.nextIndexOnCompletion(2, 3, RepeatMode.OFF))
    }

    @Test
    fun completion_offAdvancesWhenNotAtEnd() {
        assertEquals(2, RepeatPolicy.nextIndexOnCompletion(1, 3, RepeatMode.OFF))
    }

    @Test
    fun completion_onEmptyQueueStops() {
        assertNull(RepeatPolicy.nextIndexOnCompletion(0, 0, RepeatMode.ALL))
    }

    @Test
    fun manualNext_wrapsEvenWhenRepeatIsOff() {
        assertEquals(0, RepeatPolicy.manualNextIndex(2, 3))
        assertEquals(2, RepeatPolicy.manualPreviousIndex(0, 3))
    }

    @Test
    fun manualSkip_onEmptyQueueReturnsNull() {
        assertNull(RepeatPolicy.manualNextIndex(0, 0))
        assertNull(RepeatPolicy.manualPreviousIndex(0, 0))
    }
}
