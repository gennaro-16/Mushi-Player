package com.gennaro16.mushiplayer

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.Handler
import android.os.Looper
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.media.session.MediaButtonReceiver
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.SupervisorJob

// Native foreground service that owns the persistent playback notification and a
// MediaSessionCompat (lock-screen controls, Bluetooth/headset buttons, Auto).
class MusicService : Service() {
    private var mediaPlayer: MediaPlayer? = null
    private lateinit var mediaSession: MediaSessionCompat
    private var isPlaying = false
    private var currentSongIndex = 0
    private var songList: List<LibrarySong> = emptyList()
    // Consecutive prepare/playback failures; used to stop auto-skipping once
    // every track in the list has failed, to avoid an infinite skip loop.
    private var playbackErrorCount = 0

    // Best-effort embedded album art for the current track (null when absent).
    private var albumArt: Bitmap? = null
    // Cache keys so we only push MediaMetadata when something actually changed.
    private var lastMetadataIndex = -1
    private var lastMetadataDuration = -1
    private var lastMetadataArt: Bitmap? = null

    private val serviceJob = SupervisorJob()
    private val serviceScope = CoroutineScope(serviceJob + Dispatchers.Main)
    private val progressHandler = Handler(Looper.getMainLooper())
    private var progressRunnable: Runnable? = null

    // All transport controls (notification buttons, lock screen, Bluetooth,
    // Android Auto) funnel through the same handle* functions below.
    private val mediaSessionCallback = object : MediaSessionCompat.Callback() {
        override fun onPlay() = handlePlay()
        override fun onPause() = handlePause()
        override fun onSkipToNext() = handleNext()
        override fun onSkipToPrevious() = handlePrevious()
        override fun onSeekTo(pos: Long) = handleSeekTo(pos)
        override fun onStop() = handleStop()
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        initMediaSession()
        mediaPlayer = MediaPlayer()
        loadSongList()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startInForeground()
            ACTION_PLAY -> handlePlay()
            ACTION_PAUSE -> handlePause()
            ACTION_NEXT -> handleNext()
            ACTION_PREVIOUS -> handlePrevious()
            ACTION_SEEK -> handleSeekTo(intent.getLongExtra(EXTRA_SEEK_POSITION, 0L))
            ACTION_STOP -> handleStop()
            else -> startInForeground()
        }

        // Let the MediaSession translate hardware/Bluetooth media-button events
        // (delivered as ACTION_MEDIA_BUTTON intents) into the transport callbacks.
        MediaButtonReceiver.handleIntent(mediaSession, intent)

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopProgressUpdates()
        mediaPlayer?.release()
        mediaPlayer = null
        mediaSession.isActive = false
        mediaSession.release()
        serviceJob.cancel()
        super.onDestroy()
    }

    private fun initMediaSession() {
        mediaSession = MediaSessionCompat(this, "MushiMediaSession").apply {
            setCallback(mediaSessionCallback)
            isActive = true
        }
        // Publish an initial (idle/paused) state so lock screen and companions
        // have something valid to show even before the first track plays.
        updateMediaMetadata()
        updateMediaSessionPlaybackState()
    }

    // ─── Transport handlers (single source of truth for playback logic) ────────

    private fun handlePlay() {
        isPlaying = true
        playCurrentSong()
        startInForeground()
    }

    private fun handlePause() {
        isPlaying = false
        mediaPlayer?.pause()
        stopProgressUpdates()
        updatePlaybackState()
        startInForeground()
    }

    private fun handleNext() {
        if (songList.isNotEmpty()) {
            currentSongIndex = (currentSongIndex + 1) % songList.size
            albumArt = null
            if (isPlaying) {
                playCurrentSong()
            } else {
                updatePlaybackState()
            }
        }
        startInForeground()
    }

    private fun handlePrevious() {
        if (songList.isNotEmpty()) {
            currentSongIndex = if (currentSongIndex > 0) currentSongIndex - 1 else songList.size - 1
            albumArt = null
            if (isPlaying) {
                playCurrentSong()
            } else {
                updatePlaybackState()
            }
        }
        startInForeground()
    }

    private fun handleSeekTo(positionMs: Long) {
        try {
            mediaPlayer?.seekTo(positionMs.toInt())
        } catch (e: IllegalStateException) {
            Log.e(TAG, "seekTo failed", e)
        }
        updatePlaybackState()
    }

    private fun handleStop() {
        isPlaying = false
        mediaPlayer?.pause()
        stopProgressUpdates()
        updatePlaybackState()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun loadSongList() {
        serviceScope.launch(Dispatchers.IO) {
            val songs = MediaLibrary.loadSongs(this@MusicService)
            songList = songs
            serviceScope.launch(Dispatchers.Main) {
                MusicBridge.invokeMethod("songListUpdated", MediaLibrary.toChannelList(songs))
                updatePlaybackState()
                startInForeground()
            }
        }
    }

    private fun playCurrentSong() {
        if (songList.isEmpty()) return

        val song = songList.getOrNull(currentSongIndex) ?: return

        // Drop stale art immediately, then load this track's art in the background.
        albumArt = null
        loadAlbumArtFor(song)

        try {
            mediaPlayer?.apply {
                reset()
                setOnPreparedListener { player ->
                    // Successful prepare clears the failure streak.
                    playbackErrorCount = 0
                    player.start()
                    startProgressUpdates()
                    updatePlaybackState()
                }
                setOnCompletionListener {
                    currentSongIndex = (currentSongIndex + 1) % songList.size
                    albumArt = null
                    playCurrentSong()
                }
                setOnErrorListener { _, what, extra ->
                    Log.e(TAG, "MediaPlayer error (what=$what, extra=$extra) on '${song.title}'")
                    handlePlaybackError()
                    true // error handled; suppress the completion callback
                }
                setDataSource(this@MusicService, Uri.parse(song.uri))
                prepareAsync()
            }
        } catch (e: Exception) {
            // A bad/unreadable Uri can throw synchronously before onError fires.
            Log.e(TAG, "Failed to start '${song.title}'", e)
            handlePlaybackError()
        }
    }

    // Skip to the next track on a corrupt/unplayable file. If every track in the
    // list has failed in a row, stop instead of looping forever.
    private fun handlePlaybackError() {
        stopProgressUpdates()
        if (songList.isEmpty()) return

        playbackErrorCount++
        if (playbackErrorCount >= songList.size) {
            Log.e(TAG, "All ${songList.size} track(s) failed to play; stopping playback")
            playbackErrorCount = 0
            isPlaying = false
            updatePlaybackState()
            startInForeground()
            return
        }

        currentSongIndex = (currentSongIndex + 1) % songList.size
        albumArt = null
        if (isPlaying) {
            playCurrentSong()
        } else {
            updatePlaybackState()
        }
    }

    private fun updatePlaybackState() {
        val currentSong = songList.getOrNull(currentSongIndex)
        val position = safePosition()
        val duration = safeDuration()
        val state = mapOf(
            "song" to (currentSong?.title ?: "No songs"),
            "isPlaying" to isPlaying,
            "index" to currentSongIndex,
            "totalSongs" to songList.size,
            "position" to position,
            "duration" to duration,
        )
        // Unchanged: the existing EventChannel('playbackState') push to Flutter.
        MusicBridge.invokePlaybackState(state)

        // Additionally mirror the same state into the MediaSession so lock screen,
        // Bluetooth and Android Auto stay in sync. This is in addition to the
        // Flutter push, not a replacement.
        updateMediaMetadata()
        updateMediaSessionPlaybackState()
    }

    private fun updateMediaSessionPlaybackState() {
        val state = if (isPlaying) {
            PlaybackStateCompat.STATE_PLAYING
        } else {
            PlaybackStateCompat.STATE_PAUSED
        }
        val playbackState = PlaybackStateCompat.Builder()
            .setActions(
                PlaybackStateCompat.ACTION_PLAY or
                    PlaybackStateCompat.ACTION_PAUSE or
                    PlaybackStateCompat.ACTION_PLAY_PAUSE or
                    PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                    PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                    PlaybackStateCompat.ACTION_SEEK_TO or
                    PlaybackStateCompat.ACTION_STOP,
            )
            .setState(state, safePosition().toLong(), if (isPlaying) 1.0f else 0f)
            .build()
        mediaSession.setPlaybackState(playbackState)
    }

    private fun updateMediaMetadata() {
        val duration = safeDuration()
        // Only rebuild/push metadata when the track, duration, or art changed —
        // this runs on every 500ms progress tick otherwise.
        if (currentSongIndex == lastMetadataIndex &&
            duration == lastMetadataDuration &&
            albumArt === lastMetadataArt
        ) {
            return
        }
        lastMetadataIndex = currentSongIndex
        lastMetadataDuration = duration
        lastMetadataArt = albumArt

        val song = songList.getOrNull(currentSongIndex)
        val builder = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, song?.title ?: "No songs")
            .putString(
                MediaMetadataCompat.METADATA_KEY_ARTIST,
                song?.artist ?: MediaLibrary.UNKNOWN_ARTIST,
            )
            .putString(
                MediaMetadataCompat.METADATA_KEY_ALBUM,
                song?.album ?: MediaLibrary.UNKNOWN_ALBUM,
            )
            .putLong(
                MediaMetadataCompat.METADATA_KEY_DURATION,
                if (duration > 0) duration.toLong() else 0L,
            )
        albumArt?.let { builder.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, it) }
        mediaSession.setMetadata(builder.build())
    }

    private fun loadAlbumArtFor(song: LibrarySong) {
        val requestedUri = song.uri
        serviceScope.launch(Dispatchers.IO) {
            val bitmap = extractEmbeddedArt(requestedUri) ?: return@launch
            serviceScope.launch(Dispatchers.Main) {
                // Ignore if the user moved to another track while art was loading.
                if (songList.getOrNull(currentSongIndex)?.uri != requestedUri) return@launch
                albumArt = bitmap
                updateMediaMetadata()
                startInForeground()
            }
        }
    }

    private fun extractEmbeddedArt(uri: String): Bitmap? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(this, Uri.parse(uri))
            val picture = retriever.embeddedPicture ?: return null
            BitmapFactory.decodeByteArray(picture, 0, picture.size)
        } catch (e: Exception) {
            Log.w(TAG, "Album art extraction failed for '$uri'", e)
            null
        } finally {
            try {
                retriever.release()
            } catch (e: Exception) {
                // ignore
            }
        }
    }

    private fun safePosition(): Int = try {
        mediaPlayer?.currentPosition ?: 0
    } catch (e: IllegalStateException) {
        0
    }

    private fun safeDuration(): Int = try {
        mediaPlayer?.duration ?: 0
    } catch (e: IllegalStateException) {
        0
    }

    private fun startProgressUpdates() {
        stopProgressUpdates()
        progressRunnable = object : Runnable {
            override fun run() {
                try {
                    updatePlaybackState()
                } catch (e: Exception) {
                    e.printStackTrace()
                }
                progressHandler.postDelayed(this, 500)
            }
        }
        progressHandler.postDelayed(progressRunnable!!, 500)
    }

    private fun stopProgressUpdates() {
        progressRunnable?.let { progressHandler.removeCallbacks(it) }
        progressRunnable = null
    }

    private fun startInForeground() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): Notification {
        val openActivityIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }

        val contentPendingIntent = PendingIntent.getActivity(
            this,
            0,
            openActivityIntent,
            pendingIntentFlags(),
        )

        val playPauseIntent = Intent(this, MusicService::class.java).apply {
            action = if (isPlaying) ACTION_PAUSE else ACTION_PLAY
            putExtra(EXTRA_SOURCE, SOURCE_NOTIFICATION)
        }
        val playPausePendingIntent = PendingIntent.getService(
            this,
            1,
            playPauseIntent,
            pendingIntentFlags(),
        )

        val previousIntent = Intent(this, MusicService::class.java).apply {
            action = ACTION_PREVIOUS
            putExtra(EXTRA_SOURCE, SOURCE_NOTIFICATION)
        }
        val previousPendingIntent = PendingIntent.getService(
            this,
            2,
            previousIntent,
            pendingIntentFlags(),
        )

        val nextIntent = Intent(this, MusicService::class.java).apply {
            action = ACTION_NEXT
            putExtra(EXTRA_SOURCE, SOURCE_NOTIFICATION)
        }
        val nextPendingIntent = PendingIntent.getService(
            this,
            3,
            nextIntent,
            pendingIntentFlags(),
        )

        val stopIntent = Intent(this, MusicService::class.java).apply {
            action = ACTION_STOP
            putExtra(EXTRA_SOURCE, SOURCE_NOTIFICATION)
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            4,
            stopIntent,
            pendingIntentFlags(),
        )

        val currentSong = songList.getOrNull(currentSongIndex)
        val currentSongTitle = currentSong?.title ?: "No songs"
        val currentSongArtist = currentSong?.artist ?: MediaLibrary.UNKNOWN_ARTIST

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(
                if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
            )
            .setContentTitle(currentSongTitle)
            .setContentText(currentSongArtist)
            .setLargeIcon(albumArt)
            .setContentIntent(contentPendingIntent)
            .setDeleteIntent(stopPendingIntent)
            .setOngoing(isPlaying)
            .setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(
                android.R.drawable.ic_media_previous,
                "Previous",
                previousPendingIntent,
            )
            .addAction(
                if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (isPlaying) "Pause" else "Play",
                playPausePendingIntent,
            )
            .addAction(
                android.R.drawable.ic_media_next,
                "Next",
                nextPendingIntent,
            )
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Stop",
                stopPendingIntent,
            )
            .setStyle(
                androidx.media.app.NotificationCompat.MediaStyle()
                    .setMediaSession(mediaSession.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
                    .setShowCancelButton(true)
                    .setCancelButtonIntent(stopPendingIntent),
            )
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Music Playback",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Foreground service for music playback"
            setShowBadge(false)
        }

        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.createNotificationChannel(channel)
    }

    private fun pendingIntentFlags(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
    }

    companion object {
        const val ACTION_START = "com.gennaro16.mushiplayer.action.START"
        const val ACTION_PLAY = "com.gennaro16.mushiplayer.action.PLAY"
        const val ACTION_PAUSE = "com.gennaro16.mushiplayer.action.PAUSE"
        const val ACTION_NEXT = "com.gennaro16.mushiplayer.action.NEXT"
        const val ACTION_PREVIOUS = "com.gennaro16.mushiplayer.action.PREVIOUS"
        const val ACTION_SEEK = "com.gennaro16.mushiplayer.action.SEEK"
        const val ACTION_STOP = "com.gennaro16.mushiplayer.action.STOP"
        const val EXTRA_SOURCE = "com.gennaro16.mushiplayer.extra.SOURCE"
        const val EXTRA_SEEK_POSITION = "com.gennaro16.mushiplayer.extra.SEEK_POSITION"
        const val SOURCE_FLUTTER = "flutter"
        const val SOURCE_NOTIFICATION = "notification"
        private const val CHANNEL_ID = "music_playback_channel"
        private const val NOTIFICATION_ID = 1001
        private const val TAG = "MushiMusicService"
    }
}
