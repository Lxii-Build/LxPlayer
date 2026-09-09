package cc.lxii.player.core.lyrics

import android.content.ContentUris
import android.content.Context
import android.provider.MediaStore
import cc.lxii.player.data.model.Track
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * 本地歌词来源。
 *
 * 第一版只找与音频同目录、同名的 `.lrc` 侧车文件——这是本地音乐库最普遍的
 * 存放方式，不需要联网也不需要账号。找不到就是没有歌词，不去猜。
 *
 * 之所以还要走一次 MediaStore 查真实路径：Track 里存的是 content:// URI，
 * 拿不到同目录的兄弟文件名。
 */
class LyricsRepository(private val context: Context) {

    suspend fun load(track: Track): List<LyricLine> = withContext(Dispatchers.IO) {
        val audioPath = resolvePath(track) ?: return@withContext emptyList()
        val lrc = sidecarFor(audioPath) ?: return@withContext emptyList()
        val content = runCatching { lrc.readText() }.getOrNull() ?: return@withContext emptyList()
        LrcParser.parse(content, durationMs = track.durationMs)
    }

    private fun sidecarFor(audioPath: String): File? {
        val audio = File(audioPath)
        val base = audio.nameWithoutExtension
        val dir = audio.parentFile ?: return null
        // 大小写都试：外置存储常是大小写不敏感的，但内部路径不是。
        return sequenceOf("lrc", "LRC")
            .map { File(dir, "$base.$it") }
            .firstOrNull { it.isFile && it.canRead() }
    }

    private fun resolvePath(track: Track): String? {
        val id = track.id.toLongOrNull() ?: return null
        val uri = ContentUris.withAppendedId(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            id,
        )
        return runCatching {
            context.contentResolver.query(
                uri,
                arrayOf(MediaStore.Audio.Media.DATA),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        }.getOrNull()
    }
}
