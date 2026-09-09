package cc.lxii.player.core.player

import android.content.Context
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.extractor.DefaultExtractorsFactory

/**
 * ExoPlayer 构建。
 *
 * 默认 LoadControl 是按视频场景调的，音频用它会缓冲过多、起播偏慢。
 * 这里按音频重新配：起播 1 秒即可出声，同时保留 60 秒回退缓冲，
 * 让用户小幅往回拖动不必重新下载。
 */
@UnstableApi
object PlayerFactory {

    fun build(context: Context): ExoPlayer {
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                PlayerBufferConfig.MIN_BUFFER_MS,
                PlayerBufferConfig.MAX_BUFFER_MS,
                PlayerBufferConfig.BUFFER_FOR_PLAYBACK_MS,
                PlayerBufferConfig.BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS,
            )
            .setPrioritizeTimeOverSizeThresholds(true)
            .setBackBuffer(
                PlayerBufferConfig.BACK_BUFFER_MS,
                PlayerBufferConfig.BACK_BUFFER_RETAIN_FROM_KEYFRAME,
            )
            .build()

        // 定码率音频没有 seek 表，不开这个开关就拖不动进度。
        val extractorsFactory = DefaultExtractorsFactory()
            .setConstantBitrateSeekingEnabled(true)

        val cache = MediaCacheFactory.open(context)
        val upstream = DefaultDataSource.Factory(context)
        val dataSourceFactory = if (cache != null) {
            CacheDataSource.Factory()
                .setCache(cache)
                .setUpstreamDataSourceFactory(upstream)
                // 缓存出错时忽略缓存继续联网，而不是让播放失败。
                .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)
        } else {
            upstream
        }

        val player = ExoPlayer.Builder(context)
            .setMediaSourceFactory(DefaultMediaSourceFactory(dataSourceFactory, extractorsFactory))
            .setLoadControl(loadControl)
            .setHandleAudioBecomingNoisy(true)
            .build()

        player.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                .build(),
            /* handleAudioFocus = */ true,
        )
        return player
    }
}
