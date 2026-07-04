import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/music_service_bridge.dart';

/// Displays a song's embedded cover art, fetched lazily from the native side by
/// its content [uri]. Falls back to [placeholderAsset] when the track has no
/// embedded art. Results are cached per-uri so scrolling and re-selection don't
/// refetch the same image.
class SongArtwork extends StatefulWidget {
  final String uri;
  final String placeholderAsset;
  final double size;
  final BorderRadius borderRadius;

  /// Pre-loaded cover-art bytes (e.g. persisted with a favorite). When provided
  /// they render immediately with no native round-trip — instant and offline.
  final Uint8List? artworkBytes;

  const SongArtwork({
    super.key,
    required this.uri,
    required this.placeholderAsset,
    required this.size,
    this.borderRadius = BorderRadius.zero,
    this.artworkBytes,
  });

  // null value = fetched but no art; missing key = not fetched yet.
  static final Map<String, Uint8List?> _cache = {};

  @override
  State<SongArtwork> createState() => _SongArtworkState();
}

class _SongArtworkState extends State<SongArtwork> {
  Uint8List? _art;

  @override
  void initState() {
    super.initState();
    _resolveArt();
  }

  @override
  void didUpdateWidget(SongArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri ||
        oldWidget.artworkBytes != widget.artworkBytes) {
      _art = null;
      _resolveArt();
    }
  }

  Future<void> _resolveArt() async {
    // Prefer bytes handed to us directly (persisted favorites) — no fetch needed.
    final provided = widget.artworkBytes;
    if (provided != null && provided.isNotEmpty) {
      setState(() => _art = provided);
      return;
    }

    final uri = widget.uri;
    if (SongArtwork._cache.containsKey(uri)) {
      setState(() => _art = SongArtwork._cache[uri]);
      return;
    }
    final bytes = await MusicServiceBridge.getArtwork(uri);
    SongArtwork._cache[uri] = bytes;
    if (!mounted || widget.uri != uri) return;
    setState(() => _art = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final art = _art;
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: art != null
            ? Image.memory(
                art,
                key: ValueKey(widget.uri),
                width: widget.size,
                height: widget.size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              )
            : Image.asset(
                widget.placeholderAsset,
                key: const ValueKey('placeholder'),
                width: widget.size,
                height: widget.size,
                fit: BoxFit.cover,
              ),
      ),
    );
  }
}
