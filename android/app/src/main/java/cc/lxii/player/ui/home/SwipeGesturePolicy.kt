package cc.lxii.player.ui.home

/** 一次拖动手势的判定结果。 */
enum class SwipeDecision {
    /** 位移还没到激活阈值，什么都不做。 */
    IGNORE,

    /** 纵向位移先超阈值，手势让位给垂直滚动。 */
    FAIL_TO_VERTICAL,

    /** 已激活但还没到提交阈值。 */
    PENDING,

    /** 左滑提交：切到下一张。 */
    COMMIT_NEXT,

    /** 右滑提交：切到上一张。 */
    COMMIT_PREV,
}

/**
 * 首页推荐卡的滑动判定。
 *
 * 交互刻意不用 Pager：参考实现是「单卡 + 三层扇形封面 + 离散跳变」，
 * 拖动过程中卡片不跟手，松手达到阈值后才整体换一张并做入场动画。
 * 用 Pager 会得到跟手滚动的另一种手感。
 *
 * 阈值全部以 dp 计算，与参考实现一致：
 * 横向 12 激活、纵向 24 让位、横向 36 提交（只看位移，不看速度）。
 */
object SwipeGesturePolicy {

    const val ACTIVATE_THRESHOLD_DP = 12f
    const val FAIL_VERTICAL_THRESHOLD_DP = 24f
    const val COMMIT_THRESHOLD_DP = 36f

    /** 松手后的入场动画时长（毫秒）。 */
    const val ENTER_DURATION_MS = 260

    /** 入场动画的初始横向偏移（dp），方向与滑动方向相同。 */
    const val ENTER_OFFSET_DP = 40f

    fun decide(dxDp: Float, dyDp: Float): SwipeDecision {
        val absX = kotlin.math.abs(dxDp)
        val absY = kotlin.math.abs(dyDp)

        // 纵向先越界就让位给页面滚动，否则卡片会吃掉整页的上下滑。
        if (absY >= FAIL_VERTICAL_THRESHOLD_DP && absY > absX) return SwipeDecision.FAIL_TO_VERTICAL
        if (absX < ACTIVATE_THRESHOLD_DP) return SwipeDecision.IGNORE
        if (absX < COMMIT_THRESHOLD_DP) return SwipeDecision.PENDING
        return if (dxDp < 0) SwipeDecision.COMMIT_NEXT else SwipeDecision.COMMIT_PREV
    }

    /** 循环换算下标，越界回绕。 */
    fun wrapIndex(current: Int, direction: Int, size: Int): Int {
        if (size <= 0) return 0
        return (current + direction).mod(size)
    }

    /** [SwipeDecision] 对应的方向增量，未提交时为 0。 */
    fun directionOf(decision: SwipeDecision): Int = when (decision) {
        SwipeDecision.COMMIT_NEXT -> 1
        SwipeDecision.COMMIT_PREV -> -1
        else -> 0
    }
}
