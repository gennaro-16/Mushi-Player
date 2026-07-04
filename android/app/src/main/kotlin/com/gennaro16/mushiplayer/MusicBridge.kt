package com.gennaro16.mushiplayer

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// Holds the shared MethodChannel so native code can talk back to Flutter.
object MusicBridge {
    const val CHANNEL_NAME = "com.gennaro16.mushiplayer/music_service"

    @Volatile
    private var channel: MethodChannel? = null

    @Volatile
    private var playbackStateEventSink: EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    fun attachChannel(methodChannel: MethodChannel) {
        // MainActivity attaches the channel once Flutter is ready.
        channel = methodChannel
    }

    fun attachPlaybackStateListener(eventSink: EventChannel.EventSink) {
        playbackStateEventSink = eventSink
    }

    fun detachPlaybackStateListener() {
        playbackStateEventSink = null
    }

    fun invokeMethod(method: String, arguments: Any? = null) {
        val methodChannel = channel ?: return
        // MethodChannel calls must run on the main thread.
        mainHandler.post {
            methodChannel.invokeMethod(method, arguments)
        }
    }

    fun invokePlaybackState(state: Map<String, Any?>) {
        val eventSink = playbackStateEventSink ?: return
        mainHandler.post {
            eventSink.success(state)
        }
    }
}