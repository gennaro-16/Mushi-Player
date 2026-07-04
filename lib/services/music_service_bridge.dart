import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

typedef SongListCallback =
    Future<void> Function(List<Map<dynamic, dynamic>> songs);
typedef ShakeCallback = Future<void> Function();
typedef PlaybackStateCallback =
    Future<void> Function(Map<dynamic, dynamic> state);

/// Single bridge between Flutter and the native Android [MusicService].
///
/// Owns the one MethodChannel used to send playback commands to the service
/// and to receive the device song list, plus the two EventChannels that stream
/// shake events and playback state back into the UI.
class MusicServiceBridge {
  static const MethodChannel _channel = MethodChannel(
    'com.gennaro16.mushiplayer/music_service',
  );
  static const EventChannel _shakeChannel = EventChannel('shakeDetector');
  static const EventChannel _playbackStateChannel = EventChannel(
    'playbackState',
  );

  static SongListCallback? _onSongListUpdated;
  static ShakeCallback? _onShakeDetected;
  static PlaybackStateCallback? _onPlaybackStateChanged;

  static List<Map<dynamic, dynamic>>? _pendingSongList;
  static Map<dynamic, dynamic>? _pendingPlaybackState;

  static bool _initialized = false;
  static StreamSubscription? _shakeSubscription;
  static StreamSubscription? _playbackStateSubscription;

  static Future<void> initialize() async {
    // Install handlers once, and only on non-web platforms.
    if (kIsWeb || _initialized) {
      return;
    }

    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'songListUpdated':
          final songs =
              (call.arguments as List?)?.cast<Map<dynamic, dynamic>>() ?? [];
          _pendingSongList = songs;
          await _onSongListUpdated?.call(songs);
          return;
      }
    });

    _initializeShakeDetector();
    _initializePlaybackState();
  }

  /// Requests the runtime permission needed to read on-device audio and returns
  /// whether access was granted. Handles both Android 13+ (READ_MEDIA_AUDIO) and
  /// older versions (READ_EXTERNAL_STORAGE).
  static Future<bool> ensureAudioPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }

    final audioStatus = await Permission.audio.request();
    if (audioStatus.isGranted) {
      return true;
    }

    final storageStatus = await Permission.storage.request();
    return storageStatus.isGranted;
  }

  /// Opens the system app-settings screen so the user can grant a permission
  /// they previously denied permanently.
  static Future<void> openSettings() async {
    await openAppSettings();
  }

  static void _initializeShakeDetector() {
    _shakeSubscription = _shakeChannel.receiveBroadcastStream().listen(
      (data) async {
        if (data == 'shake') {
          await _onShakeDetected?.call();
        }
      },
      onError: (error) {
        if (kDebugMode) {
          print('Shake detector error: $error');
        }
      },
    );
  }

  static void _initializePlaybackState() {
    _playbackStateSubscription = _playbackStateChannel
        .receiveBroadcastStream()
        .listen(
          (data) async {
            if (data is Map) {
              _pendingPlaybackState = data;
              await _onPlaybackStateChanged?.call(data);
            }
          },
          onError: (error) {
            if (kDebugMode) {
              print('Playback state error: $error');
            }
          },
        );
  }

  static void registerSongListCallback({SongListCallback? onSongListUpdated}) {
    _onSongListUpdated = onSongListUpdated;
    final pendingSongList = _pendingSongList;
    if (pendingSongList != null && onSongListUpdated != null) {
      unawaited(onSongListUpdated(pendingSongList));
    }
  }

  static void registerShakeCallback(ShakeCallback callback) {
    _onShakeDetected = callback;
  }

  static void registerPlaybackStateCallback(PlaybackStateCallback callback) {
    _onPlaybackStateChanged = callback;
    final pendingPlaybackState = _pendingPlaybackState;
    if (pendingPlaybackState != null) {
      unawaited(callback(pendingPlaybackState));
    }
  }

  /// Asks the native side to scan the device library and push the result back
  /// via the songListUpdated callback. Does not start the foreground service.
  static Future<void> loadSongs() => _invoke('loadSongs');

  // One-shot commands from Flutter to the Android service.
  static Future<void> startService() => _invoke('startService');

  static Future<void> play() => _invoke('play');

  static Future<void> pause() => _invoke('pause');

  static Future<void> next() => _invoke('next');

  static Future<void> previous() => _invoke('previous');

  /// Fully stops playback and tears down the foreground service + notification.
  static Future<void> stop() => _invoke('stop');

  /// Seeks the current track to [positionMs] milliseconds from the start.
  static Future<void> seekTo(int positionMs) =>
      _invoke('seekTo', {'position': positionMs});

  /// Returns the embedded cover-art bytes for the track at [uri], or null when
  /// the track has no embedded art (or on unsupported platforms).
  static Future<Uint8List?> getArtwork(String uri) async {
    if (kIsWeb || uri.isEmpty) {
      return null;
    }
    try {
      return await _channel.invokeMethod<Uint8List>('getArtwork', {'uri': uri});
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<void> _invoke(String method, [dynamic arguments]) async {
    if (kIsWeb) {
      return;
    }

    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Ignore during unsupported runs, such as web or partial platform setups.
      if (kDebugMode) {
        print('$method method not available');
      }
    }
  }

  static void dispose() {
    _shakeSubscription?.cancel();
    _playbackStateSubscription?.cancel();
    _shakeSubscription = null;
    _playbackStateSubscription = null;
    _onSongListUpdated = null;
    _onShakeDetected = null;
    _onPlaybackStateChanged = null;
    _pendingSongList = null;
    _pendingPlaybackState = null;
  }
}
