package cc.lxii.player.ui.component

import org.junit.Assert.assertEquals
import org.junit.Test

class FormatDurationTest {

    @Test
    fun formatsSecondsWithLeadingZero() {
        assertEquals("0:05", formatDuration(5_000))
        assertEquals("1:00", formatDuration(60_000))
        assertEquals("3:07", formatDuration(187_000))
    }

    @Test
    fun formatsLongDurationsWithoutHours() {
        assertEquals("75:00", formatDuration(75 * 60_000L))
    }

    @Test
    fun nonPositiveIsZero() {
        assertEquals("0:00", formatDuration(0))
        assertEquals("0:00", formatDuration(-1))
    }
}
