package cc.lxii.player.core.lyrics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LrcParserTest {

    @Test
    fun parsesStandardLines() {
        val lines = LrcParser.parse(
            """
            [00:01.00]第一句
            [00:05.50]第二句
            """.trimIndent(),
        )
        assertEquals(2, lines.size)
        assertEquals(1_000L, lines[0].startTimeMs)
        assertEquals("第一句", lines[0].text)
        assertEquals(5_500L, lines[1].startTimeMs)
    }

    @Test
    fun twoDigitFractionIsCentiseconds() {
        // `.50` 是 500ms。当成毫秒会算成 50ms，整首歌词提前近半秒。
        val lines = LrcParser.parse("[00:10.50]测试")
        assertEquals(10_500L, lines.first().startTimeMs)
    }

    @Test
    fun oneDigitFractionIsTenths() {
        val lines = LrcParser.parse("[00:10.5]测试")
        assertEquals(10_500L, lines.first().startTimeMs)
    }

    @Test
    fun threeDigitFractionIsMilliseconds() {
        val lines = LrcParser.parse("[00:10.500]测试")
        assertEquals(10_500L, lines.first().startTimeMs)
    }

    @Test
    fun colonFractionSeparatorIsAccepted() {
        val lines = LrcParser.parse("[00:10:50]测试")
        assertEquals(10_500L, lines.first().startTimeMs)
    }

    @Test
    fun repeatedTimestampsShareOneBody() {
        val lines = LrcParser.parse("[00:01.00][00:30.00]副歌")
        assertEquals(2, lines.size)
        assertTrue(lines.all { it.text == "副歌" })
        assertEquals(listOf(1_000L, 30_000L), lines.map { it.startTimeMs })
    }

    @Test
    fun linesAreSortedEvenWhenFileIsNot() {
        val lines = LrcParser.parse(
            """
            [00:20.00]后
            [00:05.00]先
            """.trimIndent(),
        )
        assertEquals(listOf("先", "后"), lines.map { it.text })
    }

    @Test
    fun endTimeComesFromTheNextLine() {
        val lines = LrcParser.parse(
            """
            [00:01.00]甲
            [00:04.00]乙
            """.trimIndent(),
            durationMs = 10_000L,
        )
        assertEquals(4_000L, lines[0].endTimeMs)
        // 末行没有下一行，用曲长兜底，否则高亮判断没有终点。
        assertEquals(10_000L, lines[1].endTimeMs)
    }

    @Test
    fun offsetTagShiftsEveryLine() {
        val lines = LrcParser.parse(
            """
            [offset:-500]
            [00:02.00]偏移
            """.trimIndent(),
        )
        assertEquals(1_500L, lines.first().startTimeMs)
    }

    @Test
    fun metadataTagsAreIgnored() {
        val lines = LrcParser.parse(
            """
            [ti:标题]
            [ar:歌手]
            [al:专辑]
            [00:01.00]正文
            """.trimIndent(),
        )
        assertEquals(1, lines.size)
        assertEquals("正文", lines.first().text)
    }

    @Test
    fun enhancedLrcKeepsWordTimingsAndPlainText() {
        val lines = LrcParser.parse("[00:01.00]<00:01.00>你 <00:01.50>好")
        val line = lines.single()
        assertEquals("你 好", line.text)
        assertEquals(2, line.words.size)
        assertEquals("你 ", line.words[0].text)
        assertEquals(1_000L, line.words[0].startTimeMs)
        assertEquals("好", line.words[1].text)
        assertEquals(1_500L, line.words[1].startTimeMs)
    }

    @Test
    fun malformedLinesAreSkippedNotFatal() {
        val lines = LrcParser.parse(
            """
            这行没有时间戳
            [00:03.00]有效行
            [坏的]无效
            """.trimIndent(),
        )
        assertEquals(1, lines.size)
        assertEquals("有效行", lines.first().text)
    }

    @Test
    fun blankContentYieldsNothing() {
        assertTrue(LrcParser.parse("").isEmpty())
        assertTrue(LrcParser.parse("   \n  ").isEmpty())
    }

    @Test
    fun minutesBeyondSixtyStillParse() {
        val lines = LrcParser.parse("[100:05.00]很长的歌")
        assertEquals(100 * 60_000L + 5_000L, lines.first().startTimeMs)
    }
}

class LrcActiveIndexTest {

    private val lines = LrcParser.parse(
        """
        [00:01.00]甲
        [00:05.00]乙
        [00:09.00]丙
        """.trimIndent(),
        durationMs = 12_000L,
    )

    @Test
    fun beforeFirstLineNothingIsActive() {
        assertEquals(-1, LrcParser.activeIndex(lines, 0L))
        assertEquals(-1, LrcParser.activeIndex(lines, 999L))
    }

    @Test
    fun exactStartActivatesThatLine() {
        assertEquals(0, LrcParser.activeIndex(lines, 1_000L))
        assertEquals(1, LrcParser.activeIndex(lines, 5_000L))
    }

    @Test
    fun midLineKeepsPreviousLineActive() {
        assertEquals(0, LrcParser.activeIndex(lines, 4_999L))
        assertEquals(2, LrcParser.activeIndex(lines, 11_000L))
    }

    @Test
    fun emptyLyricsHaveNoActiveLine() {
        assertEquals(-1, LrcParser.activeIndex(emptyList(), 5_000L))
    }
}
