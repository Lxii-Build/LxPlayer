package cc.lxii.player.core.player.policy

import cc.lxii.player.data.model.Track

/**
 * 一次队列变更的结果。
 *
 * [restoreSnapshot] 只在随机播放开启时携带原始顺序：关闭随机时要还原成用户原本的排列，
 * 而不是留在打乱后的状态。
 */
data class QueueMutation(
    val queue: List<Track>,
    val currentIndex: Int,
    val restoreSnapshot: QueueSnapshot? = null,
)

/** 打乱前的队列快照，用于关闭随机播放时精确还原。 */
data class QueueSnapshot(
    val queue: List<Track>,
    val currentTrackId: String?,
)

/**
 * 队列运算，全部为纯函数。
 *
 * 抽成纯函数是为了能在 JVM 单测里覆盖，而不必启动 ExoPlayer 或设备。
 * 队列的坑几乎都在下标算术上（插入点在被移除项之后要不要减一、
 * 删掉当前项之后指针指向谁），这类 bug 只有测试能稳定拦住。
 */
object QueuePolicy {

    /**
     * 插入到「下一首播放」。
     *
     * 若曲目已在队列中，先移除旧位置再插入，避免同一首歌在队列里出现两次。
     * 当旧位置在插入点之前时，移除会让插入点左移一格，必须补偿，
     * 否则插入位置会比预期靠后一位。
     */
    fun insertNext(queue: List<Track>, currentIndex: Int, track: Track): QueueMutation {
        if (queue.isEmpty()) {
            return QueueMutation(listOf(track), 0)
        }

        val currentTrackId = queue.getOrNull(currentIndex)?.id
        val working = queue.toMutableList()
        var insertIndex = (currentIndex + 1).coerceIn(0, working.size)

        val existingIndex = working.indexOfFirst { it.id == track.id }
        if (existingIndex >= 0) {
            if (existingIndex < insertIndex) insertIndex--
            working.removeAt(existingIndex)
        }
        insertIndex = insertIndex.coerceIn(0, working.size)
        working.add(insertIndex, track)

        // 当前播放的曲目可能因为上面的移除而换了下标，按 id 重新定位。
        val nextIndex = currentTrackId
            ?.let { id -> working.indexOfFirst { it.id == id } }
            ?.takeIf { it >= 0 }
            ?: currentIndex.coerceIn(0, working.lastIndex)

        return QueueMutation(working, nextIndex)
    }

    /** 追加到队列末尾；已存在则不重复添加。 */
    fun addToEnd(queue: List<Track>, currentIndex: Int, track: Track): QueueMutation {
        if (queue.isEmpty()) {
            return QueueMutation(listOf(track), 0)
        }
        if (queue.any { it.id == track.id }) {
            return QueueMutation(queue, currentIndex)
        }
        return QueueMutation(queue + track, currentIndex)
    }

    /**
     * 移除指定位置。
     *
     * 移除当前项时，指针留在原下标——那里现在是原本的下一首，符合「删掉当前歌就播下一首」的直觉。
     * 移除最后一项且它就是当前项时，指针回退到新的末尾。
     */
    fun remove(queue: List<Track>, currentIndex: Int, removeIndex: Int): QueueMutation {
        if (removeIndex !in queue.indices) {
            return QueueMutation(queue, currentIndex)
        }
        val working = queue.toMutableList()
        working.removeAt(removeIndex)

        if (working.isEmpty()) {
            return QueueMutation(emptyList(), -1)
        }

        val nextIndex = when {
            removeIndex < currentIndex -> currentIndex - 1
            removeIndex > currentIndex -> currentIndex
            else -> currentIndex.coerceAtMost(working.lastIndex)
        }
        return QueueMutation(working, nextIndex)
    }

    /** 拖拽重排。当前播放曲目按 id 跟随移动，不因重排而切歌。 */
    fun move(queue: List<Track>, currentIndex: Int, from: Int, to: Int): QueueMutation {
        if (from !in queue.indices || to !in queue.indices || from == to) {
            return QueueMutation(queue, currentIndex)
        }
        val currentTrackId = queue.getOrNull(currentIndex)?.id
        val working = queue.toMutableList()
        working.add(to, working.removeAt(from))

        val nextIndex = currentTrackId
            ?.let { id -> working.indexOfFirst { it.id == id } }
            ?.takeIf { it >= 0 }
            ?: currentIndex
        return QueueMutation(working, nextIndex)
    }

    /**
     * 打乱队列并把当前曲目放到首位。
     *
     * 采用物理打乱而非依赖播放器内部的 shuffleOrder：本项目一次只把一个 MediaItem
     * 交给播放器（每首歌要独立解析地址），播放器的随机顺序对我们不可见也不可控。
     * [seed] 让测试可复现。
     */
    fun shuffled(queue: List<Track>, currentIndex: Int, seed: Long): QueueMutation {
        if (queue.size < 2) {
            return QueueMutation(queue, currentIndex)
        }
        val snapshot = QueueSnapshot(queue, queue.getOrNull(currentIndex)?.id)
        val current = queue.getOrNull(currentIndex)
        val rest = queue.filterIndexed { index, _ -> index != currentIndex }
            .shuffled(kotlin.random.Random(seed))

        val shuffled = if (current != null) listOf(current) + rest else rest
        return QueueMutation(shuffled, if (current != null) 0 else currentIndex, snapshot)
    }

    /** 还原打乱前的顺序，当前曲目按 id 重新定位。 */
    fun restore(mutation: QueueMutation): QueueMutation {
        val snapshot = mutation.restoreSnapshot ?: return mutation.copy(restoreSnapshot = null)
        val index = snapshot.currentTrackId
            ?.let { id -> snapshot.queue.indexOfFirst { it.id == id } }
            ?.takeIf { it >= 0 }
            ?: 0
        return QueueMutation(snapshot.queue, index)
    }
}
