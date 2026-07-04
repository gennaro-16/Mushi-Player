package com.gennaro16.mushiplayer

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {
	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)
		// Only the notification permission is requested natively. The audio/media
		// read permission is handled on the Flutter side via permission_handler
		// (see MusicServiceBridge.ensureAudioPermission) to avoid a double prompt.
		requestNotificationPermissionIfNeeded()
	}
//shake detector
	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		// MethodChannel for play/pause/next/previous controls
		val channel = MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			MusicBridge.CHANNEL_NAME,
		)
		MusicBridge.attachChannel(channel)

		channel.setMethodCallHandler { call, result ->
			when (call.method) {
				"loadSongs" -> {
					// Scan the library for the UI without starting the foreground
					// service (so no notification appears before playback begins).
					loadSongsAsync()
					result.success(null)
				}

				"startService" -> {
					startMusicService()
					result.success(null)
				}

				"play" -> {
					startMusicService()
					sendServiceCommand(MusicService.ACTION_PLAY, MusicService.SOURCE_FLUTTER)
					result.success(null)
				}

				"pause" -> {
					startMusicService()
					sendServiceCommand(MusicService.ACTION_PAUSE, MusicService.SOURCE_FLUTTER)
					result.success(null)
				}

				"next" -> {
					startMusicService()
					sendServiceCommand(MusicService.ACTION_NEXT, MusicService.SOURCE_FLUTTER)
					result.success(null)
				}

				"previous" -> {
					startMusicService()
					sendServiceCommand(MusicService.ACTION_PREVIOUS, MusicService.SOURCE_FLUTTER)
					result.success(null)
				}

				"seekTo" -> {
					val position = (call.argument<Number>("position"))?.toLong() ?: 0L
					startMusicService()
					sendSeekCommand(position)
					result.success(null)
				}

				"stop" -> {
					sendStopCommand()
					result.success(null)
				}

				"getArtwork" -> {
					val uri = call.argument<String>("uri")
					if (uri.isNullOrEmpty()) {
						result.success(null)
					} else {
						loadArtworkAsync(uri, result)
					}
				}

				else -> result.notImplemented()
			}
		}

		// EventChannel for shake detection
		val sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
		val accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
		var listener: SensorEventListener? = null

		EventChannel(flutterEngine.dartExecutor.binaryMessenger, "shakeDetector")
			.setStreamHandler(object : EventChannel.StreamHandler {
				override fun onListen(args: Any?, events: EventChannel.EventSink) {
					listener = object : SensorEventListener {
						private var lastShakeTime = 0L
						private val shakeThreshold = 12.0 // m/s²
						private val shakeTimeThreshold = 500 // ms

						override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) = Unit

						override fun onSensorChanged(event: SensorEvent) {
							if (event.sensor.type == Sensor.TYPE_ACCELEROMETER) {
								val x = event.values[0]
								val y = event.values[1]
								val z = event.values[2]

								// Calculate magnitude (remove gravity ~9.8)
								val magnitude = sqrt((x * x + y * y + z * z).toDouble())
								val acceleration = magnitude - SensorManager.STANDARD_GRAVITY

								if (acceleration > shakeThreshold) {
									val currentTime = System.currentTimeMillis()
									if (currentTime - lastShakeTime > shakeTimeThreshold) {
										events.success("shake")
										lastShakeTime = currentTime
									}
								}
							}
						}
					}
					sensorManager.registerListener(listener, accelerometer, SensorManager.SENSOR_DELAY_NORMAL)
				}

				override fun onCancel(args: Any?) {
					sensorManager.unregisterListener(listener)
					listener = null
				}
			})

		// EventChannel for playback state updates
		EventChannel(flutterEngine.dartExecutor.binaryMessenger, "playbackState")
			.setStreamHandler(object : EventChannel.StreamHandler {
				override fun onListen(args: Any?, events: EventChannel.EventSink) {
					MusicBridge.attachPlaybackStateListener(events)
				}

				override fun onCancel(args: Any?) {
					MusicBridge.detachPlaybackStateListener()
				}
			})
	}

	private fun loadSongsAsync() {
		Thread {
			val songs = MediaLibrary.toChannelList(MediaLibrary.loadSongs(this))
			// MusicBridge posts back onto the main thread and reuses the existing
			// 'songListUpdated' handler the service already talks to.
			MusicBridge.invokeMethod("songListUpdated", songs)
		}.start()
	}

	// Extracts embedded cover art (ID3 APIC frame) for a single track off the
	// main thread and returns the raw image bytes (or null) to Flutter, which
	// caches and renders them. Kept here (not in the service) so browsing the
	// library doesn't require the playback service to be running.
	private fun loadArtworkAsync(uri: String, result: MethodChannel.Result) {
		Thread {
			val bytes = extractEmbeddedArt(uri)
			runOnUiThread { result.success(bytes) }
		}.start()
	}

	private fun extractEmbeddedArt(uri: String): ByteArray? {
		val retriever = MediaMetadataRetriever()
		return try {
			retriever.setDataSource(this, android.net.Uri.parse(uri))
			retriever.embeddedPicture
		} catch (e: Exception) {
			null
		} finally {
			try {
				retriever.release()
			} catch (e: Exception) {
				// ignore
			}
		}
	}

	private fun startMusicService() {
		val intent = Intent(this, MusicService::class.java).apply {
			action = MusicService.ACTION_START
		}
		ContextCompat.startForegroundService(this, intent)
	}

	private fun sendServiceCommand(action: String, source: String) {
		val intent = Intent(this, MusicService::class.java).apply {
			this.action = action
			putExtra(MusicService.EXTRA_SOURCE, source)
		}
		// Use startForegroundService so commands sent while the app is in the
		// background (e.g. a shake) don't crash with
		// BackgroundServiceStartNotAllowedException on Android 12+. Every action
		// path in MusicService calls startForeground(), satisfying the 5s contract.
		ContextCompat.startForegroundService(this, intent)
	}

	private fun sendSeekCommand(positionMs: Long) {
		val intent = Intent(this, MusicService::class.java).apply {
			action = MusicService.ACTION_SEEK
			putExtra(MusicService.EXTRA_SOURCE, MusicService.SOURCE_FLUTTER)
			putExtra(MusicService.EXTRA_SEEK_POSITION, positionMs)
		}
		ContextCompat.startForegroundService(this, intent)
	}

	// Stop tears the service down (handleStop -> stopForeground + stopSelf), so we
	// must NOT use startForegroundService here (that would demand a startForeground
	// call within 5s and crash). A plain startService is safe: the app is in the
	// foreground when the user taps Stop, and the service is already running.
	private fun sendStopCommand() {
		val intent = Intent(this, MusicService::class.java).apply {
			action = MusicService.ACTION_STOP
			putExtra(MusicService.EXTRA_SOURCE, MusicService.SOURCE_FLUTTER)
		}
		try {
			startService(intent)
		} catch (e: Exception) {
			// Service may already be stopped; nothing to do.
		}
	}

	private fun requestNotificationPermissionIfNeeded() {
		if (
			Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
			ContextCompat.checkSelfPermission(
				this,
				Manifest.permission.POST_NOTIFICATIONS,
			) != PackageManager.PERMISSION_GRANTED
		) {
			ActivityCompat.requestPermissions(
				this,
				arrayOf(Manifest.permission.POST_NOTIFICATIONS),
				1001,
			)
		}
	}

}
