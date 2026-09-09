package cc.lxii.player

import android.app.Application
import androidx.media3.common.util.UnstableApi
import cc.lxii.player.core.lyrics.LyricsRepository
import cc.lxii.player.core.player.PlayerController
import cc.lxii.player.core.source.LocalMusicSource
import cc.lxii.player.data.prefs.SettingsStore

/**
 * 手写依赖容器。
 *
 * 单模块 + 十来个协作者的规模下，引入 DI 框架的注解处理开销换不来收益。
 */
@UnstableApi
class AppContainer(application: Application) {
    val localSource: LocalMusicSource = LocalMusicSource(application)
    val settings: SettingsStore = SettingsStore(application)
    val lyricsRepository: LyricsRepository = LyricsRepository(application)
    val playerController: PlayerController = PlayerController.get(application, localSource)
}

@UnstableApi
class LxPlayerApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }
}
