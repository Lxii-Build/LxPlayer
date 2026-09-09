package cc.lxii.player.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * 色板。
 *
 * 刻意不设品牌彩色：主色是中性灰，颜色全部来自封面取色。
 * 这些数值是视觉基线，改动等于改产品外观，所以有测试钉住。
 */
object LxColors {
    // Light
    val lightBackground = Color(0xFFFFFFFF)
    val lightOnBackground = Color(0xFF171717)
    val lightSurfaceVariant = Color(0xFFF5F5F5)
    val lightPrimary = Color(0xFF262626)
    val lightOnPrimary = Color(0xFFFAFAFA)
    val lightMuted = Color(0xFF737373)
    val lightOutline = Color(0x0D000000)

    // Dark
    val darkBackground = Color(0xFF171717)
    val darkOnBackground = Color(0xFFFAFAFA)
    val darkSurfaceVariant = Color(0xFF242424)
    val darkPrimary = Color(0xFFE5E5E5)
    val darkOnPrimary = Color(0xFF262626)
    val darkMuted = Color(0xFFA3A3A3)
    val darkOutline = Color(0x1AFFFFFF)

    // 语义色
    val liked = Color(0xFFEF4444)
    val destructiveLight = Color(0xFFE5484D)
    val destructiveDark = Color(0xFFF07167)

    /** 播放页台面固定纯黑，不随主题变化。 */
    val stage = Color(0xFF000000)

    /** 推荐卡前层封面阴影色。 */
    val cardCoverShadow = Color(0xFF17212D)
}
