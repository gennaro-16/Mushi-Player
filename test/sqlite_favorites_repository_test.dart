import 'package:flutter_test/flutter_test.dart';
import 'package:mushi_player/models/song.dart';
import 'package:mushi_player/repositories/sqlite_favorites_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Song _song({
  String path = 'content://media/1',
  String title = 'Test Song',
  String artist = 'Test Artist',
}) {
  return Song(
    title: title,
    assetPath: path,
    artist: artist,
    album: 'Test Album',
    lyrics: '',
    imageAsset: 'assets/music-images/2.jpg',
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('add, getFavorites, and remove round-trip', () async {
    final repository = SQLiteFavoritesRepository(databaseName: 'test_round_trip.db');
    await repository.init();

    final song = _song();
    await repository.add(song);

    final favorites = await repository.getFavorites();
    expect(favorites, hasLength(1));
    expect(favorites.first.title, song.title);
    expect(favorites.first.artist, song.artist);

    await repository.remove(song);
    expect(await repository.getFavorites(), isEmpty);
  });

  test('persists multiple favorites in insertion order', () async {
    final repository =
        SQLiteFavoritesRepository(databaseName: 'test_multi_fav.db');
    await repository.init();

    final first = _song(path: 'content://media/1', title: 'First');
    final second = _song(path: 'content://media/2', title: 'Second');
    await repository.add(first);
    await repository.add(second);

    final favorites = await repository.getFavorites();
    expect(favorites.map((s) => s.title), ['First', 'Second']);
  });
}
