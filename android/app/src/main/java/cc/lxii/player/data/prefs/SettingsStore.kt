package cc.lxii.player.data.prefs

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import cc.lxii.player.BuildConfig
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.dataStore by preferencesDataStore(name = "lxplayer_settings")

class SettingsStore(private val context: Context) {

    private object Keys {
        val darkTheme = stringPreferencesKey("dark_theme")
        val serverBaseUrl = stringPreferencesKey("server_base_url")
        val playbackSpeed = floatPreferencesKey("playback_speed")
        val repeatMode = stringPreferencesKey("repeat_mode")
        val shuffle = booleanPreferencesKey("shuffle")
        val likedTracks = stringSetPreferencesKey("liked_tracks")
        val playQueueIds = stringPreferencesKey("play_queue_ids")
        val playQueueIndex = stringPreferencesKey("play_queue_index")
    }

    val darkTheme: Flow<ThemeMode> = context.dataStore.data.map { prefs ->
        ThemeMode.fromKey(prefs[Keys.darkTheme])
    }

    val serverBaseUrl: Flow<String> = context.dataStore.data.map { prefs ->
        prefs[Keys.serverBaseUrl]?.takeIf { it.isNotBlank() } ?: BuildConfig.BASE_URL
    }

    val playbackSpeed: Flow<Float> = context.dataStore.data.map { prefs ->
        prefs[Keys.playbackSpeed] ?: 1.0f
    }

    val repeatMode: Flow<String> = context.dataStore.data.map { prefs ->
        prefs[Keys.repeatMode] ?: "OFF"
    }

    val shuffle: Flow<Boolean> = context.dataStore.data.map { prefs ->
        prefs[Keys.shuffle] ?: false
    }

    /** 已喜欢曲目的 globalId 集合。 */
    val likedTracks: Flow<Set<String>> = context.dataStore.data.map { prefs ->
        prefs[Keys.likedTracks] ?: emptySet()
    }

    /**
     * 上次的播放队列（globalId 列表 + 下标）。
     *
     * 第一版不为这一份列表引入 Room：单条记录用 DataStore 就够，
     * 真需要多表关联时再加。
     */
    val savedQueue: Flow<SavedQueue> = context.dataStore.data.map { prefs ->
        SavedQueue(
            ids = prefs[Keys.playQueueIds]
                ?.split('\n')
                ?.filter { it.isNotBlank() }
                ?: emptyList(),
            index = prefs[Keys.playQueueIndex]?.toIntOrNull() ?: -1,
        )
    }

    suspend fun setDarkTheme(mode: ThemeMode) = put(Keys.darkTheme, mode.key)
    suspend fun setServerBaseUrl(url: String) = put(Keys.serverBaseUrl, url.trim())
    suspend fun setPlaybackSpeed(speed: Float) = put(Keys.playbackSpeed, speed)
    suspend fun setRepeatMode(mode: String) = put(Keys.repeatMode, mode)
    suspend fun setShuffle(enabled: Boolean) = put(Keys.shuffle, enabled)

    /** 切换喜欢状态，返回切换后是否已喜欢。 */
    suspend fun toggleLiked(globalId: String): Boolean {
        var nowLiked = false
        context.dataStore.edit { prefs ->
            val current = prefs[Keys.likedTracks] ?: emptySet()
            nowLiked = globalId !in current
            prefs[Keys.likedTracks] =
                if (nowLiked) current + globalId else current - globalId
        }
        return nowLiked
    }

    suspend fun saveQueue(ids: List<String>, index: Int) {
        context.dataStore.edit { prefs ->
            prefs[Keys.playQueueIds] = ids.joinToString("\n")
            prefs[Keys.playQueueIndex] = index.toString()
        }
    }

    private suspend fun <T> put(key: Preferences.Key<T>, value: T) {
        context.dataStore.edit { it[key] = value }
    }
}

data class SavedQueue(
    val ids: List<String>,
    val index: Int,
)

enum class ThemeMode(val key: String) {
    SYSTEM("system"),
    LIGHT("light"),
    DARK("dark"),
    ;

    companion object {
        fun fromKey(key: String?): ThemeMode =
            entries.firstOrNull { it.key == key } ?: SYSTEM
    }
}
