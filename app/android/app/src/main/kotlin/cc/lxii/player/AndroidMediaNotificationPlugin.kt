package cc.lxii.player

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Android 媒体通知插件
 *
 * 通过 MethodChannel 让 Flutter 侧可以启动/停止自定义媒体通知前台服务，
 * 同时继续复用 audio_service 的 MediaSession / 媒体服务。
 */
class AndroidMediaNotificationPlugin : FlutterPlugin, MethodCallHandler {

    companion object {
        private const val CHANNEL_NAME = "android_media_notification"
    }

    private var channel: MethodChannel? = null
    private var applicationContext: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        applicationContext = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        val ctx = applicationContext
        if (ctx == null) {
            result.error("no_context", "Android context is null", null)
            return
        }

        when (call.method) {
            "start" -> {
                CustomMediaNotificationService.start(ctx)
                result.success(true)
            }
            "stop" -> {
                CustomMediaNotificationService.stop(ctx)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }
}


