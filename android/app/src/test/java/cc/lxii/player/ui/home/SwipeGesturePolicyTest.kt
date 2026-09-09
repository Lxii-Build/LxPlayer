package cc.lxii.player.ui.home

import org.junit.Assert.assertEquals
import org.junit.Test

class SwipeGesturePolicyTest {

    @Test
    fun belowActivateThreshold_doesNothing() {
        assertEquals(SwipeDecision.IGNORE, SwipeGesturePolicy.decide(dxDp = 11f, dyDp = 0f))
        assertEquals(SwipeDecision.IGNORE, SwipeGesturePolicy.decide(dxDp = -11f, dyDp = 0f))
    }

    @Test
    fun atActivateThreshold_becomesPending() {
        assertEquals(SwipeDecision.PENDING, SwipeGesturePolicy.decide(dxDp = 12f, dyDp = 0f))
    }

    @Test
    fun verticalDominatesPastItsThreshold_yieldsToScrolling() {
        assertEquals(
            SwipeDecision.FAIL_TO_VERTICAL,
            SwipeGesturePolicy.decide(dxDp = 8f, dyDp = 24f),
        )
    }

    @Test
    fun mostlyHorizontalDragKeepsTheGestureEvenWithSomeVerticalDrift() {
        // 手指斜着滑但横向占主导时不应让位，否则卡片几乎滑不动。
        assertEquals(
            SwipeDecision.COMMIT_NEXT,
            SwipeGesturePolicy.decide(dxDp = -50f, dyDp = 26f),
        )
    }

    @Test
    fun leftSwipePastCommitThreshold_goesToNext() {
        assertEquals(SwipeDecision.COMMIT_NEXT, SwipeGesturePolicy.decide(dxDp = -36f, dyDp = 0f))
    }

    @Test
    fun rightSwipePastCommitThreshold_goesToPrevious() {
        assertEquals(SwipeDecision.COMMIT_PREV, SwipeGesturePolicy.decide(dxDp = 36f, dyDp = 0f))
    }

    @Test
    fun justUnderCommitThreshold_staysPending() {
        assertEquals(SwipeDecision.PENDING, SwipeGesturePolicy.decide(dxDp = -35f, dyDp = 0f))
    }

    @Test
    fun wrapIndex_cyclesForward() {
        assertEquals(1, SwipeGesturePolicy.wrapIndex(current = 0, direction = 1, size = 3))
        assertEquals(0, SwipeGesturePolicy.wrapIndex(current = 2, direction = 1, size = 3))
    }

    @Test
    fun wrapIndex_cyclesBackward() {
        assertEquals(2, SwipeGesturePolicy.wrapIndex(current = 0, direction = -1, size = 3))
        assertEquals(0, SwipeGesturePolicy.wrapIndex(current = 1, direction = -1, size = 3))
    }

    @Test
    fun wrapIndex_onEmptyListStaysAtZero() {
        assertEquals(0, SwipeGesturePolicy.wrapIndex(current = 0, direction = 1, size = 0))
    }

    @Test
    fun directionOf_isZeroUntilCommitted() {
        assertEquals(0, SwipeGesturePolicy.directionOf(SwipeDecision.IGNORE))
        assertEquals(0, SwipeGesturePolicy.directionOf(SwipeDecision.PENDING))
        assertEquals(0, SwipeGesturePolicy.directionOf(SwipeDecision.FAIL_TO_VERTICAL))
        assertEquals(1, SwipeGesturePolicy.directionOf(SwipeDecision.COMMIT_NEXT))
        assertEquals(-1, SwipeGesturePolicy.directionOf(SwipeDecision.COMMIT_PREV))
    }

    @Test
    fun thresholdsMatchTheReferenceInteraction() {
        // 这些数值是复刻参考交互手感的依据，改动会直接改变手感，因此钉住。
        assertEquals(12f, SwipeGesturePolicy.ACTIVATE_THRESHOLD_DP, 0f)
        assertEquals(24f, SwipeGesturePolicy.FAIL_VERTICAL_THRESHOLD_DP, 0f)
        assertEquals(36f, SwipeGesturePolicy.COMMIT_THRESHOLD_DP, 0f)
        assertEquals(260, SwipeGesturePolicy.ENTER_DURATION_MS)
        assertEquals(40f, SwipeGesturePolicy.ENTER_OFFSET_DP, 0f)
    }
}
