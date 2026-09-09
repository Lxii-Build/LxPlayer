package cc.lxii.player.core.player.policy

import cc.lxii.player.data.model.Track
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class QueuePolicyTest {

    private fun track(id: String) = Track(
        id = id,
        title = "title-$id",
        artist = "artist",
        album = "album",
        durationMs = 1_000L,
        mediaUri = "file:///music/$id.mp3",
    )

    private fun ids(queue: List<Track>) = queue.map { it.id }

    @Test
    fun insertNext_onEmptyQueue_startsPlayingThatTrack() {
        val result = QueuePolicy.insertNext(emptyList(), currentIndex = -1, track = track("a"))

        assertEquals(listOf("a"), ids(result.queue))
        assertEquals(0, result.currentIndex)
    }

    @Test
    fun insertNext_placesTrackRightAfterCurrent() {
        val queue = listOf(track("a"), track("b"), track("c"))

        val result = QueuePolicy.insertNext(queue, currentIndex = 0, track = track("z"))

        assertEquals(listOf("a", "z", "b", "c"), ids(result.queue))
        assertEquals(0, result.currentIndex)
    }

    @Test
    fun insertNext_dedupesInsteadOfAddingSecondCopy() {
        val queue = listOf(track("a"), track("b"), track("c"))

        val result = QueuePolicy.insertNext(queue, currentIndex = 0, track = track("c"))

        assertEquals(listOf("a", "c", "b"), ids(result.queue))
        assertEquals(1, result.queue.count { it.id == "c" })
    }

    @Test
    fun insertNext_shiftsInsertPointWhenExistingCopyIsBeforeIt() {
        // b 在插入点(下标2)之前；移除它会让插入点左移一格，若不补偿就会插到 d 之后。
        val queue = listOf(track("b"), track("a"), track("c"), track("d"))

        val result = QueuePolicy.insertNext(queue, currentIndex = 1, track = track("b"))

        assertEquals(listOf("a", "b", "c", "d"), ids(result.queue))
        assertEquals("b", result.queue[1].id)
    }

    @Test
    fun insertNext_keepsCurrentTrackEvenWhenIndexesShift() {
        val queue = listOf(track("x"), track("a"), track("b"))

        val result = QueuePolicy.insertNext(queue, currentIndex = 1, track = track("x"))

        assertEquals("a", result.queue[result.currentIndex].id)
    }

    @Test
    fun addToEnd_appendsAndKeepsCurrentIndex() {
        val queue = listOf(track("a"), track("b"))

        val result = QueuePolicy.addToEnd(queue, currentIndex = 1, track = track("c"))

        assertEquals(listOf("a", "b", "c"), ids(result.queue))
        assertEquals(1, result.currentIndex)
    }

    @Test
    fun addToEnd_ignoresTrackAlreadyQueued() {
        val queue = listOf(track("a"), track("b"))

        val result = QueuePolicy.addToEnd(queue, currentIndex = 0, track = track("b"))

        assertEquals(listOf("a", "b"), ids(result.queue))
    }

    @Test
    fun removeCurrent_leavesPointerOnWhatWasNext() {
        val queue = listOf(track("a"), track("b"), track("c"))

        val result = QueuePolicy.remove(queue, currentIndex = 1, removeIndex = 1)

        assertEquals(listOf("a", "c"), ids(result.queue))
        assertEquals("c", result.queue[result.currentIndex].id)
    }

    @Test
    fun removeBeforeCurrent_shiftsCurrentIndexLeft() {
        val queue = listOf(track("a"), track("b"), track("c"))

        val result = QueuePolicy.remove(queue, currentIndex = 2, removeIndex = 0)

        assertEquals(1, result.currentIndex)
        assertEquals("c", result.queue[result.currentIndex].id)
    }

    @Test
    fun removeLastWhileItIsCurrent_stepsPointerBack() {
        val queue = listOf(track("a"), track("b"))

        val result = QueuePolicy.remove(queue, currentIndex = 1, removeIndex = 1)

        assertEquals(listOf("a"), ids(result.queue))
        assertEquals(0, result.currentIndex)
    }

    @Test
    fun removeOnlyTrack_emptiesQueue() {
        val result = QueuePolicy.remove(listOf(track("a")), currentIndex = 0, removeIndex = 0)

        assertEquals(emptyList<String>(), ids(result.queue))
        assertEquals(-1, result.currentIndex)
    }

    @Test
    fun move_reordersWithoutChangingWhatIsPlaying() {
        val queue = listOf(track("a"), track("b"), track("c"))

        val result = QueuePolicy.move(queue, currentIndex = 0, from = 2, to = 0)

        assertEquals(listOf("c", "a", "b"), ids(result.queue))
        assertEquals("a", result.queue[result.currentIndex].id)
    }

    @Test
    fun shuffle_putsCurrentTrackFirst() {
        val queue = listOf(track("a"), track("b"), track("c"), track("d"))

        val result = QueuePolicy.shuffled(queue, currentIndex = 2, seed = 7L)

        assertEquals("c", result.queue.first().id)
        assertEquals(0, result.currentIndex)
        assertEquals(queue.size, result.queue.size)
        assertEquals(queue.map { it.id }.toSet(), result.queue.map { it.id }.toSet())
        assertNotNull(result.restoreSnapshot)
    }

    @Test
    fun shuffleThenRestore_returnsOriginalOrderAndCurrentTrack() {
        val queue = listOf(track("a"), track("b"), track("c"), track("d"))

        val shuffled = QueuePolicy.shuffled(queue, currentIndex = 2, seed = 7L)
        val restored = QueuePolicy.restore(shuffled)

        assertEquals(ids(queue), ids(restored.queue))
        assertEquals(2, restored.currentIndex)
        assertEquals("c", restored.queue[restored.currentIndex].id)
    }

    @Test
    fun shuffle_isReproducibleForTheSameSeed() {
        val queue = (1..8).map { track("t$it") }

        val first = QueuePolicy.shuffled(queue, currentIndex = 0, seed = 42L)
        val second = QueuePolicy.shuffled(queue, currentIndex = 0, seed = 42L)

        assertEquals(ids(first.queue), ids(second.queue))
    }
}
