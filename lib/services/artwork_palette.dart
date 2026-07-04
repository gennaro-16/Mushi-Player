import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import '../models/song.dart';
import '../theme/app_theme.dart';
import 'music_service_bridge.dart';

/// Extracts a small, tasteful gradient from a song's cover art so the player
/// background can breathe with the music — the way Apple Music and Spotify do.
///
/// Results are cached per artwork key so switching tracks back and forth is
/// instant and never re-decodes the same image.
class ArtworkPalette {
  ArtworkPalette._();

  static final Map<String, List<Color>> _cache = {};

  static List<Color>? cached(Song song) => _cache[_keyFor(song)];

  static String _keyFor(Song song) =>
      song.assetPath.isNotEmpty ? song.assetPath : song.imageAsset;

  /// Returns three colors [top, mid, bottom] suitable for a vertical gradient.
  static Future<List<Color>> forSong(Song song) async {
    final key = _keyFor(song);
    final hit = _cache[key];
    if (hit != null) return hit;

    ImageProvider provider;
    final Uint8List? bytes = await MusicServiceBridge.getArtwork(
      song.assetPath,
    );
    if (bytes != null && bytes.isNotEmpty) {
      provider = MemoryImage(bytes);
    } else {
      provider = AssetImage(song.imageAsset);
    }

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        provider,
        size: const ui.Size(200, 200),
        maximumColorCount: 16,
      );
      final colors = _derive(palette);
      _cache[key] = colors;
      return colors;
    } catch (_) {
      return AppTheme.fallbackGradient;
    }
  }

  static List<Color> _derive(PaletteGenerator palette) {
    // Prefer a vivid, legible base color, then darken it toward the ink so the
    // gradient always ends on our neutral background for consistency.
    final base =
        palette.darkVibrantColor?.color ??
        palette.vibrantColor?.color ??
        palette.darkMutedColor?.color ??
        palette.dominantColor?.color ??
        AppTheme.fallbackGradient.first;

    final top = _mix(base, Colors.black, 0.28);
    final mid = _mix(base, AppTheme.ink, 0.62);
    return [top, mid, AppTheme.ink];
  }

  static Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;
}
