package cc.lxii.player.core.player

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import cc.lxii.player.core.player.policy.RepeatMode
import cc.lxii.player.core.source.AudioQuality
import cc.lxii.player.core.source.MusicSource
import cc.lxii.player.core.source.SongUrlResult
import cc.lxii.player.data.model.Track
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * 队列行为测试。
 *
 * [PlayerController] 之前完全没有测试，因为它持有 ExoPlayer。
 * 但队列变更（插入下一首、移除、重排、随机开关）只改 StateFlow，
 * 不碰播放器——这些恰好是用户最容易感知出错的部分：
 * 「下一首播放插错位置」「删掉当前歌跳到了错的歌」都会立刻被察觉。
 *
 * 这里用一个假音源避免真的解析地址，只验证队列状态机。
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class PlayerControllerQueueTest {

    private class FakeSource : MusicSource {
        override val id = "fake"
        var resolveCount = 0
        override suspend fun resolve(track: Track, quality: AudioQuality): SongUrlResult {
            resolveCount++
            // 返回失败，避免测试触碰真实播放器：本测试只关心队列状态。
            return SongUrlResult.Failure("测试不播放", retryable = false)
        }
    }

    private lateinit var controller: PlayerController
    private lateinit var source: FakeSource

    private fun track(id: String) = Track(
        id = id,
        title = "曲目 $id",
        artist = "歌手",
        album = "专辑",
        durationMs = 100_000,
        mediaUri = "content://audio/$id",
    )

    private fun ids() = controller.queue.value.map { it.id }

    @Before
    fun setUp() {
        // 播放状态是进程级的，所以 PlayerController 是单例；
        // 但测试之间必须彻底隔离，否则循环模式、随机开关这类不在队列里的状态
        // 会从上一个用例渗过来，结果随执行顺序变化。
        PlayerController.resetForTesting()
        source = FakeSource()
        controller = PlayerController.get(
            ApplicationProvider.getApplicationContext(),
            source,
        )
    }

    @After
    fun tearDown() {
        PlayerController.resetForTesting()
    }

    @Test
    fun playQueueSetsTheWholeListAndIndex() {
        controller.playQueue(listOf(track("a"), track("b"), track("c")), 1)

        assertEquals(listOf("a", "b", "c"), ids())
        assertEquals(1, controller.currentIndex.value)
        assertEquals("b", controller.currentTrack.value?.id)
    }

    @Test
    fun playQueueIgnoresAnEmptyList() {
        controller.playQueue(listOf(track("a")), 0)
        controller.playQueue(emptyList(), 0)

        // 空列表不应把已有队列清掉——那会让「点了个空歌单就没歌了」。
        assertEquals(listOf("a"), ids())
    }

    @Test
    fun playQueueClampsAnOutOfRangeStartIndex() {
        controller.playQueue(listOf(track("a"), track("b")), 99)

        assertEquals(1, controller.currentIndex.value)
        assertEquals("b", controller.currentTrack.value?.id)
    }

    @Test
    fun insertNextPutsTheTrackRightAfterCurrent() {
        controller.playQueue(listOf(track("a"), track("b"), track("c")), 0)

        controller.insertNext(track("z"))

        assertEquals(listOf("a", "z", "b", "c"), ids())
        // 当前曲目不能被插入操作改变
        assertEquals("a", controller.currentTrack.value?.id)
    }

    @Test
    fun insertNextDedupesInsteadOfDuplicating() {
        controller.playQueue(listOf(track("a"), track("b"), track("c")), 0)

        controller.insertNext(track("c"))

        assertEquals(listOf("a", "c", "b"), ids())
        assertEquals(1, controller.queue.value.count { it.id == "c" })
    }

    @Test
    fun insertNextOnEmptyQueueStartsPlaying() {
        controller.insertNext(track("solo"))

        assertEquals(listOf("solo"), ids())
        assertEquals(0, controller.currentIndex.value)
    }

    @Test
    fun addToEndAppendsWithoutChangingCurrent() {
        controller.playQueue(listOf(track("a"), track("b")), 1)

        controller.addToEnd(track("c"))

        assertEquals(listOf("a", "b", "c"), ids())
        assertEquals("b", controller.currentTrack.value?.id)
    }

    @Test
    fun addToEndSkipsTracksAlreadyQueued() {
        controller.playQueue(listOf(track("a"), track("b")), 0)

        controller.addToEnd(track("b"))

        assertEquals(listOf("a", "b"), ids())
    }

    @Test
    fun removingATrackBeforeCurrentKeepsTheSameSongPlaying() {
        controller.playQueue(listOf(track("a"), track("b"), track("c")), 2)

        controller.removeAt(0)

        assertEquals(listOf("b", "c"), ids())
        // 删的是前面的歌，正在播的必须还是 c
        assertEquals("c", controller.currentTrack.value?.id)
    }

    @Test
    fun removingTheLastTrackEmptiesTheQueueAndClearsCurrent() {
        controller.playQueue(listOf(track("only")), 0)

        controller.removeAt(0)

        assertTrue(ids().isEmpty())
        assertNull(controller.currentTrack.value)
    }

    @Test
    fun moveReordersWithoutSwitchingSongs() {
        controller.playQueue(listOf(track("a"), track("b"), track("c")), 0)

        controller.move(2, 0)

        assertEquals(listOf("c", "a", "b"), ids())
        assertEquals("a", controller.currentTrack.value?.id)
    }

    @Test
    fun shuffleKeepsEveryTrackAndPutsCurrentFirst() {
        val original = (1..8).map { track("t$it") }
        controller.playQueue(original, 3)

        controller.setShuffle(true)

        assertTrue(controller.shuffleEnabled.value)
        assertEquals(original.size, controller.queue.value.size)
        assertEquals(original.map { it.id }.toSet(), ids().toSet())
        assertEquals("t4", controller.queue.value.first().id)
    }

    @Test
    fun disablingShuffleRestoresTheOriginalOrder() {
        val original = (1..8).map { track("t$it") }
        controller.playQueue(original, 3)

        controller.setShuffle(true)
        controller.setShuffle(false)

        assertEquals(original.map { it.id }, ids())
        // 还原后当前曲目仍是原来那首
        assertEquals("t4", controller.currentTrack.value?.id)
    }

    @Test
    fun repeatModeCyclesThroughAllThreeStates() {
        assertEquals(RepeatMode.OFF, controller.repeatMode.value)

        controller.cycleRepeat()
        assertEquals(RepeatMode.ONE, controller.repeatMode.value)

        controller.cycleRepeat()
        assertEquals(RepeatMode.ALL, controller.repeatMode.value)

        controller.cycleRepeat()
        assertEquals(RepeatMode.OFF, controller.repeatMode.value)
    }

    @Test
    fun playbackSpeedIsClampedToASaneRange() {
        controller.setSpeed(9f)
        assertEquals(2.0f, controller.playbackSpeed.value, 0.001f)

        controller.setSpeed(0.01f)
        assertEquals(0.5f, controller.playbackSpeed.value, 0.001f)

        controller.setSpeed(1.25f)
        assertEquals(1.25f, controller.playbackSpeed.value, 0.001f)
    }

    @Test
    fun sleepTimerCanBeArmedAndCancelled() {
        controller.armSleepTimer(30, cc.lxii.player.core.player.policy.SleepTimerMode.COUNTDOWN)
        assertTrue(controller.sleepTimer.value != null)

        controller.cancelSleepTimer()
        assertNull(controller.sleepTimer.value)
    }
}
