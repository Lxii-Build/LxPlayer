package cc.lxii.player.ui.login

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color as AndroidColor
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import cc.lxii.player.ui.theme.LxPlayerTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * 登录页视觉与行为。
 *
 * 旧版登录页是纵向堆控件，被指「太简单」。重做后这里守住新设计的要点：
 * 品牌区是圆形发光徽章、分段控件二选一、按钮尺寸与禁用态、
 * 错误以卡片而非裸红字呈现。
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-xxhdpi")
class LoginScreenTest {

    @get:Rule
    val compose = createComposeRule()

    private fun render(
        busy: Boolean = false,
        error: String? = null,
        onSubmit: (String, String, Boolean) -> Unit = { _, _, _ -> },
        onBack: () -> Unit = {},
    ) {
        compose.setContent {
            LxPlayerTheme(darkTheme = true) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    LoginScreen(
                        busy = busy,
                        error = error,
                        onSubmit = onSubmit,
                        onBack = onBack,
                        // 关掉入场动画，否则断言可能落在动画中途的尺寸上。
                        animateBrand = false,
                    )
                }
            }
        }
        compose.waitForIdle()
    }

    @Test
    fun brandMarkIsASquareBoundedCircleAtTheDesignSize() {
        render()
        val brand = compose.onNodeWithTag(LoginBrandMarkTags.ROOT)
            .fetchSemanticsNode().boundsInRoot

        // 圆的包围盒必须是正方形，否则渲染出来是椭圆
        assertTrue(
            "品牌区应为正方形包围盒，实测 ${brand.width}x${brand.height}",
            kotlin.math.abs(brand.width - brand.height) <= 2f,
        )
        // 140dp @ xxhdpi = 420px
        assertEquals(420f, brand.width, 3f)
    }

    @Test
    fun brandGlowIsCenteredHorizontally() {
        render()
        val root = compose.onRoot().fetchSemanticsNode().boundsInRoot
        val brand = compose.onNodeWithTag(LoginBrandMarkTags.GLOW)
            .fetchSemanticsNode().boundsInRoot

        val rootCenter = root.center.x
        val brandCenter = brand.center.x
        assertTrue(
            "品牌区应水平居中（root=$rootCenter brand=$brandCenter）",
            kotlin.math.abs(rootCenter - brandCenter) < 8f,
        )
    }

    @Test
    fun submitButtonMatchesTheDesignSize() {
        render()
        val button = compose.onNodeWithTag(LoginTags.SUBMIT)
            .fetchSemanticsNode().boundsInRoot

        // 54dp @ xxhdpi = 162px
        assertEquals(162f, button.height, 3f)
        // 按钮应占满内容宽度（左右各 28dp padding → 411-56=355dp）
        assertTrue("按钮应接近满宽，实测 ${button.width}", button.width > 1000f)
    }

    @Test
    fun submitStaysDisabledUntilBothFieldsAreValid() {
        var submitted = false
        render(onSubmit = { _, _, _ -> submitted = true })

        compose.onNodeWithTag(LoginTags.SUBMIT).performClick()
        assertTrue("空表单不应可提交", !submitted)

        compose.onNodeWithTag(LoginTags.EMAIL).performTextInput("a@example.com")
        compose.onNodeWithTag(LoginTags.SUBMIT).performClick()
        assertTrue("只填邮箱不应可提交", !submitted)

        // 密码不足 8 位仍不可提交
        compose.onNodeWithTag(LoginTags.PASSWORD).performTextInput("short")
        compose.onNodeWithTag(LoginTags.SUBMIT).performClick()
        assertTrue("密码不足 $MIN_PASSWORD_LENGTH 位不应可提交", !submitted)
    }

    @Test
    fun submitFiresOnceBothFieldsAreValid() {
        var email: String? = null
        var password: String? = null
        var register: Boolean? = null
        render(onSubmit = { e, p, r -> email = e; password = p; register = r })

        compose.onNodeWithTag(LoginTags.EMAIL).performTextInput("  a@example.com  ")
        compose.onNodeWithTag(LoginTags.PASSWORD).performTextInput("password12")
        compose.onNodeWithTag(LoginTags.SUBMIT).performClick()

        // 邮箱应被 trim：用户复制粘贴时常带空格
        assertEquals("a@example.com", email)
        assertEquals("password12", password)
        assertEquals(false, register)
    }

    @Test
    fun switchingToRegisterChangesTheHeadline() {
        render()
        compose.onNodeWithText("登录 LxPlayer").assertIsDisplayed()

        compose.onNodeWithTag(LoginTags.MODE_REGISTER).performClick()
        compose.waitForIdle()

        // 标题用整句匹配：「注册」两个字同时出现在分段控件和按钮上，
        // 按文字找会命中多个节点。
        compose.onNodeWithText("创建账号").assertIsDisplayed()
        compose.onNodeWithTag(LoginTags.SUBMIT).assertIsDisplayed()
    }

    @Test
    fun theBottomHintAlsoSwitchesMode() {
        render()

        // 底部提示必须可点：读到那句话时手已经在屏幕下方了
        compose.onNodeWithTag(LoginTags.TOGGLE_HINT).performClick()
        compose.waitForIdle()

        compose.onNodeWithText("创建账号").assertIsDisplayed()
    }

    @Test
    fun registerModeShowsThePasswordLengthHint() {
        render()
        compose.onNodeWithTag(LoginTags.MODE_REGISTER).performClick()
        compose.waitForIdle()

        compose.onNodeWithText("至少 $MIN_PASSWORD_LENGTH 位").assertIsDisplayed()
    }

    @Test
    fun errorIsShownInsideACardNotAsBareText() {
        render(error = "邮箱或密码不正确")
        compose.waitForIdle()

        val card = compose.onNodeWithTag(LoginTags.ERROR)
            .fetchSemanticsNode().boundsInRoot
        val text = compose.onNodeWithText("邮箱或密码不正确")
            .fetchSemanticsNode().boundsInRoot

        // 卡片必须比里面的文字宽出内边距，否则就是裸文字而非卡片。
        assertTrue(
            "错误应以卡片承载：卡片宽 ${card.width} 应明显大于文字宽 ${text.width}",
            card.width > text.width + 40f,
        )
        compose.onNodeWithText("邮箱或密码不正确").assertIsDisplayed()
    }

    @Test
    fun busyStateLocksEveryInteractiveControl() {
        var submitted = false
        render(busy = true, onSubmit = { _, _, _ -> submitted = true })

        // 请求进行中，输入框应被禁用——此时改邮箱不影响已发出的请求。
        compose.onNodeWithTag(LoginTags.EMAIL).assertIsNotEnabled()
        compose.onNodeWithTag(LoginTags.PASSWORD).assertIsNotEnabled()

        // 模式切换也要锁住，否则界面看起来切了但请求还是原来那个。
        compose.onNodeWithTag(LoginTags.MODE_REGISTER).performClick()
        compose.waitForIdle()
        compose.onNodeWithText("登录 LxPlayer").assertIsDisplayed()

        // 按钮仍在原位（不是消失），但点不动。
        compose.onNodeWithTag(LoginTags.SUBMIT).performClick()
        compose.onNodeWithTag(LoginTags.SUBMIT).assertIsDisplayed()
        assertTrue("忙碌态不应再次提交", !submitted)
    }

    @Test
    fun backButtonIsReachable() {
        var backed = false
        render(onBack = { backed = true })

        compose.onNodeWithTag(LoginTags.BACK).performClick()
        assertTrue("返回按钮应可点", backed)
    }

    /**
     * 背景不是一块死平的纯色：右上角那团主色光必须真的画出来。
     */
    @Test
    fun backgroundCarriesARadialGlowTowardTheTopRight() {
        render()
        val captured = compose.onRoot().captureToImage().asAndroidBitmap()
        val flat = Bitmap.createBitmap(
            captured.width,
            captured.height,
            Bitmap.Config.ARGB_8888,
        )
        Canvas(flat).apply {
            drawColor(AndroidColor.BLACK)
            drawBitmap(captured, 0f, 0f, null)
        }

        fun lum(x: Int, y: Int): Int {
            val p = flat.getPixel(x, y)
            return AndroidColor.red(p) + AndroidColor.green(p) + AndroidColor.blue(p)
        }

        // 右上角应比左下角亮（径向光中心在右上）
        val topRight = lum(flat.width - 12, 12)
        val bottomLeft = lum(12, flat.height - 12)
        assertTrue(
            "右上角应有主色光，实测 topRight=$topRight bottomLeft=$bottomLeft",
            topRight > bottomLeft,
        )
    }

    @Test
    fun designMetricsMatchTheReferenceValues() {
        assertEquals(16f, LoginMetrics.fieldRadius.value, 0f)
        assertEquals(12f, LoginMetrics.fieldIconTileRadius.value, 0f)
        assertEquals(2f, LoginMetrics.focusedBorderWidth.value, 0f)
        assertEquals(1f, LoginMetrics.idleBorderWidth.value, 0f)
        assertEquals(54f, LoginMetrics.buttonHeight.value, 0f)
        assertEquals(20f, LoginMetrics.buttonRadius.value, 0f)
        assertEquals(140f, LoginMetrics.brandSize.value, 0f)
        // 内圈必须小于外圈，否则描边压在渐变边缘上看不出层次
        assertTrue(LoginMetrics.brandRingSize.value < LoginMetrics.brandSize.value)
        // focus 描边必须比静止态粗，这是焦点提示的全部依据
        assertTrue(
            LoginMetrics.focusedBorderWidth.value > LoginMetrics.idleBorderWidth.value,
        )
    }
}
