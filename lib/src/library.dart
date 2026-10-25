// Biblioteca local en SQLite. Es la misma base de datos que usa python-tracker.
import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

typedef Track = Map<String, Object?>;

String nowIso() => DateTime.now().toIso8601String().substring(0, 19);

class Library {
  late final Database db;

  Library(String path) {
    // libsqlite3.so (sin versión) solo viene con los paquetes -dev; la .so.0 está siempre.
    open.overrideFor(OperatingSystem.linux, () {
      try {
        return DynamicLibrary.open('libsqlite3.so.0');
      } on ArgumentError {
        return DynamicLibrary.open('libsqlite3.so');
      }
    });
    Directory(File(path).parent.path).createSync(recursive: true);
    db = sqlite3.open(path);
    db.execute('''
      CREATE TABLE IF NOT EXISTS tracks (
          path TEXT PRIMARY KEY, ma_id INTEGER, filename TEXT, title TEXT, artist TEXT,
          format TEXT, genre TEXT, channels INTEGER, duration REAL, ma_downloads INTEGER,
          ma_favourites INTEGER, added_at TEXT, plays INTEGER DEFAULT 0, last_played TEXT,
          favorite INTEGER DEFAULT 0);
      CREATE INDEX IF NOT EXISTS tracks_ma_id ON tracks(ma_id);
    ''');
    // columnas añadidas en versiones posteriores
    final have = {for (final r in db.select('PRAGMA table_info(tracks)')) r['name']};
    for (final col in ['download_url TEXT', 'md5 TEXT', 'checked_at TEXT']) {
      if (!have.contains(col.split(' ').first)) db.execute('ALTER TABLE tracks ADD COLUMN $col');
    }
  }

  List<Track> _q(String sql, [List<Object?> args = const []]) =>
      [for (final r in db.select(sql, args)) Map.of(r)];

  List<Track> all() => _q('SELECT * FROM tracks');

  Track? byMaId(int mid) {
    for (final r in _q('SELECT * FROM tracks WHERE ma_id = ?', [mid])) {
      if (File(r['path'] as String).existsSync()) return r;
    }
    return null;
  }

  Set<int> maIds() => {for (final r in _q('SELECT ma_id FROM tracks WHERE ma_id IS NOT NULL')) r['ma_id'] as int};

  Track add(Track track) {
    track = {'added_at': nowIso(), ...track};
    final cols = track.keys.join(', ');
    final marks = List.filled(track.length, '?').join(', ');
    db.execute('INSERT OR REPLACE INTO tracks ($cols) VALUES ($marks)', track.values.toList());
    return _q('SELECT * FROM tracks WHERE path = ?', [track['path']]).first;
  }

  void update(String path, Map<String, Object?> fields) {
    if (fields.isEmpty) return;
    final sets = fields.keys.map((k) => '$k = ?').join(', ');
    db.execute('UPDATE tracks SET $sets WHERE path = ?', [...fields.values, path]);
  }

  void remove(String path) => db.execute('DELETE FROM tracks WHERE path = ?', [path]);

  void played(String path) =>
      db.execute('UPDATE tracks SET plays = plays + 1, last_played = ? WHERE path = ?', [nowIso(), path]);

  void toggleFavorite(String path) => db.execute('UPDATE tracks SET favorite = 1 - favorite WHERE path = ?', [path]);
}
