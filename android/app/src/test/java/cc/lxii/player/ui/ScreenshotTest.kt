package cc.lxii.player.ui

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color as AndroidColor
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import cc.lxii.player.core.lyrics.LrcParser
import cc.lxii.player.core.player.policy.RepeatMode
import cc.lxii.player.data.model.Track
import cc.lxii.player.ui.component.GlassBottomNav
import cc.lxii.player.ui.component.LxTab
import cc.lxii.player.ui.component.MiniPlayer
import cc.lxii.player.ui.home.HomeScreen
import cc.lxii.player.ui.nowplaying.NowPlayingScreen
import cc.lxii.player.ui.theme.LxPlayerTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

/**
 * 界面渲染验证。
 *
 * 单元测试只能证明代码能编译、逻辑正确，无法证明「界面长出来了」。
 * 这里在 JVM 上真正 compose 出界面、抓取根节点位图并写成 PNG，
 * CI 把这些图作为产物上传——风格是否做出来，看图即可。
 *
 * 断言比「不崩溃」更进一步：检查画面不是单一色块。
 * 一个布局出错的界面往往渲染成纯背景色，那种情况截图看着「有图」，
 * 但其实什么都没画出来。
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-xxhdpi")
class ScreenshotTest {

    @get:Rule
    val compose = createComposeRule()

    private val demoTracks = listOf(
        track("1", "夜航星", "程之", "Sunset Drive"),
        track("2", "起风了", "买辣椒也用券", "起风了"),
        track("3", "Blue Monday", "New Order", "Substance"),
        track("4", "山海", "草东没有派对", "丑"),
        track("5", "雾里", "姚六一", "雾里"),
        track("6", "晚安", "颜人中", "晚安"),
    )

    private fun track(id: String, title: String, artist: String, album: String) = Track(
        id = id,
        title = title,
        artist = artist,
        album = album,
        durationMs = 214_000,
        mediaUri = "content://media/external/audio/media/$id",
    )

    @Test
    fun homeScreenRenders() {
        compose.setContent {
            LxPlayerTheme(darkTheme = true) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    HomeScreen(
                        state = LibraryUiState(
                            loading = false,
                            tracks = demoTracks,
                            permissionGranted = true,
                        ),
                        featuredIndex = 0,
                        currentTrackId = "2",
                        isPlaying = true,
                        likedIds = setOf("local:2", "local:4"),
                        onFeaturedIndexChange = {},
                        onPlayTrack = {},
                        onPlayDaily = {},
                        onPlayShuffled = {},
                        onToggleLike = {},
                        onRefresh = {},
                        onRequestPermission = {},
                        contentPadding = PaddingValues(bottom = 160.dp),
                    )
                }
            }
        }
        capture("home-dark")
    }

    @Test
    fun homeScreenRendersInLightTheme() {
        compose.setContent {
            LxPlayerTheme(darkTheme = false) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    HomeScreen(
                        state = LibraryUiState(
                            loading = false,
                            tracks = demoTracks,
                            permissionGranted = true,
                        ),
                        featuredIndex = 2,
                        currentTrackId = null,
                        isPlaying = false,
                        likedIds = emptySet(),
                        onFeaturedIndexChange = {},
                        onPlayTrack = {},
                        onPlayDaily = {},
                        onPlayShuffled = {},
                        onToggleLike = {},
                        onRefresh = {},
                        onRequestPermission = {},
                        contentPadding = PaddingValues(bottom = 160.dp),
                    )
                }
            }
        }
        capture("home-light")
    }

    @Test
    fun nowPlayingRendersWithLyrics() {
        val lyrics = LrcParser.parse(
            """
            [00:00.00]夜色落在窗台
            [00:04.00]风把灯影吹散
            [00:08.00]我数着远处的星
            [00:12.00]等一句还没说的话
            """.trimIndent(),
            durationMs = 214_000,
        )
        compose.setContent {
            LxPlayerTheme(darkTheme = true) {
                Surface(modifier = Modifier.fillMaxSize()) {
                NowPlayingScreen(
                    track = demoTracks[1],
                    playing = true,
                    positionMs = 92_000,
                    durationMs = 214_000,
                    repeatMode = RepeatMode.ALL,
                    shuffleEnabled = true,
                    liked = true,
                    lyrics = lyrics,
                    onTogglePlay = {},
                    onNext = {},
                    onPrevious = {},
                    onSeek = {},
                    onCycleRepeat = {},
                    onToggleShuffle = {},
                    onToggleLike = {},
                    onOpenQueue = {},
                    onCollapse = {},
                )
                }
            }
        }
        capture("now-playing")
    }

    @Test
    fun glassNavAndMiniPlayerRender() {
        compose.setContent {
            LxPlayerTheme(darkTheme = true) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    androidx.compose.foundation.layout.Column {
                        MiniPlayer(
                            track = demoTracks[0],
                            playing = true,
                            positionMs = 64_000,
                            durationMs = 214_000,
                            onTogglePlay = {},
                            onNext = {},
                            onOpenNowPlaying = {},
                            onOpenQueue = {},
                        )
                        GlassBottomNav(selected = LxTab.HOME, onSelect = {})
                    }
                }
            }
        }
        capture("chrome")
    }

    /**
     * 抓取根节点，合成到不透明底后写 PNG。
     *
     * 合成这一步是必须的：直接写 captureToImage 的位图，导出的 PNG
     * alpha 通道全为 0，用图片查看器打开是一片空白——第一版就踩了这个坑，
     * 而当时只断言「颜色种类数」，透明图照样通过，等于没验证。
     *
     * 断言分两层：
     *  1. 不透明像素必须占绝大多数（挡住「整张透明」这类失败）；
     *  2. 颜色种类要够（挡住「只画了背景色」这类布局失败）。
     */
    private fun capture(name: String) {
        compose.waitForIdle()
        val captured = compose.onRoot().captureToImage().asAndroidBitmap()

        // 铺一层不透明底再把画面画上去，得到可直接查看的图。
        val flattened = Bitmap.createBitmap(
            captured.width,
            captured.height,
            Bitmap.Config.ARGB_8888,
        )
        Canvas(flattened).apply {
            drawColor(AndroidColor.BLACK)
            drawBitmap(captured, 0f, 0f, null)
        }

        val dir = File("build/screenshots").apply { mkdirs() }
        File(dir, "$name.png").outputStream().use { out ->
            flattened.compress(Bitmap.CompressFormat.PNG, 100, out)
        }

        var opaque = 0
        var sampled = 0
        val distinct = HashSet<Int>()
        var y = 0
        while (y < captured.height) {
            var x = 0
            while (x < captured.width) {
                val pixel = captured.getPixel(x, y)
                sampled++
                if (AndroidColor.alpha(pixel) > 200) opaque++
                distinct += pixel
                x += 7
            }
            y += 7
        }

        val opaqueRatio = opaque.toDouble() / sampled
        assertTrue(
            "$name 只有 ${(opaqueRatio * 100).toInt()}% 的像素不透明，画面几乎是空的",
            opaqueRatio > 0.9,
        )
        assertTrue(
            "$name 只渲染出 ${distinct.size} 种颜色，界面可能只画了背景",
            distinct.size >= 12,
        )
        assertTrue("$name 尺寸异常", captured.width > 300 && captured.height > 300)
    }
}

