package cc.lxii.player.ui

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color as AndroidColor
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import cc.lxii.player.data.model.Track
import cc.lxii.player.ui.component.CoverCard
import cc.lxii.player.ui.component.GlassBottomNav
import cc.lxii.player.ui.component.LxTab
import cc.lxii.player.ui.home.FanCoverStack
import cc.lxii.player.ui.nowplaying.VinylStage
import cc.lxii.player.ui.theme.LxPlayerTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * 风格特征的几何断言。
 *
 * 截图能证明「界面画出来了」，但证明不了「圆角是不是圆的、唱盘是不是圆形、
 * 扇形封面有没有错开」。这里直接检查渲染结果的像素几何：
 * 拐角是否被裁掉、形状是否呈圆形、层与层是否有位移。
 *
 * 这比肉眼看截图更严格——肉眼容易漏掉几个 dp 的偏差，
 * 而这些断言会在圆角丢失或层级重叠时直接失败。
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-xxhdpi")
class StyleGeometryTest {

    @get:Rule
    val compose = createComposeRule()

    private fun track(id: String) = Track(
        id = id,
        title = "测试曲目 $id",
        artist = "测试歌手",
        album = "测试专辑",
        durationMs = 200_000,
        mediaUri = "content://media/external/audio/media/$id",
    )

    private fun render(content: @androidx.compose.runtime.Composable () -> Unit): Frame {
        compose.setContent {
            LxPlayerTheme(darkTheme = true) {
                Surface(modifier = Modifier.fillMaxSize()) { content() }
            }
        }
        compose.waitForIdle()
        val captured = compose.onRoot().captureToImage().asAndroidBitmap()
        val flat = Bitmap.createBitmap(captured.width, captured.height, Bitmap.Config.ARGB_8888)
        Canvas(flat).apply {
            drawColor(AndroidColor.BLACK)
            drawBitmap(captured, 0f, 0f, null)
        }
        return Frame(flat)
    }

    private class Frame(val bitmap: Bitmap) {
        fun pixel(x: Int, y: Int): Int = bitmap.getPixel(x, y)

        /** 某个矩形区域内的不同颜色数，用来判断「这里有没有东西」。 */
        fun colorCount(left: Int, top: Int, right: Int, bottom: Int): Int {
            val seen = HashSet<Int>()
            var y = top
            while (y < bottom) {
                var x = left
                while (x < right) {
                    seen += bitmap.getPixel(x, y)
                    x += 2
                }
                y += 2
            }
            return seen.size
        }

        /** 区域内非背景（非纯黑）像素占比。 */
        fun inkRatio(left: Int, top: Int, right: Int, bottom: Int): Double {
            var ink = 0
            var total = 0
            var y = top
            while (y < bottom) {
                var x = left
                while (x < right) {
                    val p = bitmap.getPixel(x, y)
                    total++
                    val lum = AndroidColor.red(p) + AndroidColor.green(p) + AndroidColor.blue(p)
                    if (lum > 24) ink++
                    x += 2
                }
                y += 2
            }
            return if (total == 0) 0.0 else ink.toDouble() / total
        }
    }

    /**
     * 圆角是真的圆角。
     *
     * 在一块纯色方块上套 20dp 圆角，四个角必须露出底色。
     * 如果 clip 没生效（写成 background 却忘了 clip 是常见错误），
     * 角落会被填满，这个断言就会失败。
     */
    @Test
    fun coverCardCornersAreRounded() {
        val frame = render {
            Box(modifier = Modifier.fillMaxSize()) {
                CoverCard(track = track("1"), onClick = {}, width = 200.dp)
            }
        }
        // 封面从 (0,0) 起画，边长 200dp。xxhdpi 下 1dp = 3px。
        val side = 200 * 3
        val corner = 4 // 贴角取样，圆角半径 20dp=60px，这里必然在圆弧之外
        val cornerPixel = frame.pixel(corner, corner)
        val centerPixel = frame.pixel(side / 2, side / 2)

        val cornerLum = AndroidColor.red(cornerPixel) + AndroidColor.green(cornerPixel) +
            AndroidColor.blue(cornerPixel)
        val centerLum = AndroidColor.red(centerPixel) + AndroidColor.green(centerPixel) +
            AndroidColor.blue(centerPixel)

        assertTrue(
            "左上角亮度 $cornerLum 应明显低于中心 $centerLum —— 圆角没有裁出来",
            cornerLum < centerLum,
        )
    }

    /**
     * 扇形封面三层是错开的，不是叠在一起。
     *
     * 按设计，后层在 right=1、中层 right=18、前层 right=36，
     * 每层尺寸也不同。若三层完全重合，右侧边缘只会出现一条竖直分界；
     * 错开时右半区会出现多个层次的边界，颜色数明显更多。
     */
    @Test
    fun fanCoverLayersAreOffsetFromEachOther() {
        val tracks = (1..4).map { track(it.toString()) }
        val frame = render {
            Box(modifier = Modifier.fillMaxSize()) {
                FanCoverStack(tracks = tracks, featuredIndex = 0)
            }
        }
        // 堆叠区 160x192dp = 480x576px
        val ink = frame.inkRatio(0, 0, 480, 576)
        assertTrue("扇形封面区几乎空白（ink=$ink）", ink > 0.25)

        // 三层错开会在纵向不同高度产生不同的左边界：
        // 逐行找最左侧非背景像素，若三层重合则这个值几乎恒定。
        val leftEdges = mutableListOf<Int>()
        var y = 20
        while (y < 560) {
            var x = 0
            var found = -1
            while (x < 480) {
                val p = frame.pixel(x, y)
                val lum = AndroidColor.red(p) + AndroidColor.green(p) + AndroidColor.blue(p)
                if (lum > 24) { found = x; break }
                x += 2
            }
            if (found >= 0) leftEdges += found
            y += 20
        }
        val distinctEdges = leftEdges.toSet().size
        assertTrue(
            "左边界只有 $distinctEdges 种取值，三层封面可能完全重合（应因错开与旋转产生多种）",
            distinctEdges >= 3,
        )
    }

    /**
     * 黑胶唱盘是圆形的。
     *
     * 圆形的判据：水平中线两端为背景（圆之外），中心为内容；
     * 且四个角必须是背景。方形封面无法同时满足这两条。
     */
    @Test
    fun vinylStageRendersAsACircle() {
        val frame = render {
            Box(modifier = Modifier.size(300.dp)) {
                VinylStage(coverUri = null, playing = true)
            }
        }
        val side = 300 * 3
        fun lum(x: Int, y: Int): Int {
            val p = frame.pixel(x, y)
            return AndroidColor.red(p) + AndroidColor.green(p) + AndroidColor.blue(p)
        }

        val center = lum(side / 2, side / 2)
        // 只查左侧与右下三角：右上角被唱臂占据，唱臂本来就该画在那里，
        // 拿它判断「圆外无内容」会把正确实现判成缺陷。
        val topLeft = lum(6, 6)
        val bottomLeft = lum(6, side - 6)
        val bottomRight = lum(side - 6, side - 6)

        assertTrue("唱盘中心应有内容，实测亮度 $center", center > 24)
        assertTrue("左上角应在圆外（亮度 $topLeft）", topLeft < 24)
        assertTrue("左下角应在圆外（亮度 $bottomLeft）", bottomLeft < 24)
        assertTrue("右下角应在圆外（亮度 $bottomRight）", bottomRight < 24)
    }

    /**
     * 玻璃导航是半透明的：能透出身后的颜色。
     *
     * 在导航后面铺一块高饱和底色，导航区域的像素必须带上那个色偏。
     * 若玻璃写成了不透明填充，导航区会是纯灰，红色分量不会升高。
     */
    @Test
    fun glassNavLetsBackgroundColorThrough() {
        val frame = render {
            Box(modifier = Modifier.fillMaxSize()) {
                // 身后铺满强红色，用来检验玻璃是否真的透光
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color(0xFFB03030)),
                )
                GlassBottomNav(selected = LxTab.HOME, onSelect = {})
            }
        }
        // 导航条约在容器顶部（Box 内 GlassBottomNav 自身高 68dp + padding）
        var reddish = 0
        var sampled = 0
        var y = 30
        while (y < 200) {
            var x = 120
            while (x < 1100) {
                val p = frame.pixel(x, y)
                sampled++
                if (AndroidColor.red(p) > AndroidColor.blue(p) + 12) reddish++
                x += 8
            }
            y += 8
        }
        val ratio = reddish.toDouble() / sampled
        assertTrue(
            "导航区只有 ${(ratio * 100).toInt()}% 的像素透出背景红色，玻璃可能是不透明的",
            ratio > 0.30,
        )
    }
}

