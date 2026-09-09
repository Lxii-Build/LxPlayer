package cc.lxii.player.ui.home

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.absoluteOffset
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import cc.lxii.player.data.model.Track
import cc.lxii.player.ui.component.CoverArt
import cc.lxii.player.ui.theme.LxColors

/**
 * 扇形封面堆叠的一层参数。数值来自参考交互实测，改动会直接改变卡片观感。
 */
private data class FanLayer(
    val width: Dp,
    val height: Dp,
    val offsetRight: Dp,
    val offsetTop: Dp,
    val alpha: Float,
    val rotation: Float,
)

private val backLayer = FanLayer(112.dp, 144.dp, 1.dp, 9.dp, 0.35f, 12f)
private val midLayer = FanLayer(120.dp, 160.dp, 18.dp, 4.dp, 0.65f, 5f)
private val frontLayer = FanLayer(128.dp, 176.dp, 36.dp, 0.dp, 1f, -4f)

/** 堆叠区域尺寸。 */
val FanStackWidth = 160.dp
val FanStackHeight = 192.dp

/**
 * 三层的测试标记。
 *
 * 三层封面用的是同一批图、颜色相近，靠像素边界无法分辨谁在哪里，
 * 所以让测试直接按标记读取各层的布局坐标与尺寸。
 */
object FanCoverStackTags {
    const val BACK = "fan-cover-back"
    const val MID = "fan-cover-mid"
    const val FRONT = "fan-cover-front"
    val all = listOf(BACK, MID, FRONT)
}

private val coverRadius = 24.dp

/**
 * 三层扇形封面。
 *
 * 后两层展示的是队列里接下来的封面，制造「还有更多」的暗示——
 * 这是参考实现用来替代分页指示器的手法：不画圆点，用露出的封面告诉你可以滑。
 */
@Composable
fun FanCoverStack(
    tracks: List<Track>,
    featuredIndex: Int,
    modifier: Modifier = Modifier,
) {
    if (tracks.isEmpty()) return

    fun coverAt(offset: Int): String? {
        val index = SwipeGesturePolicy.wrapIndex(featuredIndex, offset, tracks.size)
        return tracks.getOrNull(index)?.coverUri ?: tracks.getOrNull(featuredIndex)?.coverUri
    }

    // 不用 contentAlignment：让每层自己用 align(TopEnd) 定位，
    // 再叠 offset。父容器统一对齐会在测量阶段把子元素重新吸附，
    // 纵向位移被吃掉（顶边全为 0）。
    Box(
        modifier = modifier
            .width(FanStackWidth)
            .height(FanStackHeight),
    ) {
        Layer(this, backLayer, coverAt(2), withShadow = false, tag = FanCoverStackTags.BACK)
        Layer(this, midLayer, coverAt(1), withShadow = false, tag = FanCoverStackTags.MID)
        Layer(this, frontLayer, coverAt(0), withShadow = true, tag = FanCoverStackTags.FRONT)
    }
}

@Composable
private fun Layer(
    scope: BoxScope,
    layer: FanLayer,
    uri: String?,
    withShadow: Boolean,
    tag: String,
) {
    // 每层自己对齐到右上，再用 absoluteOffset 位移。
    //
    // 用 Modifier.offset 曾让三层顶边全是 0：offset 不改变布局约束，
    // 父容器 contentAlignment 会在测量后把子元素重新吸附回对齐点。
    // absoluteOffset 直接偏移放置坐标，不受对齐影响，也不随 RTL 翻转
    // （这里的偏移是视觉构图，不该跟随阅读方向）。
    //
    // testTag 放在链末：modifier 链靠前的是外层，
    // 放在 offset 之前会读到位移前的位置，断言就验不到 offset。
    var modifier: Modifier = with(scope) {
        Modifier
            .align(Alignment.TopEnd)
            .size(width = layer.width, height = layer.height)
            .absoluteOffset(x = -layer.offsetRight, y = layer.offsetTop)
            .rotate(layer.rotation)
            .alpha(layer.alpha)
            .testTag(tag)
    }

    if (withShadow) {
        modifier = modifier.shadow(
            elevation = 14.dp,
            shape = androidx.compose.foundation.shape.RoundedCornerShape(coverRadius),
            ambientColor = LxColors.cardCoverShadow,
            spotColor = LxColors.cardCoverShadow,
        )
    }

    CoverArt(uri = uri, modifier = modifier, radius = coverRadius)
}
