package cc.lxii.player

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import androidx.core.app.NotificationCompat

/**
 * 悬浮歌词前台服务
 * 
 * 使用前台服务确保歌词更新在后台也能持续运行
 * Android 8.0+ 要求后台任务必须使用前台服务
 */
class FloatingLyricService : Service() {
    
    companion object {
        private const val NOTIFICATION_ID = 19920808
        private const val CHANNEL_ID = "floating_lyric_channel"
        private const val CHANNEL_NAME = "悬浮歌词服务"
        
        // 服务状态
        @Volatile
        var isRunning = false
            private set
        
        // 歌词更新回调
        var onUpdateCallback: (() -> Unit)? = null
    }
    
    // 使用独立的 HandlerThread 确保后台运行
    private var handlerThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null
    private var mainHandler = Handler(Looper.getMainLooper())
    
    // 更新间隔
    private val updateIntervalMs = 100L
    
    // 更新任务
    private val updateRunnable = object : Runnable {
        override fun run() {
            try {
                // 在主线程执行回调
                mainHandler.post {
                    onUpdateCallback?.invoke()
                }
            } catch (e: Exception) {
                android.util.Log.e("FloatingLyricService", "更新失败: ${e.message}")
            }
            
            // 继续下一次更新
            if (isRunning) {
                backgroundHandler?.postDelayed(this, updateIntervalMs)
            }
        }
    }
    
    override fun onCreate() {
        super.onCreate()
        android.util.Log.d("FloatingLyricService", "🚀 服务创建")
        
        // 创建通知渠道
        createNotificationChannel()
        
        // 启动前台服务
        startForeground(NOTIFICATION_ID, createNotification())
        
        // 创建后台线程
        handlerThread = HandlerThread("LyricUpdateThread").apply {
            start()
        }
        backgroundHandler = Handler(handlerThread!!.looper)
        
        isRunning = true
        
        // 开始更新循环
        backgroundHandler?.post(updateRunnable)
        
        android.util.Log.d("FloatingLyricService", "✅ 服务已启动，后台更新循环已开始")
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        android.util.Log.d("FloatingLyricService", "📌 onStartCommand")
        return START_STICKY  // 服务被杀死后自动重启
    }
    
    override fun onDestroy() {
        android.util.Log.d("FloatingLyricService", "🛑 服务销毁")
        
        isRunning = false
        
        // 停止更新循环
        backgroundHandler?.removeCallbacks(updateRunnable)
        
        // 停止后台线程
        handlerThread?.quitSafely()
        handlerThread = null
        backgroundHandler = null
        
        super.onDestroy()
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW  // 低优先级，不发出声音
            ).apply {
                description = "用于保持悬浮歌词在后台运行"
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        // 点击通知打开应用
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("悬浮歌词运行中")
            .setContentText("点击返回应用")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}
