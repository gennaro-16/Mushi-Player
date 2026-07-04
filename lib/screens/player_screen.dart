import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../controllers/favorites_controller.dart';
import '../models/song.dart';
import '../repositories/sqlite_favorites_repository.dart';
import '../services/artwork_palette.dart';
import '../services/music_service_bridge.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/glass_icon_button.dart';
import '../widgets/song_artwork.dart';
import 'favorites_screen.dart';

class PlayerContent extends StatefulWidget {
  const PlayerContent({super.key});

  @override
  State<PlayerContent> createState() => _PlayerContentState();
}

class _PlayerContentState extends State<PlayerContent> {
  bool loading = true;
  bool permissionDenied = false;
  bool isFavorite = false;
  bool isPlaying = false;
  int currentIndex = 0;
  late final FavoritesController favoritesController;
  int position = 0; // milliseconds
  int duration = 0; // milliseconds
  // While the user is dragging the seek bar we follow the finger (0..1) and
  // ignore incoming native position updates so the thumb doesn't jump around.
  double? _seekPreview;

  // Artwork-driven gradient for the ambient background.
  List<Color> _bgColors = AppTheme.fallbackGradient;
  String? _paletteKey;

  List<Song> songs = const [];

  @override
  void initState() {
    super.initState();
    favoritesController = FavoritesController(SQLiteFavoritesRepository());
    MusicServiceBridge.registerSongListCallback(
      onSongListUpdated: _handleNativeSongList,
    );

    // Register shake detection callback
    MusicServiceBridge.registerShakeCallback(() async {
      // Toggle play/pause on shake
      await togglePlayPause();
    });

    // Register playback state callback
    MusicServiceBridge.registerPlaybackStateCallback((state) async {
      // Update UI with playback state from native
      if (mounted) {
        setState(() {
          isPlaying = state['isPlaying'] ?? false;
          // Don't overwrite the position while the user is scrubbing.
          if (_seekPreview == null) {
            position = (state['position'] as int?) ?? position;
          }
          duration = (state['duration'] as int?) ?? duration;
          if (songs.isNotEmpty) {
            currentIndex = ((state['index'] as int?) ?? 0).clamp(
              0,
              songs.length - 1,
            );
            isFavorite = favoritesController.containsSong(songs[currentIndex]);
          } else {
            currentIndex = 0;
            isFavorite = false;
          }
        });
      }
    });

    // Keep the heart icon in sync whenever favorites change anywhere (e.g. the
    // favorites screen removing the current song).
    favoritesController.addListener(_syncFavoriteState);

    favoritesController.initialize().then((_) {
      if (!mounted) return;
      _syncFavoriteState();
    });

    // Scan the device library automatically, before the user does anything.
    _loadLibrary();
  }

  void _syncFavoriteState() {
    if (!mounted) return;
    setState(() {
      isFavorite =
          songs.isNotEmpty &&
          favoritesController.containsSong(songs[currentIndex]);
    });
  }

  /// Refreshes the ambient gradient to match the current track's cover art.
  /// Cached palettes apply synchronously; new ones fade in when ready.
  void _maybeUpdatePalette() {
    if (songs.isEmpty) return;
    final song = songs[currentIndex];
    final key = song.assetPath.isNotEmpty ? song.assetPath : song.imageAsset;
    if (key == _paletteKey) return;
    _paletteKey = key;

    final cached = ArtworkPalette.cached(song);
    if (cached != null) {
      _bgColors = cached;
      return;
    }
    ArtworkPalette.forSong(song).then((colors) {
      if (mounted && _paletteKey == key) {
        setState(() => _bgColors = colors);
      }
    });
  }

  Future<void> _loadLibrary() async {
    if (kIsWeb) {
      setState(() => loading = false);
      return;
    }

    setState(() {
      loading = true;
      permissionDenied = false;
    });

    final granted = await MusicServiceBridge.ensureAudioPermission();
    if (!mounted) return;

    if (!granted) {
      setState(() {
        loading = false;
        permissionDenied = true;
      });
      return;
    }

    await MusicServiceBridge.loadSongs();

    // Safety net: if the native side never answers, don't spin forever.
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && loading) {
        setState(() => loading = false);
      }
    });
  }

  String _formatTime(int ms) {
    final seconds = (ms / 1000).floor();
    final minutesPart = (seconds ~/ 60).toString().padLeft(2, '0');
    final secondsPart = (seconds % 60).toString().padLeft(2, '0');
    return '$minutesPart:$secondsPart';
  }

  @override
  void dispose() {
    MusicServiceBridge.registerSongListCallback();
    favoritesController.removeListener(_syncFavoriteState);
    favoritesController.dispose();
    super.dispose();
  }

  Future<void> _playNative() async {
    await MusicServiceBridge.startService();
    await MusicServiceBridge.play();
  }

  Future<void> _pauseNative() async {
    await MusicServiceBridge.pause();
  }

  Future<void> _handleNativeSongList(
    List<Map<dynamic, dynamic>> nativeSongs,
  ) async {
    final mappedSongs = nativeSongs.map((entry) {
      final title = (entry['title'] as String?)?.trim().isNotEmpty == true
          ? entry['title'] as String
          : 'Unknown Song';
      final uri = entry['uri'] as String? ?? '';
      final artist = (entry['artist'] as String?)?.trim().isNotEmpty == true
          ? entry['artist'] as String
          : 'Unknown Artist';
      final album = (entry['album'] as String?)?.trim().isNotEmpty == true
          ? entry['album'] as String
          : 'Unknown Album';
      return Song(
        title: title,
        assetPath: uri,
        artist: artist,
        album: album,
        lyrics: '',
        imageAsset: _coverForTitle(title),
      );
    }).toList();

    if (!mounted) {
      songs = mappedSongs;
      currentIndex = 0;
      return;
    }

    setState(() {
      loading = false;
      songs = mappedSongs;
      currentIndex = songs.isEmpty
          ? 0
          : currentIndex.clamp(0, songs.length - 1);
      isFavorite =
          songs.isNotEmpty &&
          favoritesController.containsSong(songs[currentIndex]);
    });
  }

  String _coverForTitle(String title) {
    final covers = [
      'assets/music-images/1.jpg',
      'assets/music-images/2.jpg',
      'assets/music-images/3.jpg',
    ];
    final index = title.hashCode.abs() % covers.length;
    return covers[index % covers.length];
  }

  Future<void> nextSong() async {
    if (songs.isEmpty) return;
    setState(() {
      currentIndex = (currentIndex + 1) % songs.length;
      // Reset progress immediately so the bar doesn't briefly show the previous
      // track's position; the native playbackState stream will correct it.
      position = 0;
      duration = 0;
      isFavorite = favoritesController.containsSong(songs[currentIndex]);
    });
    await MusicServiceBridge.startService();
    await MusicServiceBridge.next();
  }

  Future<void> previousSong() async {
    if (songs.isEmpty) return;
    setState(() {
      currentIndex = (currentIndex - 1 + songs.length) % songs.length;
      position = 0;
      duration = 0;
      isFavorite = favoritesController.containsSong(songs[currentIndex]);
    });
    await MusicServiceBridge.startService();
    await MusicServiceBridge.previous();
  }

  Future<void> togglePlayPause() async {
    if (isPlaying) {
      await _pauseNative();
    } else {
      await _playNative();
    }
  }

  Future<void> stopPlayback() async {
    await MusicServiceBridge.stop();
    if (!mounted) return;
    setState(() {
      isPlaying = false;
      position = 0;
      _seekPreview = null;
    });
  }

  Future<void> toggleFavorite() async {
    var song = songs[currentIndex];
    try {
      // When adding, pull the real embedded cover art so it travels with the
      // song and is persisted in the favorites DB (instant + offline later).
      if (!favoritesController.containsSong(song)) {
        final bytes = await MusicServiceBridge.getArtwork(song.assetPath);
        if (bytes != null && bytes.isNotEmpty) {
          song = song.copyWith(artwork: bytes);
        }
      }
      await favoritesController.toggleFavorite(song);
      if (!mounted) return;
      setState(() {
        isFavorite = favoritesController.containsSong(song);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update favorites: $error')),
      );
    }
  }

  void openFavorites() async {
    final wasPlaying = isPlaying;
    if (isPlaying) {
      await _pauseNative();
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FavoritesScreen(controller: favoritesController),
      ),
    );
    // Resume if it was playing before
    if (wasPlaying && mounted) {
      await _playNative();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AppBackground(colors: _bgColors),
        SafeArea(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (loading) return _buildStatus();
    if (permissionDenied) return _buildPermissionDenied();
    if (songs.isEmpty) return _buildEmpty();
    return _buildPlayer();
  }

  Widget _buildStatus() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppTheme.accentSoft,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Scanning your music…',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required String title,
    required String message,
    required Widget actions,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Icon(icon, size: 40, color: AppTheme.accentSoft),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            actions,
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionDenied() {
    return _buildMessage(
      icon: Icons.lock_outline_rounded,
      title: 'Music access needed',
      message:
          'Mushi Player needs permission to read the audio files on your device.',
      actions: Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.center,
        children: [
          FilledButton(
            onPressed: _loadLibrary,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('Grant access'),
          ),
          TextButton(
            onPressed: MusicServiceBridge.openSettings,
            style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return _buildMessage(
      icon: Icons.music_off_rounded,
      title: 'No music found',
      message: "We couldn't find any MP3 files on this device.",
      actions: FilledButton.icon(
        onPressed: _loadLibrary,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Rescan'),
      ),
    );
  }

  Widget _buildPlayer() {
    _maybeUpdatePalette();
    final song = songs[currentIndex];
    return Column(
      children: [
        _buildTopBar(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Scale the artwork to the available space so the layout stays
              // balanced on both small and tall devices.
              final artSize = (constraints.maxHeight * 0.42).clamp(200.0, 340.0);
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 4, 28, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(height: 4),
                      _buildArtwork(song, artSize),
                      const SizedBox(height: 8),
                      _buildTrackInfo(song),
                      const SizedBox(height: 8),
                      _buildProgress(),
                      const SizedBox(height: 8),
                      _buildControls(),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildArtwork(Song song, double size) {
    final glow = _bgColors.isNotEmpty ? _bgColors.first : AppTheme.accent;
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: glow.withValues(alpha: 0.55),
              blurRadius: 60,
              spreadRadius: -12,
              offset: const Offset(0, 26),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: SongArtwork(
          uri: song.assetPath,
          placeholderAsset: song.imageAsset,
          size: size,
          borderRadius: BorderRadius.circular(28),
        ),
      ),
    );
  }

  Widget _buildTrackInfo(Song song) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _FavoriteButton(isFavorite: isFavorite, onTap: toggleFavorite),
      ],
    );
  }

  Widget _buildTopBar() {
    final counter = songs.isEmpty
        ? ''
        : '${currentIndex + 1} of ${songs.length}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'NOW PLAYING',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.textTertiary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              if (counter.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  counter,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          const Spacer(),
          GlassIconButton(
            icon: Icons.stop_rounded,
            tooltip: 'Stop',
            onTap: stopPlayback,
          ),
          const SizedBox(width: 10),
          GlassIconButton(
            icon: Icons.favorite_rounded,
            tooltip: 'Favorites',
            iconColor: AppTheme.favorite,
            onTap: openFavorites,
          ),
        ],
      ),
    );
  }

  Widget _buildProgress() {
    final hasDuration = duration > 0;
    final value = hasDuration
        ? (_seekPreview ?? (position / duration).clamp(0.0, 1.0))
        : 0.0;
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
            thumbColor: Colors.white,
            trackShape: const RoundedRectSliderTrackShape(),
          ),
          child: Slider(
            value: value,
            onChanged: hasDuration
                ? (v) {
                    setState(() {
                      _seekPreview = v;
                      position = (v * duration).round();
                    });
                  }
                : null,
            onChangeEnd: hasDuration
                ? (v) {
                    final target = (v * duration).round();
                    setState(() {
                      position = target;
                      _seekPreview = null;
                    });
                    MusicServiceBridge.seekTo(target);
                  }
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatTime(position), style: _timeStyle),
              Text(_formatTime(duration), style: _timeStyle),
            ],
          ),
        ),
      ],
    );
  }

  TextStyle get _timeStyle => TextStyle(
    color: AppTheme.textSecondary,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ControlButton(
          icon: Icons.skip_previous_rounded,
          size: 40,
          onTap: previousSong,
        ),
        _PlayButton(isPlaying: isPlaying, onTap: togglePlayPause),
        _ControlButton(
          icon: Icons.skip_next_rounded,
          size: 40,
          onTap: nextSong,
        ),
      ],
    );
  }
}

/// The large primary play/pause control — an accent gradient disc with a glow.
class _PlayButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onTap;

  const _PlayButton({required this.isPlaying, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.accentSoft, AppTheme.accent],
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accent.withValues(alpha: 0.5),
              blurRadius: 24,
              spreadRadius: -2,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            key: ValueKey(isPlaying),
            color: Colors.white,
            size: 40,
          ),
        ),
      ),
    );
  }
}

/// Secondary transport control (previous / next).
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      iconSize: size,
      color: Colors.white,
      splashRadius: 28,
      icon: Icon(icon),
    );
  }
}

/// Animated heart toggle that bounces when favorited.
class _FavoriteButton extends StatelessWidget {
  final bool isFavorite;
  final VoidCallback onTap;

  const _FavoriteButton({required this.isFavorite, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: Icon(
            isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            key: ValueKey(isFavorite),
            color: isFavorite ? AppTheme.favorite : Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }
}
