package cc.lxii.player.core.source

import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.provider.MediaStore
import cc.lxii.player.data.model.SourceId
import cc.lxii.player.data.model.Track
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * 本地 MediaStore 音源。第一版唯一实现。
 *
 * 解析就是把已有的 content:// URI 原样交回：本地文件不需要签名 URL，
 * 也不需要 cacheKeyOverride（内容身份就是 URI 本身）。
 */
class LocalMusicSource(private val context: Context) : MusicSource {

    override val id: String = SourceId.LOCAL.name.lowercase()

    override suspend fun resolve(track: Track, quality: AudioQuality): SongUrlResult {
        val uri = track.mediaUri
        if (uri.isBlank()) {
            return SongUrlResult.Failure("缺少本地音频地址", retryable = false)
        }
        return SongUrlResult.Success(
            url = uri,
            mimeType = track.mimeType,
            cacheKeyOverride = null,
        )
    }

    suspend fun scanLibrary(): List<Track> = withContext(Dispatchers.IO) {
        val tracks = mutableListOf<Track>()
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.MIME_TYPE,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.IS_MUSIC,
        )
        val selection = "${MediaStore.Audio.Media.IS_MUSIC}!=0"
        val sort = "${MediaStore.Audio.Media.DATE_ADDED} DESC"
        context.contentResolver.query(collection, projection, selection, null, sort)?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val durationCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val mimeCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.MIME_TYPE)
            val albumIdCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
            while (cursor.moveToNext()) {
                val id = cursor.getLong(idCol)
                val albumId = cursor.getLong(albumIdCol)
                val mediaUri = ContentUris.withAppendedId(collection, id).toString()
                val coverUri = ContentUris.withAppendedId(
                    Uri.parse("content://media/external/audio/albumart"),
                    albumId,
                ).toString()
                tracks += Track(
                    id = id.toString(),
                    title = cursor.getString(titleCol).orEmpty().ifBlank { "未知歌曲" },
                    artist = cursor.getString(artistCol).orEmpty().ifBlank { "未知艺术家" },
                    album = cursor.getString(albumCol).orEmpty().ifBlank { "未知专辑" },
                    durationMs = cursor.getLong(durationCol).coerceAtLeast(0L),
                    mediaUri = mediaUri,
                    coverUri = coverUri,
                    mimeType = cursor.getString(mimeCol),
                    source = SourceId.LOCAL,
                )
            }
        }
        tracks
    }
}
