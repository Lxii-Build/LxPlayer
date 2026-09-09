package cc.lxii.player.data.model

/**
 * 音源标识。
 *
 * 参考实现把来源信息塞进 album 字段兼用，导致「判断是不是 B 站曲目」要去比对专辑名。
 * 这里用显式枚举：来源是曲目的固有属性，不该寄生在展示字段上。
 */
enum class SourceId {
    LOCAL,
}

/**
 * 播放队列与列表页共用的曲目模型。
 *
 * [id] 在同一 [source] 内稳定唯一，是队列去重、当前曲目定位、收藏比对的唯一依据。
 * 不要用列表下标做这些判断：随机播放会打乱顺序，下标随时失效。
 */
data class Track(
    val id: String,
    val title: String,
    val artist: String,
    val album: String,
    val durationMs: Long,
    val mediaUri: String,
    val coverUri: String? = null,
    val mimeType: String? = null,
    val source: SourceId = SourceId.LOCAL,
) {
    /** 跨来源的全局唯一键，用于持久化和缓存键。 */
    val globalId: String get() = "${source.name.lowercase()}:$id"
}
