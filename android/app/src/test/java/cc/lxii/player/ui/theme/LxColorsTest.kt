package cc.lxii.player.ui.theme

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * 色板是产品外观的定义。这些断言不是为了验证 Compose，
 * 而是防止有人「顺手调一下颜色」把视觉基线改掉却无人察觉。
 */
class LxColorsTest {

    @Test
    fun lightPaletteMatchesTheSpec() {
        assertEquals(Color(0xFFFFFFFF), LxColors.lightBackground)
        assertEquals(Color(0xFF171717), LxColors.lightOnBackground)
        assertEquals(Color(0xFFF5F5F5), LxColors.lightSurfaceVariant)
        assertEquals(Color(0xFF262626), LxColors.lightPrimary)
        assertEquals(Color(0xFFFAFAFA), LxColors.lightOnPrimary)
        assertEquals(Color(0xFF737373), LxColors.lightMuted)
    }

    @Test
    fun darkPaletteMatchesTheSpec() {
        assertEquals(Color(0xFF171717), LxColors.darkBackground)
        assertEquals(Color(0xFFFAFAFA), LxColors.darkOnBackground)
        assertEquals(Color(0xFF242424), LxColors.darkSurfaceVariant)
        assertEquals(Color(0xFFE5E5E5), LxColors.darkPrimary)
        assertEquals(Color(0xFF262626), LxColors.darkOnPrimary)
        assertEquals(Color(0xFFA3A3A3), LxColors.darkMuted)
    }

    @Test
    fun semanticColorsMatchTheSpec() {
        assertEquals(Color(0xFFEF4444), LxColors.liked)
        assertEquals(Color(0xFFE5484D), LxColors.destructiveLight)
        assertEquals(Color(0xFFF07167), LxColors.destructiveDark)
        assertEquals(Color(0xFF000000), LxColors.stage)
        assertEquals(Color(0xFF17212D), LxColors.cardCoverShadow)
    }

    @Test
    fun primaryIsNeutralGrayNotABrandHue() {
        // 主色必须是灰阶：R=G=B。彩色主色会破坏「颜色只来自封面」的设计。
        val light = LxColors.lightPrimary
        assertEquals(light.red, light.green, 0.001f)
        assertEquals(light.green, light.blue, 0.001f)

        val dark = LxColors.darkPrimary
        assertEquals(dark.red, dark.green, 0.001f)
        assertEquals(dark.green, dark.blue, 0.001f)
    }
}
