import 'package:flutter/foundation.dart';

import '../models/song.dart';
import '../repositories/favorites_repository.dart';

class FavoritesController extends ChangeNotifier {
  final FavoritesRepository _repository;
  List<Song> _favorites = [];

  FavoritesController(this._repository);

  List<Song> get favorites => _favorites;

  bool _isSameSong(Song a, Song b) {
    // Prefer assetPath when available (device files), otherwise fall back to title
    if (a.assetPath.isNotEmpty && b.assetPath.isNotEmpty) {
      return a.assetPath == b.assetPath;
    }
    return a.title == b.title;
  }

  Future<void> initialize() async {
    await _repository.init();
    _favorites = List.of(await _repository.getFavorites());
    notifyListeners();
  }

  bool containsSong(Song song) {
    return _favorites.any((item) => _isSameSong(item, song));
  }

  Future<void> addFavorite(Song song) async {
    await _repository.add(song);
    if (!containsSong(song)) {
      _favorites.add(song);
    }
    notifyListeners();
  }

  Future<void> removeFavorite(Song song) async {
    await _repository.remove(song);
    _favorites.removeWhere((item) => _isSameSong(item, song));
    notifyListeners();
  }

  Future<void> toggleFavorite(Song song) async {
    if (containsSong(song)) {
      await removeFavorite(song);
    } else {
      await addFavorite(song);
    }
  }
}
