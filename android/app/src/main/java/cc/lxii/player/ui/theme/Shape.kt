package cc.lxii.player.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Shapes
import androidx.compose.ui.unit.dp

val LxShapes = Shapes(
    extraSmall = RoundedCornerShape(6.dp),
    small = RoundedCornerShape(8.dp),
    medium = RoundedCornerShape(10.dp),
    large = RoundedCornerShape(14.dp),
    extraLarge = RoundedCornerShape(18.dp),
)

/** 语义化圆角，避免在各处散落魔法数。 */
object LxRadius {
    val listCover = 10.dp
    val card = 16.dp
    val cover = 20.dp
    val hero = 24.dp

    /** 推荐卡外层，与参考实现一致。 */
    val featuredCard = 4.dp

    /** 播放页封面。 */
    val stageCover = 14.dp

    /** 队列面板顶部。 */
    val sheet = 18.dp
}
