package cc.lxii.player.data.prefs

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
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

    suspend fun setDarkTheme(mode: ThemeMode) = put(Keys.darkTheme, mode.key)
    suspend fun setServerBaseUrl(url: String) = put(Keys.serverBaseUrl, url.trim())
    suspend fun setPlaybackSpeed(speed: Float) = put(Keys.playbackSpeed, speed)
    suspend fun setRepeatMode(mode: String) = put(Keys.repeatMode, mode)
    suspend fun setShuffle(enabled: Boolean) = put(Keys.shuffle, enabled)

    private suspend fun <T> put(key: Preferences.Key<T>, value: T) {
        context.dataStore.edit { it[key] = value }
    }
}

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
