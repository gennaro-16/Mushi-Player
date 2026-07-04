package com.gennaro16.mushiplayer

import android.content.ContentUris
import android.content.Context
import android.provider.MediaStore
import android.util.Log

data class LibrarySong(
    val title: String,
    val uri: String,
    val artist: String,
    val album: String,
)

// Shared, crash-proof MediaStore scan used by both MainActivity (to populate the
// UI list at startup, without starting the service/notification) and MusicService
// (to build its playback queue).
object MediaLibrary {
    private const val TAG = "MushiMediaLibrary"
    const val UNKNOWN_ARTIST = "Unknown Artist"
    const val UNKNOWN_ALBUM = "Unknown Album"

    fun loadSongs(context: Context): List<LibrarySong> {
        val songs = mutableListOf<LibrarySong>()
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.MIME_TYPE,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
        )
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"

        try {
            context.contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                null,
                "${MediaStore.Audio.Media.DATE_ADDED} DESC",
            )?.use { cursor ->
                val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
                val mimeColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.MIME_TYPE)
                val titleColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
                val artistColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
                val albumColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)

                while (cursor.moveToNext()) {
                    val mimeType = cursor.getString(mimeColumn) ?: ""
                    val displayName = cursor.getString(nameColumn) ?: "Unknown"
                    val isMp3 = mimeType == "audio/mpeg" || displayName.endsWith(".mp3", ignoreCase = true)
                    if (!isMp3) continue

                    val id = cursor.getLong(idColumn)
                    val contentUri = ContentUris.withAppendedId(
                        MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                        id,
                    )

                    // Prefer the ID3 TITLE tag; fall back to the file name.
                    val tagTitle = cursor.getString(titleColumn)?.trim()
                    val title = if (!tagTitle.isNullOrEmpty()) {
                        tagTitle
                    } else {
                        displayName.removeSuffix(".mp3").removeSuffix(".MP3")
                    }

                    val artist = cursor.getString(artistColumn)?.trim()
                        .takeUnless { it.isNullOrEmpty() || it == "<unknown>" }
                        ?: UNKNOWN_ARTIST
                    val album = cursor.getString(albumColumn)?.trim()
                        .takeUnless { it.isNullOrEmpty() || it == "<unknown>" }
                        ?: UNKNOWN_ALBUM

                    songs.add(LibrarySong(title, contentUri.toString(), artist, album))
                }
            }
        } catch (e: Exception) {
            // Most commonly a SecurityException when the audio permission hasn't
            // been granted yet. Return whatever we have (possibly empty) instead
            // of throwing, so callers never hang waiting for a result.
            Log.e(TAG, "Failed to query MediaStore for songs", e)
        }

        return songs
    }

    fun toChannelList(songs: List<LibrarySong>): List<Map<String, String>> =
        songs.map {
            mapOf(
                "title" to it.title,
                "uri" to it.uri,
                "artist" to it.artist,
                "album" to it.album,
            )
        }
}
