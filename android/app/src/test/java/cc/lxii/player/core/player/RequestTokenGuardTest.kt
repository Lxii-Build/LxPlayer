package cc.lxii.player.core.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RequestTokenGuardTest {

    @Test
    fun matchingTokensApply() {
        assertTrue(RequestTokenGuard.shouldApply(request = 7L, latest = 7L))
    }

    @Test
    fun staleTokensAreDiscarded() {
        assertFalse(RequestTokenGuard.shouldApply(request = 6L, latest = 7L))
        assertFalse(RequestTokenGuard.shouldApply(request = 8L, latest = 7L))
    }
}

class PlayerBufferConfigTest {

    @Test
    fun loadControlMatchesAudioTunedValues() {
        assertEquals(15_000, PlayerBufferConfig.MIN_BUFFER_MS)
        assertEquals(30_000, PlayerBufferConfig.MAX_BUFFER_MS)
        assertEquals(1_000, PlayerBufferConfig.BUFFER_FOR_PLAYBACK_MS)
        assertEquals(3_000, PlayerBufferConfig.BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS)
        assertEquals(60_000, PlayerBufferConfig.BACK_BUFFER_MS)
        assertFalse(PlayerBufferConfig.BACK_BUFFER_RETAIN_FROM_KEYFRAME)
        assertEquals(512L * 1024L * 1024L, PlayerBufferConfig.CACHE_SIZE_BYTES)
        assertEquals(200L, PlayerBufferConfig.POSITION_TICK_MS)
    }
}
