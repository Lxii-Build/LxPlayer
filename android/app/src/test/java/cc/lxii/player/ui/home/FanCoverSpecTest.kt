package cc.lxii.player.ui.home

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 扇形封面的设计参数。
 *
 * 这些数值来自参考交互实测，是「卡片看起来对不对」的直接依据。
 * 用纯 JVM 断言钉住它们，比依赖渲染坐标可靠：
 * 旋转会改变布局包围盒，从 boundsInRoot 反推 offset 未必测得准，
 * 但参数本身被改动一定会被这里抓到。
 */
class FanCoverSpecTest {

    @Test
    fun threeLayersAreDefined() {
        assertEquals(3, FanCoverLayerSpecs.size)
        assertEquals(listOf("back", "mid", "front"), FanCoverLayerSpecs.map { it.name })
    }

    @Test
    fun sizesMatchTheReferenceLayout() {
        assertEquals(112 to 144, FanCoverLayerSpecs[0].widthDp to FanCoverLayerSpecs[0].heightDp)
        assertEquals(120 to 160, FanCoverLayerSpecs[1].widthDp to FanCoverLayerSpecs[1].heightDp)
        assertEquals(128 to 176, FanCoverLayerSpecs[2].widthDp to FanCoverLayerSpecs[2].heightDp)
    }

    @Test
    fun offsetsMatchTheReferenceLayout() {
        assertEquals(1 to 9, FanCoverLayerSpecs[0].offsetRightDp to FanCoverLayerSpecs[0].offsetTopDp)
        assertEquals(18 to 4, FanCoverLayerSpecs[1].offsetRightDp to FanCoverLayerSpecs[1].offsetTopDp)
        assertEquals(36 to 0, FanCoverLayerSpecs[2].offsetRightDp to FanCoverLayerSpecs[2].offsetTopDp)
    }

    @Test
    fun rotationsAlternateSoTheStackLooksFanned() {
        assertEquals(12f, FanCoverLayerSpecs[0].rotationDegrees, 0f)
        assertEquals(5f, FanCoverLayerSpecs[1].rotationDegrees, 0f)
        // 前层反向倾斜，扇形才有「张开」感；同向会看成整叠歪掉。
        assertEquals(-4f, FanCoverLayerSpecs[2].rotationDegrees, 0f)
    }

    @Test
    fun alphaIncreasesTowardTheFront() {
        val alphas = FanCoverLayerSpecs.map { it.alpha }
        assertEquals(listOf(0.35f, 0.65f, 1f), alphas)
        // 越靠前越实，这是「后面还有更多」的视觉暗示。
        assertTrue(alphas.zipWithNext().all { (a, b) -> b > a })
    }

    @Test
    fun layersGrowTowardTheFront() {
        // 前层最大、后层最小，构成层层递进的堆叠。
        assertTrue(FanCoverLayerSpecs.map { it.widthDp }.zipWithNext().all { (a, b) -> b > a })
        assertTrue(FanCoverLayerSpecs.map { it.heightDp }.zipWithNext().all { (a, b) -> b > a })
    }

    @Test
    fun eachLayerPeeksFurtherLeftThanTheOneInFront() {
        // offsetRight 递增意味着后层更靠右、前层更靠左，
        // 三层因此各露出一条边而不是完全遮住。
        val offsets = FanCoverLayerSpecs.map { it.offsetRightDp }
        assertTrue(offsets.zipWithNext().all { (a, b) -> b > a })
        assertEquals(3, offsets.toSet().size)
    }

    @Test
    fun stackAreaFitsTheLargestLayer() {
        val widest = FanCoverLayerSpecs.maxOf { it.widthDp + it.offsetRightDp }
        val tallest = FanCoverLayerSpecs.maxOf { it.heightDp + it.offsetTopDp }
        assertTrue("堆叠区宽度 ${FanStackWidth} 应容纳最宽层 $widest dp", widest <= 164)
        assertTrue("堆叠区高度 ${FanStackHeight} 应容纳最高层 $tallest dp", tallest <= 192)
    }
}
