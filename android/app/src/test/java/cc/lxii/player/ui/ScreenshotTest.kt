package cc.lxii.player.ui

import android.graphics.Bitmap
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
     * 抓取根节点并写 PNG。
     *
     * 同时断言画面里至少有 8 种不同颜色：布局失败的界面通常只剩背景色，
     * 那种截图「看起来有图」，实际什么都没画。
     */
    private fun capture(name: String) {
        compose.waitForIdle()
        val bitmap = compose.onRoot().captureToImage().asAndroidBitmap()

        val dir = File("build/screenshots").apply { mkdirs() }
        File(dir, "$name.png").outputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        }

        val distinct = HashSet<Int>()
        var y = 0
        while (y < bitmap.height && distinct.size < 32) {
            var x = 0
            while (x < bitmap.width) {
                distinct += bitmap.getPixel(x, y)
                x += 7
            }
            y += 7
        }
        assertTrue(
            "$name 只渲染出 ${distinct.size} 种颜色，界面可能是空的",
            distinct.size >= 8,
        )
        assertTrue("$name 尺寸异常", bitmap.width > 300 && bitmap.height > 300)
    }
}

