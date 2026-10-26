// Estado y lógica de la aplicación (explorador, biblioteca, cola y reproducción), sin interfaz.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'library.dart';
import 'modarchive.dart';
import 'player.dart';

const version = '2.0.1';

final home = Platform.environment['HOME'] ?? '.';
final musicDir = Platform.environment['TRACKER_DIR'] ?? '$home/Música/Tracker';
final dbPath = '$home/.local/share/trackerplay/biblioteca.db';

const exts = {
  'mptm', 'mod', 's3m', 'xm', 'it', '667', '669', 'amf', 'ams', 'c67', 'cba', 'dbm', 'digi', 'dmf', 'dsm', 'dsym',
  'dtm', 'etx', 'far', 'fc', 'fc13', 'fc14', 'fmt', 'fst', 'ftm', 'imf', 'ims', 'ice', 'j2b', 'm15', 'mdl', 'med',
  'mms', 'mt2', 'mtm', 'mus', 'nst', 'okt', 'plm', 'psm', 'pt36', 'ptm', 'puma', 'rtm', 'sfx', 'sfx2', 'smod',
  'st26', 'stk', 'stm', 'stx', 'stp', 'symmod', 'tcb', 'gmc', 'gtk', 'gt2', 'ult', 'unic', 'wow', 'xmf', 'gdm',
  'mo3', 'oxm', 'umx', 'xpk', 'ppm', 'mmcmp',
};

String fmtTime(num? secs) {
  final s = (secs ?? 0).toInt();
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

/// El texto si no está vacío; si no, null (como el «or» de Python).
String? str(Object? v) => v is String && v.isNotEmpty ? v : null;

/// Ordenación estable (la de List.sort no lo es).
List<T> sortedBy<T>(Iterable<T> items, int Function(T a, T b) cmp) {
  final xs = items.toList();
  final idx = List.generate(xs.length, (i) => i)
    ..sort((a, b) {
      final c = cmp(xs[a], xs[b]);
      return c != 0 ? c : a - b;
    });
  return [for (final i in idx) xs[i]];
}

class View {
  final String kind, title; // kind: modules, genres, artists, letters
  final Map<String, String>? params;
  final int page;
  int pages;
  View(this.kind, this.title, [this.params, this.page = 1, this.pages = 1]);
  View atPage(int p) => View(kind, title, params, p, pages);
}

/// Secciones de la barra lateral.
class Section {
  final String key, label;
  final bool library;
  const Section(this.key, this.label, {this.library = false});
}

const exploreSections = [
  Section('buscar', 'Buscar canción'),
  Section('artista', 'Buscar artista'),
  Section('tophits', 'Más descargadas'),
  Section('topscore', 'Mejor puntuadas'),
  Section('favs', 'Favoritas de la gente'),
  Section('featured', 'Destacadas'),
  Section('generos', 'Géneros'),
  Section('az', 'A-Z'),
  Section('random', 'Aleatorias'),
];
const librarySections = [
  Section('lib:0', 'Canciones', library: true),
  Section('lib:1', 'Por artista', library: true),
  Section('lib:2', 'Populares', library: true),
  Section('lib:3', 'Más escuchadas', library: true),
  Section('lib:4', 'Recientes', library: true),
  Section('lib:5', 'Favoritas', library: true),
];

final _views = {
  'tophits': ('Más descargadas', {'request': 'view_chart', 'query': 'tophits'}),
  'topscore': ('Mejor puntuadas', {'request': 'view_chart', 'query': 'topscore'}),
  'featured': ('Destacadas', {'request': 'view_chart', 'query': 'featured'}),
  'favs': ('Favoritas de la gente', {'request': 'view_top_favourites'}),
};
const resultSorts = ['Orden de la web', 'Alfabético', 'Popularidad'];
const libSortKeys = ['alfa', 'artista', 'popular', 'escuchadas', 'recientes', 'favoritas'];

class Controller extends ChangeNotifier {
  final Library lib;
  final player = Player();

  /// Avisos para el usuario (la interfaz los muestra como toasts).
  final void Function(String msg, {bool error}) notify;

  Controller(this.lib, {required this.notify});

  // explorador
  String section = 'tophits';
  View? view;
  final history = <View>[];
  List<Object> rows = [], shown = []; // Module o Entry
  int resultSort = 0, _viewToken = 0;
  bool loading = false;
  String? error;
  Set<int> haveIds = {};

  // biblioteca
  int libSort = 0, _scanToken = 0;
  String filter = '';
  List<Object> libItems = []; // Track, o String para la cabecera de un artista
  String libStatus = '';
  bool checking = false;

  // reproducción
  List<Object> queue = []; // Module o Track
  int qpos = -1, playToken = 0;
  String? note, noteTitle; // «Descargando…», «Error de descarga»
  final vu = <String, Float32List?>{};
  Timer? _ticker;

  bool get inLibrary => section.startsWith('lib:');
  bool get isSearch => section == 'buscar' || section == 'artista';

  void start() {
    Directory(musicDir).createSync(recursive: true);
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
    // con canciones descargadas se arranca en la biblioteca, que no necesita conexión
    openSection(lib.all().isEmpty ? 'tophits' : 'lib:0');
    scanLibrary();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    player.stop();
    super.dispose();
  }

  // ---------------------------------------------------------- explorador

  void openSection(String key) {
    section = key;
    if (key.startsWith('lib:')) {
      libSort = int.parse(key.substring(4));
      renderLibrary();
      return;
    }
    if (isSearch) {
      _viewToken++; // descarta lo que estuviera cargando
      view = null;
      rows = shown = [];
      loading = false;
      error = null;
      history.clear();
      notifyListeners();
      return;
    }
    history.clear();
    if (_views[key] case (final title, final params)?) {
      loadView(View('modules', title, params));
    } else if (key == 'generos') {
      loadView(View('genres', 'Géneros', {'request': 'view_genres'}));
    } else if (key == 'az') {
      showView(View('letters', 'A-Z'), [for (final c in '0ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')) Entry(c, c)]);
    } else if (key == 'random') {
      loadView(View('modules', 'Aleatorias', {'request': 'zomg_random'}));
    }
  }

  void search(String q) {
    q = q.trim();
    if (q.isEmpty) return;
    history.clear();
    if (section == 'artista') {
      loadView(View('artists', 'Artistas: $q', {'request': 'search', 'query': q, 'submit': 'Find', 'search_type': 'search_artist'}));
    } else {
      section = 'buscar';
      loadView(View('modules', 'Búsqueda: $q',
          {'request': 'search', 'query': q, 'submit': 'Find', 'search_type': 'filename_or_songtitle'}));
    }
  }

  Future<void> loadView(View v) async {
    final token = ++_viewToken;
    view = v;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final doc = await fetch(pageUrl(v.params!, v.page));
      if (token != _viewToken) return;
      final List<Object> found = switch (v.kind) {
        'modules' => parseModules(doc),
        'genres' => parseGenres(doc),
        _ => parseArtists(doc),
      };
      v.pages = math.max(parsePages(doc), v.page);
      showView(v, found);
    } catch (e) {
      if (token != _viewToken) return;
      loading = false;
      error = 'No se pudo cargar ${v.title}: $e';
      notifyListeners();
    }
  }

  void showView(View v, List<Object> found) {
    view = v;
    rows = found;
    resultSort = 0;
    loading = false;
    error = null;
    _buildResults();
  }

  void _buildResults() {
    haveIds = lib.maIds();
    if (view?.kind == 'modules') {
      final mods = rows.cast<Module>();
      shown = switch (resultSort) {
        1 => sortedBy<Module>(mods, (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase())),
        2 => sortedBy<Module>(mods, (a, b) => b.pop.compareTo(a.pop)),
        _ => List.of(mods),
      };
    } else {
      shown = rows;
    }
    notifyListeners();
  }

  void setResultSort(int i) {
    resultSort = i;
    _buildResults();
  }

  void selectResult(int idx) {
    final v = view;
    if (v == null || idx >= shown.length) return;
    if (v.kind == 'modules') {
      queue = List.of(shown);
      playIndex(idx);
      return;
    }
    final e = shown[idx] as Entry;
    history.add(v);
    switch (v.kind) {
      case 'genres':
        loadView(View('modules', 'Género: ${e.name}', {'query': e.id, 'request': 'search', 'search_type': 'genre'}));
      case 'artists':
        loadView(View('modules', 'Artista: ${e.name}', {'request': 'view_artist_modules', 'query': e.id}));
      case 'letters':
        loadView(View('modules', 'Letra ${e.name}', {'request': 'view_by_list', 'query': e.id}));
    }
  }

  bool canPage(int delta) {
    final v = view;
    return v != null && v.params != null && !loading && v.page + delta >= 1 && v.page + delta <= v.pages;
  }

  void page(int delta) {
    if (canPage(delta)) loadView(view!.atPage(view!.page + delta));
  }

  void back() {
    if (history.isNotEmpty) loadView(history.removeLast());
  }

  // ---------------------------------------------------------- descargas

  /// Descarga un módulo (si no está ya) y lo registra en la biblioteca.
  Future<Track> _download(Module mod) async {
    if (lib.byMaId(mod.id) case final t?) return t;
    final url = downloadUrl(mod.id);
    final data = await fetchModuleFile(url);
    var name = mod.filename.substring(mod.filename.lastIndexOf('/') + 1);
    if (name.isEmpty) name = '${mod.id}.mod';
    var dest = File('$musicDir/$name');
    if (dest.existsSync()) dest = File('$musicDir/${mod.id}_$name');
    await dest.writeAsBytes(data);
    Map<String, Object?> info;
    try {
      info = await moduleInfo(mod.id);
    } catch (_) {
      info = {}; // sin ficha nos quedamos con lo que sabemos
    }
    final local = await openmptInfo(dest.path);
    return lib.add({
      'path': dest.path, 'ma_id': mod.id, 'filename': mod.filename,
      'title': str(info['title']) ?? str(local['title']) ?? mod.title,
      'artist': str(info['artist']) ?? str(local['artist']),
      'format': mod.format, 'genre': info['genre'],
      'channels': info['channels'] ?? local['channels'],
      'duration': local['duration'], 'ma_downloads': info['ma_downloads'],
      'ma_favourites': info['ma_favourites'], 'download_url': url,
      'md5': md5.convert(data).toString(), 'checked_at': nowIso(),
    });
  }

  /// [token] nulo: solo descargar; si no, reproducir al acabar si sigue siendo la canción pedida.
  Future<void> download(Module mod, [int? token]) async {
    if (token == null) notify('Descargando ${mod.filename}…');
    Track track;
    try {
      track = await _download(mod);
    } catch (e) {
      notify('No se pudo descargar ${mod.filename}: $e', error: true);
      if (token == playToken) {
        note = 'Error de descarga';
        notifyListeners();
      }
      return;
    }
    _buildResults();
    renderLibrary();
    if (token == null) {
      notify('Guardada en la biblioteca: ${track['path'].toString().split('/').last}');
    } else if (token == playToken) {
      _startTrack(track);
    }
  }

  /// Refresca los datos de modarchive y vuelve a bajar los archivos cuyo MD5 haya cambiado.
  Future<void> checkUpdates() async {
    if (checking) return;
    checking = true;
    final tracks = [for (final t in lib.all()) if (t['ma_id'] != null) t];
    var updated = 0, failed = 0;
    for (var n = 0; n < tracks.length; n++) {
      final t = tracks[n];
      libStatus = 'Comprobando actualizaciones ${n + 1}/${tracks.length}…';
      notifyListeners();
      try {
        final mid = t['ma_id'] as int;
        final info = await moduleInfo(mid);
        final fields = <String, Object?>{
          for (final k in ['artist', 'title', 'genre', 'channels', 'ma_downloads', 'ma_favourites'])
            if (info[k] != null && info[k] != '' && info[k] != 0) k: info[k],
        };
        final file = File(t['path'] as String);
        final localMd5 = file.existsSync() ? md5.convert(await file.readAsBytes()).toString() : null;
        final url = str(t['download_url']) ?? downloadUrl(mid);
        if (info['md5'] != null && info['md5'] != localMd5) {
          final data = await fetchModuleFile(url);
          if (md5.convert(data).toString() == info['md5']) {
            await file.writeAsBytes(data);
            fields['duration'] = (await openmptInfo(file.path))['duration'];
            updated++;
          }
        }
        fields.addAll({'md5': info['md5'] ?? localMd5, 'download_url': url, 'checked_at': nowIso()});
        lib.update(t['path'] as String, fields);
      } catch (_) {
        failed++; // seguimos con las demás
      }
      await Future<void>.delayed(const Duration(milliseconds: 500)); // no saturar modarchive
    }
    checking = false;
    notify('Comprobadas ${tracks.length} canciones: $updated actualizadas${failed > 0 ? ', $failed con error' : ''}');
    renderLibrary();
  }

  // ---------------------------------------------------------- reproducción

  void playIndex(int idx) {
    if (idx < 0 || idx >= queue.length) return;
    qpos = idx;
    playToken++;
    final item = queue[idx];
    note = noteTitle = null;
    if (item is Map) {
      _startTrack(item as Track);
    } else if (lib.byMaId((item as Module).id) case final t?) {
      _startTrack(t);
    } else {
      player.stop();
      noteTitle = item.title;
      note = 'Descargando…';
      notifyListeners();
      download(item, playToken);
    }
  }

  void _startTrack(Track track) {
    final path = track['path'] as String;
    if (!File(path).existsSync()) {
      notify('No existe $path', error: true);
      return;
    }
    note = noteTitle = null;
    player.play(track);
    if (!vu.containsKey(path)) {
      vu[path] = null;
      vuEnvelope(path).then((env) => vu[path] = env);
    }
    lib.played(path);
    renderLibrary();
  }

  /// Niveles (izquierdo, derecho) del vúmetro en este instante, o null si no suena nada.
  (double, double)? vuNow() {
    final t = player.track;
    if (t == null || !player.active || player.paused) return null;
    final env = vu[t['path']];
    final i = (player.position * vuFps).toInt();
    if (env == null || i * 2 + 1 >= env.length) return null;
    return (env[i * 2], env[i * 2 + 1]);
  }

  void _tick() {
    if (player.finished) {
      player.markFinished();
      if (qpos + 1 < queue.length) {
        playIndex(qpos + 1);
      } else {
        renderLibrary();
      }
    }
  }

  /// Pausa o reanuda; si no suena nada, reproduce [fallback] (la fila seleccionada).
  void playPause([void Function()? fallback]) {
    if (player.active) {
      player.togglePause();
      notifyListeners();
    } else {
      fallback?.call();
    }
  }

  void stop() {
    playToken++;
    note = noteTitle = null;
    player.stop();
    renderLibrary();
  }

  void next() => playIndex(qpos + 1);

  void prev() {
    if (player.position > 5) {
      player.restartAt(0);
      notifyListeners();
    } else {
      playIndex(qpos - 1);
    }
  }

  void seek(double delta) => seekTo(player.position + delta);

  void seekTo(double pos) {
    player.restartAt(pos);
    notifyListeners();
  }

  void setVolume(int gain) {
    gain = gain.clamp(-30, 12);
    if (gain == player.gain) return;
    player.gain = gain;
    player.restartAt(player.position);
    notifyListeners();
  }

  // ---------------------------------------------------------- biblioteca

  Future<void> scanLibrary() async {
    final token = ++_scanToken;
    final known = {for (final t in lib.all()) t['path'] as String};
    final files = <String>{};
    try {
      await for (final e in Directory(musicDir).list(recursive: true, followLinks: false)) {
        if (exts.contains(extOf(e.path).toLowerCase()) && FileSystemEntity.isFileSync(e.path)) files.add(e.path);
      }
    } on FileSystemException catch (e) {
      notify('No se pudo leer $musicDir: ${e.message}', error: true);
    }
    for (final p in known.difference(files)) {
      lib.remove(p);
    }
    final added = files.difference(known).toList()..sort();
    for (var n = 0; n < added.length; n++) {
      if (token != _scanToken) return;
      if (n % 10 == 0) {
        libStatus = 'Escaneando ${n + 1}/${added.length}…';
        notifyListeners();
      }
      final path = added[n];
      final info = await openmptInfo(path);
      final name = path.split('/').last;
      final ext = extOf(name);
      lib.add({
        'path': path, 'filename': name,
        'title': str(info['title']) ?? (ext.isEmpty ? name : name.substring(0, name.length - ext.length - 1)),
        'artist': info['artist'], 'format': ext.toUpperCase(), 'channels': info['channels'], 'duration': info['duration'],
      });
    }
    renderLibrary();
  }

  void setFilter(String q) {
    filter = q;
    renderLibrary();
  }

  void renderLibrary() {
    var tracks = lib.all();
    final q = filter.trim().toLowerCase();
    if (q.isNotEmpty) {
      tracks = [
        for (final t in tracks)
          if (['title', 'artist', 'filename', 'genre'].any((k) => (str(t[k]) ?? '').toLowerCase().contains(q))) t,
      ];
    }
    final key = libSortKeys[libSort];
    String title(Track t) => (str(t['title']) ?? str(t['filename']) ?? '').toLowerCase();
    String artist(Track t) => (str(t['artist']) ?? '~').toLowerCase(); // «~» deja los desconocidos al final
    int byTitle(Track a, Track b) => title(a).compareTo(title(b));
    int intOf(Track t, String k) => (t[k] as int?) ?? 0;
    int desc(Track a, Track b, String k) {
      final c = intOf(b, k).compareTo(intOf(a, k));
      return c != 0 ? c : byTitle(a, b);
    }

    tracks = switch (key) {
      'alfa' => sortedBy(tracks, byTitle),
      'artista' => sortedBy(tracks, (a, b) {
          final c = artist(a).compareTo(artist(b));
          return c != 0 ? c : byTitle(a, b);
        }),
      'popular' => sortedBy(tracks, (a, b) => desc(a, b, 'ma_downloads')),
      'escuchadas' => sortedBy(tracks, (a, b) => desc(a, b, 'plays')),
      'recientes' => sortedBy(tracks, (a, b) => (str(b['added_at']) ?? '').compareTo(str(a['added_at']) ?? '')),
      _ => sortedBy(tracks.where((t) => intOf(t, 'favorite') != 0), byTitle),
    };

    libItems = [];
    if (key == 'artista') {
      final counts = <String, int>{};
      for (final t in tracks) {
        counts[artist(t)] = (counts[artist(t)] ?? 0) + 1;
      }
      String? last;
      for (final t in tracks) {
        if (artist(t) != last) {
          last = artist(t);
          libItems.add('${str(t['artist']) ?? 'Artista desconocido'} · ${counts[last]}');
        }
        libItems.add(t);
      }
    } else {
      libItems.addAll(tracks);
    }
    if (!checking) libStatus = '${tracks.length} canciones en $musicDir';
    notifyListeners();
  }

  void selectLibrary(Track track) {
    queue = [for (final t in libItems) if (t is Map) t];
    playIndex(queue.indexWhere((t) => (t as Track)['path'] == track['path']));
  }

  void toggleFavorite(Track track) {
    lib.toggleFavorite(track['path'] as String);
    renderLibrary();
  }

  bool isPlaying(Object item) {
    final t = player.track;
    if (t == null || !player.active) return false;
    return item is Map ? item['path'] == t['path'] : item is Module && t['ma_id'] == item.id;
  }
}
