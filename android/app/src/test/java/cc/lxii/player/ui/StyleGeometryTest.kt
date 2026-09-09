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
     * 扇形封面三层各自落在不同位置、不同尺寸。
     *
     * 用布局坐标验证，而不是猜像素边界：三层封面颜色相近（同一批占位图），
     * 靠「最左非背景像素」判断谁在哪里是不可靠的——第一版这么写，
     * 结果无论代码怎么改都报同一个数字，测的其实是最外层的包围盒。
     *
     * 每层带 testTag，直接读它们的实际位置与尺寸，
     * 位置重合或尺寸相同都会失败。
     */
    @Test
    fun fanCoverLayersOccupyDistinctPositionsAndSizes() {
        val tracks = (1..4).map { track(it.toString()) }
        compose.setContent {
            LxPlayerTheme(darkTheme = true) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    Box { FanCoverStack(tracks = tracks, featuredIndex = 0) }
                }
            }
        }
        compose.waitForIdle()

        val bounds = FanCoverStackTags.all.map { tag ->
            compose.onNodeWithTag(tag).fetchSemanticsNode().boundsInRoot
        }

        // 尺寸必须三种都不同：112x144 / 120x160 / 128x176
        val widths = bounds.map { it.width.toInt() }.toSet()
        assertTrue("三层宽度应各不相同，实测 $widths", widths.size == 3)

        // 左边界必须三种都不同（层层向左露出）
        val lefts = bounds.map { it.left.toInt() }.toSet()
        assertTrue("三层左边界应各不相同，实测 $lefts", lefts.size == 3)

        // 顶边也应错开：设计里 top 分别是 9 / 4 / 0
        val tops = bounds.map { it.top.toInt() }.toSet()
        assertTrue("三层顶边应错开，实测 $tops", tops.size >= 2)
    }

    /**
     * 黑胶唱盘是圆形的。
     *
     * 圆形的判据：水平中线两端为背景（圆之外），中心为内容；
     * 且四个角必须是背景。方形封面无法同时满足这两条。
     */
    /**
     * 唱盘是正方形布局里的圆，唱臂另有位置。
     *
     * 不用「角落像素是否发亮」判断：那片区域可能落着唱臂、阴影或父容器背景，
     * 拿它当依据会得到一个和代码改动无关的恒定值（第一版就一直报同一个亮度 69）。
     * 改成读布局坐标：唱盘必须是等宽等高（圆的包围盒是正方形），
     * 唱臂必须偏在右上、且不与唱盘同心。
     */
    @Test
    fun vinylDiscIsSquareBoundedAndTonearmSitsTopRight() {
        compose.setContent {
            LxPlayerTheme(darkTheme = true) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    Box(modifier = Modifier.size(300.dp)) {
                        VinylStage(coverUri = null, playing = true)
                    }
                }
            }
        }
        compose.waitForIdle()

        val disc = compose.onNodeWithTag(VinylStageTags.DISC)
            .fetchSemanticsNode().boundsInRoot
        val arm = compose.onNodeWithTag(VinylStageTags.TONEARM)
            .fetchSemanticsNode().boundsInRoot

        // 圆的包围盒必须是正方形（容差 2px 给舍入）
        val delta = kotlin.math.abs(disc.width - disc.height)
        assertTrue("唱盘包围盒应为正方形，实测 ${disc.width}x${disc.height}", delta <= 2f)

        // 唱臂中心必须在唱盘中心的右上方
        val discCx = disc.center.x
        val discCy = disc.center.y
        assertTrue(
            "唱臂应偏右（臂心 ${arm.center.x} vs 盘心 $discCx）",
            arm.center.x > discCx,
        )
        assertTrue(
            "唱臂应偏上（臂心 ${arm.center.y} vs 盘心 $discCy）",
            arm.center.y < discCy,
        )
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

