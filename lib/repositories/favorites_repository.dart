import '../models/song.dart';

abstract class FavoritesRepository {
  Future<void> init();
  Future<List<Song>> getFavorites();
  Future<void> add(Song song);
  Future<void> remove(Song song);
}
