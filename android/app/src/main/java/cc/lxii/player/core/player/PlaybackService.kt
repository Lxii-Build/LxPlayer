package cc.lxii.player.core.player

import android.content.Intent
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import cc.lxii.player.LxPlayerApp

/**
 * 前台播放服务。
 *
 * 用官方 [MediaSessionService] 而不是裸 Service + framework MediaSession：
 * 通知栏、媒体键、蓝牙元数据由 Media3 提供，省掉手搓通知与各家 OEM 适配。
 */
class PlaybackService : MediaSessionService() {

    private var session: MediaSession? = null

    override fun onCreate() {
        super.onCreate()
        val container = (application as LxPlayerApp).container
        val player = container.playerController.ensurePlayer()
        session = MediaSession.Builder(this, player).build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

    override fun onTaskRemoved(rootIntent: Intent?) {
        // 划掉任务卡片时若已暂停就收摊，避免留一个不发声的前台通知。
        val player = session?.player
        if (player == null || !player.isPlaying) {
            stopSelf()
        }
    }

    override fun onDestroy() {
        (application as LxPlayerApp).container.playerController.detach()
        session?.run {
            player.release()
            release()
        }
        session = null
        super.onDestroy()
    }
}
