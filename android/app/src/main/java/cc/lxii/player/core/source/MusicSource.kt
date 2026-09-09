package cc.lxii.player.core.source

import cc.lxii.player.data.model.Track

enum class AudioQuality {
    STANDARD,
    HIGH,
}

sealed interface SongUrlResult {
    data class Success(
        val url: String,
        val mimeType: String? = null,
        val cacheKeyOverride: String? = null,
        val expectedContentLength: Long = -1L,
        val fallbackUrls: List<String> = emptyList(),
    ) : SongUrlResult

    data class Failure(
        val reason: String,
        val retryable: Boolean = false,
    ) : SongUrlResult
}

interface MusicSource {
    val id: String
    suspend fun resolve(track: Track, quality: AudioQuality): SongUrlResult
}
