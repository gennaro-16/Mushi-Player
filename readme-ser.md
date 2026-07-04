# Native background playback — how it works

This app does **not** use a Dart audio package. All playback runs in a native
Android foreground service (`MusicService.kt`) driven by `android.media.MediaPlayer`.
Flutter only sends commands and renders state.

## Android side

**`MainActivity.kt`** is the entry point. On start it requests the notification
(Android 13+) and media permissions, then wires up the platform channels:

- a `MethodChannel` (`MusicBridge.CHANNEL_NAME`) that receives commands from
  Flutter (`startService`, `play`, `pause`, `next`, `previous`) and forwards
  them to the service as intents,
- an `EventChannel` (`shakeDetector`) that streams `"shake"` events from the
  accelerometer,
- an `EventChannel` (`playbackState`) that streams playback state back to Flutter.

**`MusicService.kt`** is the foreground service. It creates the notification
channel, queries `MediaStore` for on-device MP3s, plays them with `MediaPlayer`,
shows an ongoing `MediaStyle` notification with previous/play-pause/next actions,
owns a `MediaSessionCompat` (lock screen, Bluetooth/headset, Android Auto),
extracts embedded album art, handles seek, pushes the song list and periodic
playback state up to Flutter, and releases the player and session in `onDestroy`.

**`MusicBridge.kt`** is a small helper that holds the `MethodChannel` and the
`playbackState` event sink so the service can call back into Flutter on the main
thread.

## Flutter side

**`music_service_bridge.dart`** is the single bridge class. It owns the same
`MethodChannel` plus the two `EventChannel`s, sends commands to the service,
requests runtime permissions, and exposes callbacks
(`registerSongListCallback`, `registerShakeCallback`,
`registerPlaybackStateCallback`) that the UI subscribes to. Flutter never talks
to the service directly — everything goes through this bridge.

**`main.dart`** calls `MusicServiceBridge.initialize()` before `runApp` so the
channels are ready before the UI appears.

**`player_screen.dart`** subscribes to the bridge callbacks and drives the UI
from native state: notification/UI play-pause stay in sync via the
`playbackState` stream, and a shake toggles play/pause.

## Manifest

`AndroidManifest.xml` declares the `MusicService` with
`foregroundServiceType="mediaPlayback"` and the permissions Android requires:
`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `POST_NOTIFICATIONS`
(so the notification can appear on Android 13+), `READ_MEDIA_AUDIO` (Android 13+)
and `READ_EXTERNAL_STORAGE` (`maxSdkVersion=32`). `MainActivity` uses
`launchMode="singleTask"` so tapping the notification doesn't spawn duplicate
activities. A `MediaButtonReceiver` is registered so hardware/Bluetooth media
buttons reach the `MediaSession` even after the process was killed.

## Media session

`MusicService` holds a `MediaSessionCompat` whose `Callback` funnels every
transport source — notification buttons, lock screen, Bluetooth/headset, and
Android Auto — through the same `handle*` functions used by the Flutter
commands. Playback state and metadata (title, artist, album, duration, and
embedded album art) are mirrored into the session so companion surfaces stay in
sync with the app UI.
