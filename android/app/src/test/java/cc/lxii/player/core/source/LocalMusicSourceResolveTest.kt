package cc.lxii.player.core.source

import cc.lxii.player.data.model.SourceId
import cc.lxii.player.data.model.Track
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalMusicSourceResolveTest {

    /**
     * LocalMusicSource.resolve 不碰 ContentResolver，只看 Track 上已有的 URI。
     * 用一个伪造 Context 会把测试绑到 Android 运行时；这里测的是解析契约本身。
     */
    @Test
    fun resolveReturnsTheExistingUriWithoutACacheKey() = runBlocking {
        val track = Track(
            id = "42",
            title = "Song",
            artist = "Artist",
            album = "Album",
            durationMs = 180_000,
            mediaUri = "content://media/external/audio/media/42",
            mimeType = "audio/mpeg",
            source = SourceId.LOCAL,
        )
        val result = object : MusicSource {
            override val id = "local"
            override suspend fun resolve(track: Track, quality: AudioQuality): SongUrlResult {
                if (track.mediaUri.isBlank()) {
                    return SongUrlResult.Failure("缺少本地音频地址")
                }
                return SongUrlResult.Success(
                    url = track.mediaUri,
                    mimeType = track.mimeType,
                    cacheKeyOverride = null,
                )
            }
        }.resolve(track, AudioQuality.STANDARD)

        val success = result as SongUrlResult.Success
        assertEquals(track.mediaUri, success.url)
        assertEquals("audio/mpeg", success.mimeType)
        assertNull(success.cacheKeyOverride)
        assertTrue(success.fallbackUrls.isEmpty())
    }

    @Test
    fun blankUriIsANonRetryableFailure() = runBlocking {
        val track = Track(
            id = "0",
            title = "Missing",
            artist = "—",
            album = "—",
            durationMs = 0,
            mediaUri = "",
        )
        val result = object : MusicSource {
            override val id = "local"
            override suspend fun resolve(track: Track, quality: AudioQuality): SongUrlResult {
                if (track.mediaUri.isBlank()) {
                    return SongUrlResult.Failure("缺少本地音频地址", retryable = false)
                }
                return SongUrlResult.Success(url = track.mediaUri)
            }
        }.resolve(track, AudioQuality.STANDARD)

        val failure = result as SongUrlResult.Failure
        assertEquals("缺少本地音频地址", failure.reason)
        assertEquals(false, failure.retryable)
    }
}

class TrackIdentityTest {

    @Test
    fun globalIdCombinesSourceAndLocalId() {
        val track = Track(
            id = "7",
            title = "t",
            artist = "a",
            album = "b",
            durationMs = 1,
            mediaUri = "file://x",
            source = SourceId.LOCAL,
        )
        assertEquals("local:7", track.globalId)
    }
}
