import 'dart:typed_data';

class Song {
  final String title;
  final String assetPath;
  final String artist;
  final String album;
  final String lyrics;
  final String imageAsset; // e.g. 'assets/hello_cover.jpg'

  /// Real embedded cover art bytes, when known. Carried with the song so the
  /// favorites screen can render the true cover instantly and offline (it is
  /// persisted alongside the row in the favorites database).
  final Uint8List? artwork;

  const Song({
    required this.title,
    required this.assetPath,
    required this.artist,
    required this.album,
    required this.lyrics,
    required this.imageAsset,
    this.artwork,
  });

  Song copyWith({
    String? title,
    String? assetPath,
    String? artist,
    String? album,
    String? lyrics,
    String? imageAsset,
    Uint8List? artwork,
  }) {
    return Song(
      title: title ?? this.title,
      assetPath: assetPath ?? this.assetPath,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      lyrics: lyrics ?? this.lyrics,
      imageAsset: imageAsset ?? this.imageAsset,
      artwork: artwork ?? this.artwork,
    );
  }
}
