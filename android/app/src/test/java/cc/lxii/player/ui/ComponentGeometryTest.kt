package cc.lxii.player.ui

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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import cc.lxii.player.core.lyrics.LrcParser
import cc.lxii.player.data.model.Track
import cc.lxii.player.ui.component.EqBars
import cc.lxii.player.ui.component.MiniPlayer
import cc.lxii.player.ui.home.HeroSection
import cc.lxii.player.ui.nowplaying.LyricsPane
import cc.lxii.player.ui.theme.LxPlayerTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * 其余组件的行为与几何断言。
 *
 * 补上 Hero 区、歌词、迷你播放器、均衡器——这些之前只有代码在，
 * 没有任何测试守着，改坏了不会有人知道。
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-xxhdpi")
class ComponentGeometryTest {

    @get:Rule
    val compose = createComposeRule()

    private fun track(id: String, title: String = "曲目 $id") = Track(
        id = id,
        title = title,
        artist = "歌手 $id",
        album = "专辑 $id",
        durationMs = 200_000,
        mediaUri = "content://media/external/audio/media/$id",
    )

    /** Hero 区两张卡都要出现，且每日推荐在私人 FM 之上。 */
    @Test
    fun heroSectionShowsBothCardsInOrder() {
        val tracks = (1..6).map { track(it.toString()) }
        compose.setContent {
            LxPlayerTheme(darkTheme = true) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    HeroSection(tracks = tracks, onPlayDaily = {}, onPlayShuffled = {})
                }
            }
        }
        compose.waitForIdle()

        val daily = compose.onNodeWithText("每日推荐").fetchSemanticsNode().boundsInRoot
        val fm = compose.onNodeWithText("私人 FM").fetchSemanticsNode().boundsInRoot

        assertTrue(
            "每日推荐应在私人 FM 上方（daily.top=${daily.top} fm.top=${fm.top}）",
            daily.top < fm.top,
        )
        // 每日推荐是主卡，标题字号更大，占的高度应明显更高
        assertTrue("每日推荐标题应更大", daily.height > fm.height)
    }

    /** 曲目数量要如实显示，不能写死。 */
    @Test
    fun heroSectionReportsTheRealTrackCount() {
        val tracks = (1..17).map { track(it.toString()) }
        compose.setContent {
            LxPlayerTheme(darkTheme = true) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    HeroSection(tracks = tracks, onPlayDaily = {}, onPlayShuffled = {})
                }
            }
        }
        compose.waitForIdle()
        compose.onNodeWithText("17 首本地音乐").assertExists()
        compose.onNodeWithText("共 17 首").assertExists()
    }

    /**
     * 当前歌词行比其他行更亮更大。
     *
     * 这是歌词区唯一的焦点手段（不给非当前行上色，避免和取色背景打架），
     * 所以必须验证：同一时刻只有一行是「白且大」的。
     */
    @Test
    fun activeLyricLineIsLargerThanTheRest() {
        val lyrics = LrcParser.parse(
            """
            [00:00.00]第一行
            [00:10.00]第二行
            [00:20.00]第三行
            """.trimIndent(),
            durationMs = 30_000,
        )
        compose.setContent {
            LxPlayerTheme(darkTheme = true) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    LyricsPane(lines = lyrics, positionMs = 12_000, onSeekTo = {})
                }
            }
        }
        compose.waitForIdle()

        val second = compose.onNodeWithText("第二行").fetchSemanticsNode().boundsInRoot
        val third = compose.onNodeWithText("第三行").fetchSemanticsNode().boundsInRoot

        // 12 秒时第二行是当前行：22sp vs 18sp，高度必须更大
        assertTrue(
            "当前行应比非当前行高（second=${second.height} third=${third.height}）",
            second.height > third.height,
        )
    }

    /** 没有歌词时给出明确空态，而不是一片空白。 */
    @Test
    fun emptyLyricsShowAnExplicitMessage() {
        compose.setContent {
            LxPlayerTheme(darkTheme = true) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    LyricsPane(lines = emptyList(), positionMs = 0, onSeekTo = {})
                }
            }
        }
        compose.waitForIdle()
        compose.onNodeWithText("没有找到歌词").assertExists()
    }

    /** 迷你播放器无当前曲目时不占位。 */
    @Test
    fun miniPlayerRendersNothingWithoutATrack() {
        compose.setContent {
            LxPlayerTheme(darkTheme = true) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    MiniPlayer(
                        track = null,
                        playing = false,
                        positionMs = 0,
                        durationMs = 0,
                        onTogglePlay = {},
                        onNext = {},
                        onOpenNowPlaying = {},
                        onOpenQueue = {},
                    )
                }
            }
        }
        compose.waitForIdle()
        val bitmap = compose.onRoot().captureToImage().asAndroidBitmap()

        // 整屏应只有 Surface 背景色，没有胶囊
        val distinct = HashSet<Int>()
        var y = 0
        while (y < bitmap.height && distinct.size < 4) {
            var x = 0
            while (x < bitmap.width) {
                distinct += bitmap.getPixel(x, y)
                x += 16
            }
            y += 16
        }
        assertTrue("无曲目时不应画出胶囊，实测 ${distinct.size} 种颜色", distinct.size <= 3)
    }

    /** 迷你播放器有曲目时显示标题与歌手。 */
    @Test
    fun miniPlayerShowsTitleAndArtist() {
        compose.setContent {
            LxPlayerTheme(darkTheme = true) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    MiniPlayer(
                        track = track("9", title = "夜航星"),
                        playing = true,
                        positionMs = 40_000,
                        durationMs = 200_000,
                        onTogglePlay = {},
                        onNext = {},
                        onOpenNowPlaying = {},
                        onOpenQueue = {},
                    )
                }
            }
        }
        compose.waitForIdle()
        compose.onNodeWithText("夜航星").assertExists()
        compose.onNodeWithText("歌手 9").assertExists()
    }

    /**
     * 均衡器画出三根独立的竖条。
     *
     * 判据是横向存在「亮—暗—亮—暗—亮」的交替：三根条之间必须有空隙。
     * 如果画成一整块（比如忘了留 gap），这个断言会失败。
     */
    @Test
    fun eqBarsRenderThreeSeparateBars() {
        compose.setContent {
            LxPlayerTheme(darkTheme = true) {
                Box(modifier = Modifier.background(Color.Black)) {
                    EqBars(
                        playing = false,
                        color = Color.White,
                        modifier = Modifier.testTag(EQ_TAG),
                    )
                }
            }
        }
        compose.waitForIdle()

        // 按组件自身的实际边界取样。
        // 之前固定用 bitmap.height-3，那一行落在 EqBars（默认 14dp）下方的空白里，
        // 统计到 0 段——测的是背景，不是组件。
        val bounds = compose.onNodeWithTag(EQ_TAG).fetchSemanticsNode().boundsInRoot
        val bitmap = compose.onRoot().captureToImage().asAndroidBitmap()

        // 三根条贴底生长，静止高度最低一档是 0.2，所以在靠底部取样最稳。
        val y = (bounds.bottom - 2).toInt().coerceIn(0, bitmap.height - 1)
        val left = bounds.left.toInt().coerceAtLeast(0)
        val right = bounds.right.toInt().coerceAtMost(bitmap.width)

        var segments = 0
        var inBar = false
        var x = left
        while (x < right) {
            val bright = AndroidColor.red(bitmap.getPixel(x, y)) > 100
            if (bright && !inBar) segments++
            inBar = bright
            x++
        }
        assertTrue(
            "均衡器应画出 3 根分离的竖条，实测 $segments 段（取样 y=$y, x=$left..$right）",
            segments == 3,
        )
    }

    private companion object {
        const val EQ_TAG = "eq-bars"
    }

}
