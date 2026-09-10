package cc.lxii.player.ui.theme

import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 排版与圆角的具体数值。
 *
 * 这些是「编辑感重字重 + 负字距」这套视觉语言的实际载体：
 * 标题不够重、字距不够紧，整个界面就会从 Cyrene 那种编辑排版
 * 退回成普通 Material 观感。改动这些数值等于改产品外观，
 * 所以逐项钉住，而不是只在设计文档里写一句。
 */
class TypographyTest {

    @Test
    fun displayHeadlineIsBlackWeightWithTightTracking() {
        val style = LxTypography.headlineLarge
        assertEquals(FontWeight.Black, style.fontWeight)
        assertEquals(30.sp, style.fontSize)
        // 负字距是这套排版的标志；正字距会显得松散普通。
        assertTrue("headlineLarge 字距应为负，实测 ${style.letterSpacing}", style.letterSpacing.value < 0f)
    }

    @Test
    fun sectionHeadlineIsExtraBold() {
        val style = LxTypography.headlineMedium
        assertEquals(FontWeight.ExtraBold, style.fontWeight)
        assertEquals(24.sp, style.fontSize)
        assertTrue(style.letterSpacing.value < 0f)
    }

    @Test
    fun cardTitleIsBoldAt14sp() {
        val style = LxTypography.titleSmall
        assertEquals(FontWeight.Bold, style.fontWeight)
        assertEquals(14.sp, style.fontSize)
    }

    @Test
    fun activeNavLabelIsBoldAndSmallerThanBody() {
        val label = LxTypography.labelMedium
        assertEquals(FontWeight.Bold, label.fontWeight)
        assertEquals(11.sp, label.fontSize)
        // 导航标签必须比正文小，否则底栏会抢走内容的视觉重量。
        assertTrue(label.fontSize.value < LxTypography.bodyLarge.fontSize.value)
    }

    @Test
    fun inactiveMetaTextIsTheSmallestTier() {
        assertEquals(10.sp, LxTypography.labelSmall.fontSize)
        assertEquals(FontWeight.Medium, LxTypography.labelSmall.fontWeight)
    }

    @Test
    fun weightDescendsFromHeadlineToBody() {
        // 层级靠字重递减建立，而不是靠颜色。顺序颠倒会让重点跑到正文上。
        val ladder = listOf(
            LxTypography.headlineLarge.fontWeight!!.weight,
            LxTypography.headlineMedium.fontWeight!!.weight,
            LxTypography.titleSmall.fontWeight!!.weight,
            LxTypography.bodyLarge.fontWeight!!.weight,
        )
        assertTrue("字重应逐级递减，实测 $ladder", ladder.zipWithNext().all { (a, b) -> a >= b })
        assertTrue("最重与最轻应有明显落差，实测 $ladder", ladder.first() - ladder.last() >= 400)
    }

    @Test
    fun sizeDescendsFromHeadlineToMeta() {
        val ladder = listOf(
            LxTypography.headlineLarge.fontSize.value,
            LxTypography.headlineMedium.fontSize.value,
            LxTypography.titleSmall.fontSize.value,
            LxTypography.bodySmall.fontSize.value,
            LxTypography.labelSmall.fontSize.value,
        )
        assertTrue("字号应逐级递减，实测 $ladder", ladder.zipWithNext().all { (a, b) -> a > b })
    }

    @Test
    fun lineHeightAlwaysExceedsFontSize() {
        // 行高小于字号会让中文出现明显挤压和裁切。
        listOf(
            "headlineLarge" to LxTypography.headlineLarge,
            "headlineMedium" to LxTypography.headlineMedium,
            "titleLarge" to LxTypography.titleLarge,
            "titleSmall" to LxTypography.titleSmall,
            "bodyLarge" to LxTypography.bodyLarge,
            "bodySmall" to LxTypography.bodySmall,
            "labelSmall" to LxTypography.labelSmall,
        ).forEach { (name, style) ->
            assertTrue(
                "$name 行高 ${style.lineHeight} 应大于字号 ${style.fontSize}",
                style.lineHeight.value > style.fontSize.value,
            )
        }
    }
}

/**
 * 圆角数值。
 *
 * 参考实现的观感很依赖圆角梯度：列表缩略图小圆角、卡片中等、
 * 封面更大、Hero 最大、推荐卡最大且独立。梯度错乱会让层级感消失。
 */
class ShapeTest {

    @Test
    fun radiusLadderIncreasesWithElementImportance() {
        val ladder = listOf(
            LxRadius.listCover.value,
            LxRadius.card.value,
            LxRadius.cover.value,
            LxRadius.hero.value,
            LxRadius.featuredCard.value,
        )
        assertTrue("圆角应逐级增大，实测 $ladder", ladder.zipWithNext().all { (a, b) -> b > a })
    }

    @Test
    fun radiiMatchTheDesignValues() {
        assertEquals(10f, LxRadius.listCover.value, 0f)
        assertEquals(16f, LxRadius.card.value, 0f)
        assertEquals(20f, LxRadius.cover.value, 0f)
        assertEquals(24f, LxRadius.hero.value, 0f)
        // 推荐卡 28dp 来自参考实现实测，是首页最大的圆角。
        assertEquals(28f, LxRadius.featuredCard.value, 0f)
    }

    @Test
    fun stageCoverIsTighterThanHomeCards() {
        // 播放页封面 14dp：台面是纯黑全屏，圆角过大会让封面显得漂浮。
        assertEquals(14f, LxRadius.stageCover.value, 0f)
        assertTrue(LxRadius.stageCover.value < LxRadius.cover.value)
    }

    @Test
    fun sheetCornerSitsBetweenCardAndCover() {
        assertEquals(18f, LxRadius.sheet.value, 0f)
        assertTrue(LxRadius.sheet.value > LxRadius.card.value)
        assertTrue(LxRadius.sheet.value < LxRadius.cover.value)
    }

}
