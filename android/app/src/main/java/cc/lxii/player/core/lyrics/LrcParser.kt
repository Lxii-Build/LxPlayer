package cc.lxii.player.core.lyrics

/** 逐字时间片，仅增强型 LRC 才有。 */
data class WordTiming(
    val text: String,
    val startTimeMs: Long,
)

/**
 * 一行歌词。
 *
 * [endTimeMs] 由下一行的开始时间推出，最后一行用曲长兜底；
 * 没有它就无法判断「当前行是否已经唱完」，高亮会一直卡在末行。
 */
data class LyricLine(
    val startTimeMs: Long,
    val text: String,
    val words: List<WordTiming> = emptyList(),
    val endTimeMs: Long = Long.MAX_VALUE,
)

/**
 * LRC 解析。
 *
 * 支持三种现实里常见的写法：
 *  - 标准 `[mm:ss.xx]歌词`
 *  - 一行多时间戳 `[00:01.00][00:30.00]副歌`（同一句复用）
 *  - 增强型逐字 `[00:01.00]<00:01.00>你 <00:01.50>好`
 *
 * 元数据标签（ti/ar/al/by/offset）里 offset 会被应用，其余忽略。
 * 解析失败的行直接跳过而不抛异常：歌词文件质量参差，
 * 一行坏掉不该让整首歌没有歌词。
 */
object LrcParser {

    private val lineTimeRegex = Regex("""\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?]""")
    private val wordTimeRegex = Regex("""<(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?>""")
    private val offsetRegex = Regex("""\[offset:\s*([+-]?\d+)\s*]""", RegexOption.IGNORE_CASE)

    fun parse(content: String, durationMs: Long = Long.MAX_VALUE): List<LyricLine> {
        if (content.isBlank()) return emptyList()

        val offset = offsetRegex.find(content)?.groupValues?.get(1)?.toLongOrNull() ?: 0L
        val collected = mutableListOf<LyricLine>()

        content.lineSequence().forEach { raw ->
            val line = raw.trim()
            if (line.isEmpty()) return@forEach

            val stamps = lineTimeRegex.findAll(line).toList()
            if (stamps.isEmpty()) return@forEach

            // 时间戳只在行首连续出现；正文从最后一个行首时间戳之后开始。
            val bodyStart = stamps.last().range.last + 1
            if (bodyStart > line.length) return@forEach
            val body = line.substring(bodyStart)

            val words = parseWords(body, offset)
            val text = stripWordTags(body).trim()
            if (text.isEmpty() && words.isEmpty()) return@forEach

            stamps.forEach { stamp ->
                val start = toMillis(stamp.groupValues) + offset
                if (start >= 0) {
                    collected += LyricLine(
                        startTimeMs = start,
                        text = text,
                        words = words,
                    )
                }
            }
        }

        if (collected.isEmpty()) return emptyList()

        // 排序后回填 endTimeMs：末行用曲长，拿不到曲长就留 MAX_VALUE。
        val sorted = collected.sortedBy { it.startTimeMs }
        return sorted.mapIndexed { index, line ->
            val end = sorted.getOrNull(index + 1)?.startTimeMs ?: durationMs
            line.copy(endTimeMs = end)
        }
    }

    private fun parseWords(body: String, offset: Long): List<WordTiming> {
        val matches = wordTimeRegex.findAll(body).toList()
        if (matches.isEmpty()) return emptyList()
        return matches.mapIndexedNotNull { index, match ->
            val start = toMillis(match.groupValues) + offset
            val textStart = match.range.last + 1
            val textEnd = matches.getOrNull(index + 1)?.range?.first ?: body.length
            if (textStart > textEnd) return@mapIndexedNotNull null
            val text = body.substring(textStart, textEnd)
            if (text.isEmpty()) null else WordTiming(text, start.coerceAtLeast(0L))
        }
    }

    private fun stripWordTags(body: String): String = wordTimeRegex.replace(body, "")

    /**
     * 时间戳转毫秒。
     *
     * 小数位要按位数缩放：`.5` 是 500ms、`.50` 是 500ms、`.500` 也是 500ms。
     * 统一当成毫秒会把两位写法算成 50ms，歌词整体提前近半秒。
     */
    private fun toMillis(groups: List<String>): Long {
        val minutes = groups[1].toLongOrNull() ?: 0L
        val seconds = groups[2].toLongOrNull() ?: 0L
        val fractionRaw = groups.getOrNull(3).orEmpty()
        val fraction = when (fractionRaw.length) {
            0 -> 0L
            1 -> (fractionRaw.toLongOrNull() ?: 0L) * 100
            2 -> (fractionRaw.toLongOrNull() ?: 0L) * 10
            else -> fractionRaw.take(3).toLongOrNull() ?: 0L
        }
        return minutes * 60_000 + seconds * 1_000 + fraction
    }

    /**
     * 当前应高亮的行下标，返回 -1 表示还没到第一行。
     *
     * 用二分查找而不是线性扫描：进度每 200ms 触发一次重算，
     * 长歌词线性扫描会在滚动时产生可感知的卡顿。
     */
    fun activeIndex(lines: List<LyricLine>, positionMs: Long): Int {
        if (lines.isEmpty() || positionMs < lines.first().startTimeMs) return -1
        var low = 0
        var high = lines.lastIndex
        var result = 0
        while (low <= high) {
            val mid = (low + high) / 2
            if (lines[mid].startTimeMs <= positionMs) {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }
}
