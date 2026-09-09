package cc.lxii.player.ui.home

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
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

    Box(
        modifier = modifier
            .width(FanStackWidth)
            .height(FanStackHeight),
        contentAlignment = Alignment.TopEnd,
    ) {
        Layer(backLayer, coverAt(2), withShadow = false, tag = FanCoverStackTags.BACK)
        Layer(midLayer, coverAt(1), withShadow = false, tag = FanCoverStackTags.MID)
        Layer(frontLayer, coverAt(0), withShadow = true, tag = FanCoverStackTags.FRONT)
    }
}

@Composable
private fun Layer(layer: FanLayer, uri: String?, withShadow: Boolean, tag: String) {
    // offset 必须在 size 之后：写成 offset → size 时位移作用在尺寸未定的元素上，
    // 会被父容器的 TopEnd 对齐吸附回同一个角，三层完全重合。
    //
    // testTag 放在链末（最内层）：modifier 链里靠前的是外层，
    // 把 tag 放在 offset 之前会读到「父容器分配的位置」而非位移后的位置，
    // 断言就测不到 offset 到底有没有生效。
    var modifier: Modifier = Modifier
        .size(width = layer.width, height = layer.height)
        .offset(x = -layer.offsetRight, y = layer.offsetTop)
        .rotate(layer.rotation)
        .alpha(layer.alpha)
        .testTag(tag)

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
