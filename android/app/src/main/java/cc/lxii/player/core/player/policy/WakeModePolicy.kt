package cc.lxii.player.core.player.policy

/** 播放器唤醒锁级别。 */
enum class WakeMode {
    /** 网络流：需要 WifiLock + WakeLock，否则息屏后连接被系统掐断。 */
    NETWORK,

    /** 本地文件：只需要 WakeLock，多申请 WifiLock 是白耗电。 */
    LOCAL,

    /** 无有效地址：不申请任何锁。 */
    NONE,
}

object WakeModePolicy {

    /**
     * 按播放地址决定唤醒锁级别。
     *
     * 全局固定成 NETWORK 会让本地播放白拿 WifiLock 耗电；固定成 LOCAL 会让
     * 网络播放在息屏后断流。所以每次解析出地址后都要重设一次。
     */
    fun forUrl(url: String?): WakeMode {
        val trimmed = url?.trim().orEmpty()
        if (trimmed.isEmpty()) return WakeMode.NONE

        val lower = trimmed.lowercase()
        return when {
            lower.startsWith("http://") || lower.startsWith("https://") -> WakeMode.NETWORK
            lower.startsWith("file://") -> WakeMode.LOCAL
            lower.startsWith("content://") -> WakeMode.LOCAL
            lower.startsWith("/") -> WakeMode.LOCAL
            else -> WakeMode.LOCAL
        }
    }
}
