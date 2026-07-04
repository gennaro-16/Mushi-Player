import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/song.dart';
import 'favorites_repository.dart';

/// SQLite-backed [FavoritesRepository] using `sqflite`. The database is opened
/// lazily on first use and supports add/remove/list of favorite songs. Works on
/// mobile and web (via the FFI web factory configured in `main.dart`).
class SQLiteFavoritesRepository implements FavoritesRepository {
  static const String _defaultDbName = 'favorites.db';
  static const int _dbVersion = 3;
  static const String _table = 'favorites';

  final String _dbName;

  Database? _db;

  SQLiteFavoritesRepository({String databaseName = _defaultDbName})
      : _dbName = databaseName;

  Future<Database> _database() async {
    if (_db != null) return _db!;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);

    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createFavoritesTable(db);
      },
      // v1 -> v2 rebuilds the table with the current schema, preserving rows.
      // v2 -> v3 adds the embedded cover-art BLOB column.
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE ${_table}_new (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              assetPath TEXT NOT NULL,
              title TEXT NOT NULL,
              artist TEXT NOT NULL,
              album TEXT NOT NULL,
              lyrics TEXT NOT NULL,
              imageAsset TEXT NOT NULL
            )
          ''');

          await db.execute('''
            INSERT INTO ${_table}_new (assetPath, title, artist, album, lyrics, imageAsset)
            SELECT assetPath, title, artist, album, lyrics, imageAsset
            FROM $_table
          ''');

          await db.execute('DROP TABLE $_table');
          await db.execute('ALTER TABLE ${_table}_new RENAME TO $_table');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE $_table ADD COLUMN artwork BLOB');
        }
      },
    );

    return _db!;
  }

  Future<void> _createFavoritesTable(Database db) async {
    await db.execute('''
      CREATE TABLE $_table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        assetPath TEXT NOT NULL,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        album TEXT NOT NULL,
        lyrics TEXT NOT NULL,
        imageAsset TEXT NOT NULL,
        artwork BLOB
      )
    ''');
  }

  @override
  Future<void> init() async {
    await _database();
  }

  @override
  Future<List<Song>> getFavorites() async {
    final db = await _database();
    final rows = await db.query(_table, orderBy: 'id ASC');
    return rows
        .map(
          (row) => Song(
            title: row['title'] as String,
            assetPath: row['assetPath'] as String,
            artist: row['artist'] as String,
            album: row['album'] as String,
            lyrics: row['lyrics'] as String,
            imageAsset: row['imageAsset'] as String,
            artwork: row['artwork'] as Uint8List?,
          ),
        )
        .toList();
  }

  @override
  Future<void> add(Song song) async {
    final db = await _database();
    await db.insert(_table, {
      'assetPath': song.assetPath,
      'title': song.title,
      'artist': song.artist,
      'album': song.album,
      'lyrics': song.lyrics,
      'imageAsset': song.imageAsset,
      'artwork': song.artwork,
    });
  }

  @override
  Future<void> remove(Song song) async {
    final db = await _database();
    await db.delete(
      _table,
      where:
          'assetPath = ? AND title = ? AND artist = ? AND album = ? AND lyrics = ? AND imageAsset = ?',
      whereArgs: [
        song.assetPath,
        song.title,
        song.artist,
        song.album,
        song.lyrics,
        song.imageAsset,
      ],
    );
  }
}
