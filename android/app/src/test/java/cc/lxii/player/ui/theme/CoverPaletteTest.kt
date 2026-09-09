package cc.lxii.player.ui.theme

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CoverPaletteTest {

    private fun argb(r: Int, g: Int, b: Int) = (0xFF shl 24) or (r shl 16) or (g shl 8) or b

    @Test
    fun blackIsDark() {
        assertTrue(isDark(argb(0, 0, 0)))
    }

    @Test
    fun whiteIsLight() {
        assertFalse(isDark(argb(255, 255, 255)))
    }

    @Test
    fun greenWeighsMoreThanBlue() {
        // sRGB 感知亮度里绿通道权重 0.7152、蓝只有 0.0722，
        // 简单平均会把这两个判成一样亮，那样叠加层深浅就会选错。
        assertFalse(isDark(argb(0, 255, 0)))
        assertTrue(isDark(argb(0, 0, 255)))
    }

    @Test
    fun neutralFallbackIsDarkSoTextStaysReadableOnBlackStage() {
        assertTrue(NeutralAccent.isDarkCover)
        assertTrue(NeutralAccent.accent.isDarkColor())
    }
}
