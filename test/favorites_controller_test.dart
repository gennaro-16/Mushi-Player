import 'package:flutter_test/flutter_test.dart';
import 'package:mushi_player/controllers/favorites_controller.dart';
import 'package:mushi_player/models/song.dart';
import 'package:mushi_player/repositories/favorites_repository.dart';

class _FakeFavoritesRepository implements FavoritesRepository {
  final List<Song> _store = [];

  @override
  Future<void> init() async {}

  @override
  Future<List<Song>> getFavorites() async => List.unmodifiable(_store);

  @override
  Future<void> add(Song song) async {
    _store.add(song);
  }

  @override
  Future<void> remove(Song song) async {
    _store.removeWhere(
      (item) =>
          item.assetPath == song.assetPath && item.title == song.title,
    );
  }
}

Song _song({String path = 'content://media/1', String title = 'Track A'}) {
  return Song(
    title: title,
    assetPath: path,
    artist: 'Artist',
    album: 'Album',
    lyrics: '',
    imageAsset: 'assets/music-images/1.jpg',
  );
}

void main() {
  late _FakeFavoritesRepository repository;
  late FavoritesController controller;

  setUp(() {
    repository = _FakeFavoritesRepository();
    controller = FavoritesController(repository);
  });

  test('initialize loads favorites from repository', () async {
    await repository.add(_song());
    await controller.initialize();

    expect(controller.favorites, hasLength(1));
    expect(controller.favorites.first.title, 'Track A');
  });

  test('containsSong matches by assetPath when available', () async {
    final song = _song(path: 'content://media/42');
    await controller.initialize();
    await controller.addFavorite(song);

    expect(controller.containsSong(_song(path: 'content://media/42')), isTrue);
    expect(controller.containsSong(_song(path: 'content://media/99')), isFalse);
  });

  test('toggleFavorite adds then removes', () async {
    final song = _song();
    await controller.initialize();

    await controller.toggleFavorite(song);
    expect(controller.containsSong(song), isTrue);

    await controller.toggleFavorite(song);
    expect(controller.containsSong(song), isFalse);
    expect(controller.favorites, isEmpty);
  });

  test('notifyListeners fires when favorites change', () async {
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.initialize();
    await controller.addFavorite(_song());

    expect(notifications, greaterThanOrEqualTo(2));
  });
}
