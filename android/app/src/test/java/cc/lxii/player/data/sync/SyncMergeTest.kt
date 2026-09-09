package cc.lxii.player.data.sync

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SyncMergeTest {

    private fun snapshot(revision: Long, likes: List<String> = emptyList()) =
        SyncSnapshot(revision = revision, likes = likes)

    @Test
    fun matchingRevision_appliesAndBumps() {
        val server = snapshot(3, likes = listOf("a"))
        val incoming = snapshot(3, likes = listOf("a", "b"))

        val result = SyncMerge.applyPut(server, incoming, baseRevision = 3)

        val applied = result as SyncApplyResult.Applied
        assertEquals(4, applied.snapshot.revision)
        assertEquals(listOf("a", "b"), applied.snapshot.likes)
    }

    @Test
    fun staleBaseRevision_conflictsWithoutWriting() {
        val server = snapshot(5, likes = listOf("server-wins"))
        val incoming = snapshot(4, likes = listOf("client-loses"))

        val result = SyncMerge.applyPut(server, incoming, baseRevision = 4)

        val conflict = result as SyncApplyResult.Conflict
        assertEquals(5, conflict.server.revision)
        assertEquals(listOf("server-wins"), conflict.server.likes)
    }

    @Test
    fun zeroRevisionFirstWrite_succeeds() {
        val result = SyncMerge.applyPut(
            server = snapshot(0),
            incoming = snapshot(0, likes = listOf("first")),
            baseRevision = 0,
        )
        assertTrue(result is SyncApplyResult.Applied)
        assertEquals(1, (result as SyncApplyResult.Applied).snapshot.revision)
    }
}
