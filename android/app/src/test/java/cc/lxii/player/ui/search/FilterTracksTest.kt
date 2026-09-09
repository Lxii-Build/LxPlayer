package cc.lxii.player.ui.search

import cc.lxii.player.data.model.Track
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FilterTracksTest {

    private val library = listOf(
        track("1", title = "夜航星", artist = "陈奕迅", album = "Sunset"),
        track("2", title = "Blue Monday", artist = "New Order", album = "Substance"),
        track("3", title = "起风了", artist = "买辣椒也用券", album = "起风了"),
    )

    private fun track(id: String, title: String, artist: String, album: String) = Track(
        id = id,
        title = title,
        artist = artist,
        album = album,
        durationMs = 1000,
        mediaUri = "content://audio/$id",
    )

    @Test
    fun blankQueryReturnsNothing() {
        assertTrue(filterTracks(library, "").isEmpty())
        assertTrue(filterTracks(library, "   ").isEmpty())
    }

    @Test
    fun matchesTitle() {
        assertEquals(listOf("1"), filterTracks(library, "夜航").map { it.id })
    }

    @Test
    fun matchesArtist() {
        assertEquals(listOf("2"), filterTracks(library, "New Order").map { it.id })
    }

    @Test
    fun matchesAlbum() {
        assertEquals(listOf("2"), filterTracks(library, "Substance").map { it.id })
    }

    @Test
    fun isCaseInsensitive() {
        assertEquals(listOf("2"), filterTracks(library, "blue monday").map { it.id })
    }

    @Test
    fun trimsSurroundingWhitespace() {
        assertEquals(listOf("3"), filterTracks(library, "  起风了  ").map { it.id })
    }

    @Test
    fun noMatchReturnsEmpty() {
        assertTrue(filterTracks(library, "zzzz").isEmpty())
    }
}
