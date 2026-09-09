package cc.lxii.player.data.sync

import kotlinx.serialization.Serializable

/** 服务端整快照。revision 是单调整数，客户端 PUT 必须带上次拿到的值。 */
@Serializable
data class SyncSnapshot(
    val revision: Long,
    val playlists: List<RemotePlaylist> = emptyList(),
    val likes: List<String> = emptyList(),
    val history: List<RemoteHistoryEntry> = emptyList(),
    val settings: Map<String, String> = emptyMap(),
)

@Serializable
data class RemotePlaylist(
    val id: String,
    val name: String,
    val trackIds: List<String> = emptyList(),
)

@Serializable
data class RemoteHistoryEntry(
    val trackId: String,
    val playedAtMs: Long,
)

sealed interface SyncApplyResult {
    data class Applied(val snapshot: SyncSnapshot) : SyncApplyResult
    data class Conflict(val server: SyncSnapshot) : SyncApplyResult
}

object SyncMerge {

    /**
     * 乐观并发：客户端带着 [baseRevision] 提交。服务端当前 revision 必须相等，
     * 否则说明别的设备已经写过，客户端必须先拉再合。
     *
     * 不做 CRDT：单人多设备冲突罕见，整快照替换足够，复杂度换不来收益。
     */
    fun applyPut(server: SyncSnapshot, incoming: SyncSnapshot, baseRevision: Long): SyncApplyResult {
        if (server.revision != baseRevision) return SyncApplyResult.Conflict(server)
        return SyncApplyResult.Applied(incoming.copy(revision = server.revision + 1))
    }
}
