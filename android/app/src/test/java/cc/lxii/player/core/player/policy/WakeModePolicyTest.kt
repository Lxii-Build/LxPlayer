package cc.lxii.player.core.player.policy

import org.junit.Assert.assertEquals
import org.junit.Test

class WakeModePolicyTest {

    @Test
    fun httpsUsesNetworkWakeLock() {
        assertEquals(WakeMode.NETWORK, WakeModePolicy.forUrl("https://cdn.example/a.mp3"))
    }

    @Test
    fun httpUsesNetworkWakeLock() {
        assertEquals(WakeMode.NETWORK, WakeModePolicy.forUrl("http://cdn.example/a.mp3"))
    }

    @Test
    fun fileUriUsesLocalWakeLock() {
        assertEquals(WakeMode.LOCAL, WakeModePolicy.forUrl("file:///sdcard/Music/a.mp3"))
    }

    @Test
    fun contentUriUsesLocalWakeLock() {
        assertEquals(WakeMode.LOCAL, WakeModePolicy.forUrl("content://media/external/audio/media/1"))
    }

    @Test
    fun absolutePathUsesLocalWakeLock() {
        assertEquals(WakeMode.LOCAL, WakeModePolicy.forUrl("/storage/emulated/0/Music/a.mp3"))
    }

    @Test
    fun emptyOrNullUsesNone() {
        assertEquals(WakeMode.NONE, WakeModePolicy.forUrl(""))
        assertEquals(WakeMode.NONE, WakeModePolicy.forUrl("   "))
        assertEquals(WakeMode.NONE, WakeModePolicy.forUrl(null))
    }
}
