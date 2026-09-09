package cc.lxii.player.core.player

import android.content.Context
import android.util.Log
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.cache.Cache
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import java.io.File

/**
 * 流媒体缓存工厂。
 *
 * 目标是「缓存出问题也绝不影响播放」：缓存是加速手段，不是播放的前置条件。
 * 两种失败要区别对待——
 *  - 目录被另一个进程占用：放弃缓存直接联网播，删除只会破坏那个进程的状态；
 *  - 缓存本身损坏：删掉重开一次，再失败就放弃。
 */
object MediaCacheFactory {

    private const val TAG = "LxCache"
    private const val CACHE_DIR_NAME = "media-cache"

    fun open(context: Context, maxBytes: Long = PlayerBufferConfig.CACHE_SIZE_BYTES): Cache? {
        if (maxBytes <= 0L) return null
        val dir = File(context.cacheDir, CACHE_DIR_NAME)
        return openAt(context, dir, maxBytes, allowRepair = true)
    }

    private fun openAt(context: Context, dir: File, maxBytes: Long, allowRepair: Boolean): Cache? {
        val databaseProvider = StandaloneDatabaseProvider(context)
        return try {
            val cache = SimpleCache(dir, LeastRecentlyUsedCacheEvictor(maxBytes), databaseProvider)
            // 构造成功不代表可用：索引损坏会在首次访问时才炸，这里主动探一次。
            cache.keys
            cache
        } catch (locked: IllegalStateException) {
            // SimpleCache 对同一目录的重复加锁抛这个异常。别的进程正拿着它，不能删。
            Log.w(TAG, "缓存目录被占用，本次不使用缓存", locked)
            null
        } catch (broken: Exception) {
            if (!allowRepair) {
                Log.w(TAG, "缓存修复后仍不可用，本次不使用缓存", broken)
                return null
            }
            Log.w(TAG, "缓存损坏，尝试删除后重建", broken)
            runCatching { SimpleCache.delete(dir, databaseProvider) }
            runCatching { dir.deleteRecursively() }
            openAt(context, dir, maxBytes, allowRepair = false)
        }
    }
}
