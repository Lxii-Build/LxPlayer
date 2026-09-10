package cc.lxii.player.ui

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import cc.lxii.player.core.lyrics.LyricsRepository
import cc.lxii.player.core.player.PlayerController
import cc.lxii.player.core.source.AudioQuality
import cc.lxii.player.core.source.LocalMusicSource
import cc.lxii.player.core.source.MusicSource
import cc.lxii.player.core.source.SongUrlResult
import cc.lxii.player.data.model.Track
import cc.lxii.player.data.prefs.SettingsStore
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * 推荐卡换页与播放联动。
 *
 * 这段逻辑最容易出错：滑动推荐卡时，如果当前播放的歌恰好在推荐列表里，
 * 要顺带切换队列。参考实现按索引判断，随机播放打乱队列后就会错位，
 * 所以这里改成按稳定 id 判断——正是需要测试钉住的地方。
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class LibraryViewModelTest {

    private class FakeSource : MusicSource {
        override val id = "fake"
        override suspend fun resolve(track: Track, quality: AudioQuality): SongUrlResult =
            SongUrlResult.Failure("测试不播放", retryable = false)
    }

    private lateinit var controller: PlayerController
    private lateinit var viewModel: LibraryViewModel

    private fun track(id: String) = Track(
        id = id,
        title = "曲目 $id",
        artist = "歌手",
        album = "专辑",
        durationMs = 100_000,
        mediaUri = "content://audio/$id",
    )

    @Before
    fun setUp() {
        PlayerController.resetForTesting()
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        controller = PlayerController.get(context, FakeSource())
        viewModel = LibraryViewModel(
            source = LocalMusicSource(context),
            player = controller,
            settings = SettingsStore(context),
            lyricsRepository = LyricsRepository(context),
        )
    }

    @After
    fun tearDown() {
        PlayerController.resetForTesting()
    }

    @Test
    fun swipingUpdatesTheFeaturedIndex() {
        viewModel.onFeaturedIndexChange(3)

        assertEquals(3, viewModel.featuredIndex.value)
    }

    @Test
    fun swipingDoesNotTouchPlaybackWhenNothingIsPlaying() {
        viewModel.onFeaturedIndexChange(2)

        // 没有正在播放的曲目时，滑动只是浏览，不该凭空开始播放
        assertEquals(null, controller.currentTrack.value)
    }

    @Test
    fun swipingLeavesPlaybackAloneWhenTheCurrentSongIsNotInTheList() {
        val recommended = listOf(track("a"), track("b"), track("c"))
        viewModel.setTracksForTesting(recommended)
        // 正在播放的 outsider 不在推荐列表里
        controller.playQueue(listOf(track("outsider")), 0)

        viewModel.onFeaturedIndexChange(1)

        assertEquals("outsider", controller.currentTrack.value?.id)
        assertEquals(1, viewModel.featuredIndex.value)
    }

    @Test
    fun swipingForwardAdvancesPlaybackWhenTheCurrentSongIsInTheList() {
        val recommended = listOf(track("a"), track("b"), track("c"))
        viewModel.setTracksForTesting(recommended)
        controller.playQueue(recommended, 0)

        // 0 → 1 是前进一格，应联动到下一首
        viewModel.onFeaturedIndexChange(1)

        assertEquals(1, viewModel.featuredIndex.value)
        assertEquals("b", controller.currentTrack.value?.id)
    }

    @Test
    fun swipingBackwardStepsPlaybackBack() {
        val recommended = listOf(track("a"), track("b"), track("c"))
        viewModel.setTracksForTesting(recommended)
        controller.playQueue(recommended, 2)
        viewModel.onFeaturedIndexChange(2)

        // 2 → 1 是后退一格
        viewModel.onFeaturedIndexChange(1)

        assertEquals("b", controller.currentTrack.value?.id)
    }

    @Test
    fun wrappingForwardFromTheLastCardCountsAsForward() {
        val recommended = listOf(track("a"), track("b"), track("c"))
        viewModel.setTracksForTesting(recommended)
        controller.playQueue(recommended, 2)
        viewModel.onFeaturedIndexChange(2)

        // 2 → 0 是循环前进，不是后退
        viewModel.onFeaturedIndexChange(0)

        assertEquals("a", controller.currentTrack.value?.id)
    }

    @Test
    fun swipeStillTracksTheSongWhenShuffleReordersTheQueue() {
        val recommended = (1..6).map { track("t$it") }
        viewModel.setTracksForTesting(recommended)
        controller.playQueue(recommended, 0)
        controller.setShuffle(true)

        val before = controller.currentTrack.value?.id
        viewModel.onFeaturedIndexChange(1)
        val after = controller.currentTrack.value?.id

        // 随机播放打乱了队列顺序，但联动仍应发生（按 id 判定而非下标），
        // 且切到的是队列里的相邻曲目，不是崩溃或没反应。
        assertEquals(1, viewModel.featuredIndex.value)
        assertNotEquals("随机播放下滑动应仍能切歌", before, after)
    }

    @Test
    fun playDailyStartsFromTheTopOfTheList() {
        val tracks = listOf(track("a"), track("b"), track("c"))
        viewModel.setTracksForTesting(tracks)

        viewModel.playDaily()

        assertEquals(listOf("a", "b", "c"), controller.queue.value.map { it.id })
        assertEquals("a", controller.currentTrack.value?.id)
    }

    @Test
    fun playShuffledEnablesShuffleAndQueuesEverything() {
        val tracks = (1..7).map { track("t$it") }
        viewModel.setTracksForTesting(tracks)

        viewModel.playShuffled()

        assertEquals(true, controller.shuffleEnabled.value)
        assertEquals(tracks.size, controller.queue.value.size)
        assertEquals(
            tracks.map { it.id }.toSet(),
            controller.queue.value.map { it.id }.toSet(),
        )
    }

    @Test
    fun playFromLibraryQueuesTheWholeListAtThatTrack() {
        val tracks = listOf(track("a"), track("b"), track("c"))
        viewModel.setTracksForTesting(tracks)

        viewModel.playFromLibrary(track("c"))

        assertEquals(listOf("a", "b", "c"), controller.queue.value.map { it.id })
        assertEquals("c", controller.currentTrack.value?.id)
    }

    @Test
    fun dailyTracksSkipTheFeaturedSongToAvoidShowingItTwice() {
        val tracks = listOf(track("a"), track("b"), track("c"))
        viewModel.setTracksForTesting(tracks)

        assertEquals(listOf("b", "c"), viewModel.dailyTracks().map { it.id })
    }
}
