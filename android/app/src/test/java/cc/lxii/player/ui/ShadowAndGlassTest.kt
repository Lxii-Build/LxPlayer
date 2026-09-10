package cc.lxii.player.ui

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color as AndroidColor
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import cc.lxii.player.ui.component.glassSurface
import cc.lxii.player.ui.theme.LxPlayerTheme
import cc.lxii.player.ui.theme.LxRadius
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * 阴影与玻璃高光的渲染验证。
 *
 * 这两项之前只有代码在，没有断言：玻璃如果退化成纯色填充、
 * 阴影如果没渲染出来，界面会从「液态玻璃」掉成「塑料面板」，
 * 而编译和单测都不会有任何反应。
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-xxhdpi")
class ShadowAndGlassTest {

    @get:Rule
    val compose = createComposeRule()

    private fun capture(): Bitmap {
        compose.waitForIdle()
        val captured = compose.onRoot().captureToImage().asAndroidBitmap()
        val flat = Bitmap.createBitmap(captured.width, captured.height, Bitmap.Config.ARGB_8888)
        Canvas(flat).apply {
            drawColor(AndroidColor.BLACK)
            drawBitmap(captured, 0f, 0f, null)
        }
        return flat
    }

    private fun lum(bitmap: Bitmap, x: Int, y: Int): Int {
        val p = bitmap.getPixel(x, y)
        return AndroidColor.red(p) + AndroidColor.green(p) + AndroidColor.blue(p)
    }

    /**
     * 玻璃表面顶部比底部亮：那道白色高光渐变必须真的画出来。
     *
     * 只有半透明底色的面板上下亮度一致，看着像塑料。
     * 高光是玻璃质感的主要来源，所以直接比较上下缘亮度。
     */
    @Test
    fun glassSurfaceHasABrighterTopEdge() {
        compose.setContent {
            LxPlayerTheme(darkTheme = true) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color(0xFF101010)),
                ) {
                    Box(
                        modifier = Modifier
                            .padding(40.dp)
                            .size(width = 300.dp, height = 200.dp)
                            .glassSurface(shape = RoundedCornerShape(24.dp))
                            .testTag(GLASS),
                    )
                }
            }
        }
        val bitmap = capture()
        val b = compose.onNodeWithTag(GLASS).fetchSemanticsNode().boundsInRoot

        val cx = b.center.x.toInt()
        // 取内缘而非边界像素，避开描边本身
        val topY = (b.top + 6).toInt()
        val bottomY = (b.bottom - 6).toInt()

        val top = lum(bitmap, cx, topY)
        val bottom = lum(bitmap, cx, bottomY)

        assertTrue(
            "玻璃顶部应比底部亮（高光渐变），实测 top=$top bottom=$bottom",
            top > bottom + 12,
        )
    }

    /**
     * 玻璃有一圈发丝描边：边界像素比紧邻的内部更亮。
     *
     * 没有描边时面板边缘会和背景糊在一起，失去「一片玻璃」的边界感。
     */
    @Test
    fun glassSurfaceDrawsAHairlineBorder() {
        compose.setContent {
            LxPlayerTheme(darkTheme = true) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color(0xFF101010)),
                ) {
                    Box(
                        modifier = Modifier
                            .padding(40.dp)
                            .size(width = 300.dp, height = 200.dp)
                            .glassSurface(shape = RoundedCornerShape(0.dp))
                            .testTag(GLASS),
                    )
                }
            }
        }
        val bitmap = capture()
        val b = compose.onNodeWithTag(GLASS).fetchSemanticsNode().boundsInRoot

        // 在左边缘横向扫描：描边应形成一个局部亮度峰
        val y = b.center.y.toInt()
        val edgeX = b.left.toInt() + 1
        val insideX = b.left.toInt() + 14

        val edge = lum(bitmap, edgeX, y)
        val inside = lum(bitmap, insideX, y)

        assertTrue(
            "左边缘应有描边亮线，实测 edge=$edge inside=$inside",
            edge > inside,
        )
    }

    /**
     * 阴影真的渲染在卡片之外。
     *
     * 在纯黑背景上放一张带阴影的亮色卡片，卡片外侧紧邻区域应比远处更亮
     * ——那就是阴影的扩散。写了 shadow 但形状没传对时阴影会消失。
     */
    @Test
    fun cardShadowSpreadsOutsideTheCard() {
        compose.setContent {
            LxPlayerTheme(darkTheme = true) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.Black),
                ) {
                    Box(
                        modifier = Modifier
                            .padding(60.dp)
                            .size(200.dp)
                            .androidxShadow()
                            .background(Color.White, RoundedCornerShape(LxRadius.cover))
                            .testTag(CARD),
                    )
                }
            }
        }
        val bitmap = capture()
        val b = compose.onNodeWithTag(CARD).fetchSemanticsNode().boundsInRoot

        val cx = b.center.x.toInt()
        val justBelow = (b.bottom + 6).toInt().coerceAtMost(bitmap.height - 1)
        val farBelow = (b.bottom + 50).toInt().coerceAtMost(bitmap.height - 1)

        val near = lum(bitmap, cx, justBelow)
        val far = lum(bitmap, cx, farBelow)

        assertTrue(
            "卡片下方应有阴影扩散，实测 near=$near far=$far",
            near > far,
        )
    }

    /**
     * 圆角把四角真的裁掉了。
     *
     * 用一张纯白卡片验证：角落应是背景色，中心应是白色。
     * clip 漏掉时角落会被填满，圆角形同虚设。
     */
    @Test
    fun roundedCornersActuallyClipTheCorners() {
        compose.setContent {
            LxPlayerTheme(darkTheme = true) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.Black),
                ) {
                    Box(
                        modifier = Modifier
                            .size(200.dp)
                            .background(Color.White, RoundedCornerShape(LxRadius.featuredCard))
                            .testTag(CARD),
                    )
                }
            }
        }
        val bitmap = capture()
        val b = compose.onNodeWithTag(CARD).fetchSemanticsNode().boundsInRoot

        val center = lum(bitmap, b.center.x.toInt(), b.center.y.toInt())
        // 28dp 圆角 = 84px，贴角 4px 必然落在圆弧之外
        val corner = lum(bitmap, b.left.toInt() + 4, b.top.toInt() + 4)

        assertTrue("卡片中心应为白色，实测 $center", center > 700)
        assertTrue("28dp 圆角应把左上角裁掉，实测 $corner", corner < 100)
    }

    private companion object {
        const val GLASS = "glass-surface"
        const val CARD = "shadow-card"
    }
}

/**
 * 测试用阴影：与卡片实际使用的参数同量级。
 *
 * 阴影色用白色而非默认黑：纯黑背景上黑色阴影不可见，
 * 测不出「阴影有没有渲染」。
 */
private fun Modifier.androidxShadow(): Modifier = this.shadow(
    elevation = 20.dp,
    shape = RoundedCornerShape(LxRadius.cover),
    ambientColor = Color.White,
    spotColor = Color.White,
)
