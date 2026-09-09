package cc.lxii.player.ui.theme

import android.content.Context
import android.graphics.Bitmap
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.palette.graphics.Palette
import coil3.ImageLoader
import coil3.request.ImageRequest
import coil3.request.allowHardware
import coil3.toBitmap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** 封面取色结果。[accent] 用于背景渐变，[isDarkCover] 决定叠加层深浅。 */
data class CoverAccent(
    val accent: Color,
    val isDarkCover: Boolean,
)

/** 取不到封面时的兜底：中性灰，与「不设品牌彩色」一致。 */
val NeutralAccent = CoverAccent(Color(0xFF3A3A3A), isDarkCover = true)

/**
 * 从封面提取强调色。
 *
 * 这是本项目视觉语言的关键：主色是中性灰，界面上的颜色全部来自当前封面。
 * 硬编码一个固定强调色会让播放页在所有歌曲下长得一样，正是要避免的效果。
 *
 * 换歌时用 800ms 交叉淡入，而不是直接跳变——渐变色突变会很刺眼。
 */
@Composable
fun rememberCoverAccent(coverUri: String?): State<Color> {
    val context = LocalContext.current
    var target by remember { mutableStateOf(NeutralAccent.accent) }

    LaunchedEffect(coverUri) {
        target = if (coverUri.isNullOrBlank()) {
            NeutralAccent.accent
        } else {
            extractAccent(context, coverUri).accent
        }
    }

    return animateColorAsState(
        targetValue = target,
        animationSpec = tween(durationMillis = 800),
        label = "cover-accent",
    )
}

/**
 * 解码封面并取色。
 *
 * Palette 需要可读像素，所以关掉硬件位图（硬件位图无法 getPixels）。
 * 取色顺序：鲜艳暗色 → 鲜艳色 → 主色 → 兜底灰。优先暗色是因为
 * 播放页台面是纯黑，太亮的强调色会把文字压得看不清。
 */
suspend fun extractAccent(context: Context, coverUri: String): CoverAccent =
    withContext(Dispatchers.IO) {
        val bitmap = runCatching {
            val request = ImageRequest.Builder(context)
                .data(coverUri)
                .allowHardware(false)
                .size(192)
                .build()
            loaderFor(context).execute(request).image?.toBitmap()
        }.getOrNull() ?: return@withContext NeutralAccent

        runCatching {
            val palette = Palette.from(bitmap)
                .maximumColorCount(16)
                .generate()
            val argb = palette.darkVibrantSwatch?.rgb
                ?: palette.vibrantSwatch?.rgb
                ?: palette.dominantSwatch?.rgb
                ?: return@runCatching NeutralAccent
            CoverAccent(
                accent = Color(argb),
                isDarkCover = isDark(argb),
            )
        }.getOrDefault(NeutralAccent)
    }

// 取色会随每次换歌触发，复用同一个 ImageLoader 才能命中 Coil 的磁盘/内存缓存；
// 每次新建等于每首歌都重新下载一遍封面。
@Volatile
private var sharedLoader: ImageLoader? = null

private fun loaderFor(context: Context): ImageLoader =
    sharedLoader ?: synchronized(CoverAccent::class) {
        sharedLoader ?: ImageLoader(context.applicationContext).also { sharedLoader = it }
    }

/** 感知亮度判断深浅，用的是 sRGB 加权而非简单平均。 */
internal fun isDark(argb: Int): Boolean {
    val r = (argb shr 16 and 0xFF) / 255f
    val g = (argb shr 8 and 0xFF) / 255f
    val b = (argb and 0xFF) / 255f
    val luminance = 0.2126f * r + 0.7152f * g + 0.0722f * b
    return luminance < 0.5f
}

/** 供测试与非 Composable 场景使用的亮度判断。 */
fun Color.isDarkColor(): Boolean = isDark(toArgb())
