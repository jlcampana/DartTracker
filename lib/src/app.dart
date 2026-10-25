// La aplicación: explorador de modarchive, biblioteca y reproductor.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'library.dart';
import 'modarchive.dart';
import 'player.dart';
import 'ui.dart';

const version = '1.1.0';

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

int formatColor(String f) => switch (f.toUpperCase()) {
      'XM' => C.purple,
      'IT' => C.teal,
      'MOD' => C.orange,
      'S3M' => C.pink,
      'MPTM' => C.green,
      _ => C.secondary,
    };

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

class SideItem {
  final String key, icon, label;
  const SideItem(this.key, this.icon, this.label);
  bool get header => icon.isEmpty;
}

const sideItems = [
  SideItem('h:ma', '', 'MODARCHIVE'),
  SideItem('buscar', '⌕', 'Buscar canción'),
  SideItem('artista', '☺', 'Buscar artista'),
  SideItem('tophits', '↓', 'Más descargadas'),
  SideItem('topscore', '★', 'Mejor puntuadas'),
  SideItem('favs', '♥', 'Top favoritas'),
  SideItem('featured', '◆', 'Destacadas'),
  SideItem('generos', '♫', 'Géneros'),
  SideItem('az', '#', 'A-Z'),
  SideItem('random', '⚄', 'Aleatorias'),
  SideItem('h:lib', '', 'BIBLIOTECA'),
  SideItem('lib:0', '♪', 'Canciones'),
  SideItem('lib:1', '☺', 'Por artista'),
  SideItem('lib:2', '▲', 'Populares'),
  SideItem('lib:3', '↻', 'Más escuchadas'),
  SideItem('lib:4', '◷', 'Recientes'),
  SideItem('lib:5', '★', 'Favoritas'),
];

final views = {
  'tophits': ('Más descargadas', {'request': 'view_chart', 'query': 'tophits'}),
  'topscore': ('Mejor puntuadas', {'request': 'view_chart', 'query': 'topscore'}),
  'featured': ('Destacadas', {'request': 'view_chart', 'query': 'featured'}),
  'favs': ('Favoritas de la gente', {'request': 'view_top_favourites'}),
};
const resultSorts = ['web', 'alfabético', 'popularidad'];
const libSorts = [
  ('alfa', 'Alfabético'), ('artista', 'Por artista'), ('popular', 'Populares en modarchive'),
  ('escuchadas', 'Más escuchadas'), ('recientes', 'Añadidas recientemente'), ('favoritas', 'Favoritas'),
];

class Toast {
  final String text;
  final bool error;
  final DateTime until;
  Toast(this.text, this.error) : until = DateTime.now().add(const Duration(seconds: 5));
}

class App {
  final screen = Screen();
  final lib = Library(dbPath);
  final player = Player();

  // explorador
  View? view;
  final history = <View>[];
  List<Object> rows = [], shown = [];
  int resultSort = 0, viewToken = 0;
  String searchMode = 'song';
  String heading = '', status = '';

  // biblioteca
  int libSort = 0, scanToken = 0;
  List<Track?> libRows = [];
  String libStatus = '';
  bool checking = false;

  final search = TextField('Buscar canción en modarchive (Enter)');
  final filter = TextField('Filtrar por título, artista, archivo o género');
  final results = Table()..empty = 'Sin resultados';
  final library = Table()..empty = 'La biblioteca está vacía: descarga algo desde modarchive';

  String pane = 'explore'; // explore | library
  String focus = 'results'; // sidebar | search | results | filter | library
  int side = 3; // fila de la barra lateral bajo el cursor
  String activeSide = 'tophits';

  // reproducción
  List<Object> queue = []; // Module o Track
  int qpos = -1, playToken = 0;
  String? note; // «Descargando…», «Error de descarga»
  String? noteTitle;
  final vu = <String, Float32List?>{};
  final levels = [0.0, 0.0], peaks = [0.0, 0.0], peakAt = [0.0, 0.0];
  bool vuIdle = true;
  final _clock = Stopwatch()..start();

  final toasts = <Toast>[];
  List<Hit> hits = [];
  bool dirty = true, quitting = false;

  Future<void> run() async {
    Directory(musicDir).createSync(recursive: true);
    screen.enter();
    ProcessSignal.sigint.watch().listen((_) => quit());
    ProcessSignal.sigterm.watch().listen((_) => quit());
    ProcessSignal.sigwinch.watch().listen((_) {
      screen.invalidate();
      dirty = true;
    });
    stdin.listen((bytes) {
      for (final e in parseInput(utf8.decode(bytes, allowMalformed: true))) {
        e is Mouse ? onMouse(e) : onKey(e as String);
      }
      render();
    });
    Timer.periodic(const Duration(milliseconds: 500), (_) => tick());
    Timer.periodic(const Duration(microseconds: 1000000 ~/ vuFps), (_) {
      drawVu();
      if (dirty) render();
    });
    openMenu('tophits');
    focus = 'results';
    unawaited(scanLibrary());
    render();
  }

  Future<void> quit() async {
    if (quitting) return;
    quitting = true;
    await player.dispose();
    screen.leave();
    exit(0);
  }

  void notify(String msg, {bool error = false}) {
    toasts.add(Toast(msg, error));
    if (toasts.length > 4) toasts.removeAt(0);
    dirty = true;
  }

  // ---------------------------------------------------------- teclado y ratón

  List<String> get focusOrder => pane == 'explore' ? ['sidebar', 'search', 'results'] : ['sidebar', 'filter', 'library'];
  String get tableFocus => pane == 'explore' ? 'results' : 'library';

  void onKey(String k) {
    dirty = true;
    if (k == 'ctrl+c') {
      quit();
      return;
    }
    if (k == 'tab' || k == 'shift+tab') {
      final o = focusOrder;
      focus = o[(o.indexOf(focus) + (k == 'tab' ? 1 : o.length - 1)) % o.length];
      return;
    }
    if (focus == 'search' || focus == 'filter') {
      if (k == 'escape' || k == 'down') {
        focus = tableFocus;
      } else if (k == 'enter') {
        if (focus == 'search') {
          submitSearch();
        } else {
          focus = 'library';
        }
      } else if (focus == 'search') {
        search.key(k, () {});
      } else {
        filter.key(k, renderLibrary);
      }
      return;
    }
    if (focus == 'sidebar' && sideKey(k)) return;
    if (focus == 'results' && resultsKey(k)) return;
    if (focus == 'library' && libraryKey(k)) return;
    switch (k) {
      case 'q':
        quit();
      case '1':
        actionTab('explore');
      case '2':
        actionTab('library');
      case ' ':
        actionPause();
      case 's':
        actionStop();
      case 'n':
        actionNext();
      case 'b':
        actionPrev();
      case ',':
        actionSeek(-10);
      case '.':
        actionSeek(10);
      case '-':
        actionVolume(-3);
      case '+':
        actionVolume(3);
      case '/':
        focus = pane == 'explore' ? 'search' : 'filter';
    }
  }

  bool sideKey(String k) {
    int step(int d) {
      var i = side;
      do {
        i += d;
      } while (i >= 0 && i < sideItems.length && sideItems[i].header);
      return i >= 0 && i < sideItems.length ? i : side;
    }

    switch (k) {
      case 'up':
        side = step(-1);
      case 'down':
        side = step(1);
      case 'enter':
        activateSide(side);
      case 'right' || 'escape':
        focus = tableFocus;
      default:
        return false;
    }
    return true;
  }

  bool resultsKey(String k) {
    switch (k) {
      case ']':
        actionPage(1);
      case '[':
        actionPage(-1);
      case 'backspace' || 'escape':
        actionBack();
      case 'd':
        actionDownloadOnly();
      case 'o':
        actionSortResults();
      case 'enter':
        selectResult(results.cursor);
      case 'left':
        focus = 'sidebar';
      // Av Pág en la última fila pide la página siguiente; Re Pág en la primera, la anterior
      case 'pagedown' when results.length > 0 && results.cursor >= results.length - 1:
        actionPage(1);
      case 'pageup' when results.cursor <= 0:
        actionPage(-1, cursorEnd: true);
      default:
        return results.key(k);
    }
    return true;
  }

  bool libraryKey(String k) {
    switch (k) {
      case 'o':
        actionSortLibrary();
      case 'f':
        actionFavorite();
      case 'r':
        scanLibrary();
      case 'u':
        checkUpdates();
      case 'enter':
        selectLibrary(library.cursor);
      case 'left':
        focus = 'sidebar';
      default:
        return library.key(k);
    }
    return true;
  }

  void onMouse(Mouse m) {
    if (!m.press) return;
    dirty = true;
    for (final h in hits.reversed) {
      if (!h.contains(m.x, m.y)) continue;
      if (m.button == 0 && h.onClick != null) {
        h.onClick!(m.x, m.y);
        return;
      }
      if ((m.button == 64 || m.button == 65) && h.onWheel != null) {
        h.onWheel!(m.button == 64 ? -1 : 1);
        return;
      }
    }
  }

  // ---------------------------------------------------------- explorador

  void activateSide(int i) {
    side = i;
    final key = sideItems[i].key;
    if (key.startsWith('lib:')) {
      activeSide = key;
      libSort = int.parse(key.substring(4));
      pane = 'library';
      focus = 'library';
      renderLibrary(keepCursor: false);
      return;
    }
    pane = 'explore';
    openMenu(key);
  }

  void openMenu(String key) {
    side = sideItems.indexWhere((s) => s.key == key);
    if (key == 'buscar' || key == 'artista') {
      searchMode = key == 'buscar' ? 'song' : 'artist';
      search.placeholder = key == 'buscar' ? 'Buscar canción en modarchive (Enter)' : 'Buscar artista en modarchive (Enter)';
      activeSide = key;
      focus = 'search';
      return;
    }
    activeSide = key;
    history.clear();
    if (views[key] case (final title, final params)?) {
      loadView(View('modules', title, params));
    } else if (key == 'generos') {
      loadView(View('genres', 'Géneros', {'request': 'view_genres'}));
    } else if (key == 'az') {
      showView(View('letters', 'A-Z'), [for (final c in '0ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')) Entry(c, c)]);
    } else if (key == 'random') {
      loadView(View('modules', 'Aleatorias', {'request': 'zomg_random'}));
    }
    focus = 'results';
  }

  void submitSearch() {
    final q = search.value.trim();
    if (q.isEmpty) return;
    history.clear();
    activeSide = searchMode == 'song' ? 'buscar' : 'artista';
    side = sideItems.indexWhere((s) => s.key == activeSide);
    if (searchMode == 'song') {
      loadView(View('modules', 'Búsqueda: $q',
          {'request': 'search', 'query': q, 'submit': 'Find', 'search_type': 'filename_or_songtitle'}));
    } else {
      loadView(View('artists', 'Artistas: $q', {'request': 'search', 'query': q, 'submit': 'Find', 'search_type': 'search_artist'}));
    }
    focus = 'results';
  }

  Future<void> loadView(View v, {bool cursorEnd = false}) async {
    final token = ++viewToken;
    heading = v.title;
    status = 'Cargando…';
    dirty = true;
    try {
      final doc = await fetch(pageUrl(v.params!, v.page));
      if (token != viewToken) return;
      final List<Object> found = switch (v.kind) {
        'modules' => parseModules(doc),
        'genres' => parseGenres(doc),
        _ => parseArtists(doc),
      };
      v.pages = math.max(parsePages(doc), v.page);
      showView(v, found, cursorEnd: cursorEnd);
    } catch (e) {
      if (token != viewToken) return;
      status = 'Error cargando ${v.title}: $e';
      dirty = true;
    }
  }

  void showView(View v, List<Object> found, {bool cursorEnd = false}) {
    view = v;
    rows = found;
    resultSort = 0;
    renderResults();
    if (cursorEnd && found.isNotEmpty) results.moveTo(found.length - 1);
  }

  void renderResults({bool keep = false}) {
    final v = view;
    if (v == null) return;
    var extra = '';
    if (v.kind == 'modules') {
      final sort = resultSorts[resultSort];
      final mods = rows.cast<Module>();
      shown = switch (sort) {
        'alfabético' => sortedBy<Module>(mods, (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase())),
        'popularidad' => sortedBy<Module>(mods, (a, b) => b.pop.compareTo(a.pop)),
        _ => List.of(mods),
      };
      final have = lib.maIds();
      results.set([
        const Col(' '), const Col('Título', shrink: true, weight: 2), const Col('Archivo', shrink: true), const Col('Formato'),
        const Col('Popularidad', right: true),
      ], [
        for (final m in shown.cast<Module>())
          [
            Span(have.contains(m.id) ? '✓' : '', fg: C.green, attr: bold), Span(m.title),
            Span(m.filename, fg: C.secondary), Span(m.format, fg: formatColor(m.format), attr: bold),
            Span(m.info, fg: C.secondary),
          ],
      ], keep: keep);
      extra = ' · orden: $sort (o)';
    } else {
      shown = rows;
      results.set([
        Col(switch (v.kind) { 'genres' => 'Género', 'artists' => 'Artista', _ => 'Letra' }, shrink: true),
      ], [
        for (final e in rows.cast<Entry>()) [Span(e.name)],
      ], keep: keep);
    }
    final pages = v.pages > 1 ? ' · página ${v.page}/${v.pages} ([ ])' : '';
    final back = history.isNotEmpty ? ' · ⌫ volver' : '';
    heading = v.title;
    status = '${shown.length} resultados$pages$extra$back';
    dirty = true;
  }

  void selectResult(int idx) {
    final v = view;
    if (v == null || idx >= shown.length) return;
    final row = shown[idx];
    if (v.kind == 'modules') {
      queue = List.of(shown);
      playIndex(idx);
      return;
    }
    final e = row as Entry;
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

  void actionPage(int delta, {bool cursorEnd = false}) {
    final v = view;
    if (v != null && v.params != null && v.page + delta >= 1 && v.page + delta <= v.pages) {
      loadView(v.atPage(v.page + delta), cursorEnd: cursorEnd);
    }
  }

  void actionBack() {
    if (history.isNotEmpty) loadView(history.removeLast());
  }

  void actionSortResults() {
    if (view?.kind == 'modules') {
      resultSort = (resultSort + 1) % resultSorts.length;
      renderResults();
    }
  }

  void actionDownloadOnly() {
    if (view?.kind == 'modules' && shown.isNotEmpty) downloadWorker(shown[results.cursor] as Module, null);
  }

  // ---------------------------------------------------------- descargas

  /// Descarga un módulo (si no está ya) y lo registra en la biblioteca.
  Future<Track> download(Module mod) async {
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

  Future<void> downloadWorker(Module mod, int? token) async {
    if (token == null) notify('Descargando ${mod.filename}…');
    Track track;
    try {
      track = await download(mod);
    } catch (e) {
      notify('No se pudo descargar ${mod.filename}: $e', error: true);
      if (token == playToken) {
        note = 'Error de descarga';
        dirty = true;
      }
      return;
    }
    if (view?.kind == 'modules') renderResults(keep: true);
    renderLibrary();
    if (token == null) {
      notify('Guardado en $musicDir: ${track['path'].toString().split('/').last}');
    } else if (token == playToken) {
      startTrack(track);
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
      dirty = true;
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
      startTrack(item as Track);
    } else if (lib.byMaId((item as Module).id) case final t?) {
      startTrack(t);
    } else {
      player.stop();
      noteTitle = item.title;
      note = 'Descargando…';
      dirty = true;
      downloadWorker(item, playToken);
    }
  }

  void startTrack(Track track) {
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

  void drawVu() {
    Float32List? env;
    var i = -1;
    if (player.track != null && player.active && !player.paused) {
      env = vu[player.track!['path']];
      i = (player.position * vuFps).toInt();
    }
    final now = _clock.elapsedMicroseconds / 1e6;
    for (var c = 0; c < 2; c++) {
      final t = env != null && i >= 0 && i * 2 + 1 < env.length ? env[i * 2 + c] : 0.0;
      // sube al instante y baja poco a poco, como un vúmetro de verdad
      levels[c] = t > levels[c] ? t : math.max(t, levels[c] - 0.05);
      if (levels[c] >= peaks[c]) {
        peaks[c] = levels[c];
        peakAt[c] = now;
      } else if (now - peakAt[c] > 0.6) {
        peaks[c] = math.max(levels[c], peaks[c] - 0.015);
      }
    }
    final idle = levels.every((l) => l == 0) && peaks.every((p) => p == 0);
    if (!idle || !vuIdle) dirty = true;
    vuIdle = idle;
    if (toasts.isNotEmpty) dirty = true;
  }

  void tick() {
    if (player.finished) {
      player.markFinished();
      if (qpos + 1 < queue.length) playIndex(qpos + 1);
    }
    dirty = true;
  }

  void actionPause() {
    if (player.active) {
      player.togglePause();
    } else if (pane == 'explore' && view?.kind == 'modules') {
      selectResult(results.cursor);
    } else if (pane == 'library') {
      selectLibrary(library.cursor);
    }
  }

  void actionStop() {
    playToken++;
    note = noteTitle = null;
    player.stop();
    renderLibrary();
  }

  void actionNext() => playIndex(qpos + 1);

  void actionPrev() {
    if (player.position > 5) {
      player.restartAt(0);
    } else {
      playIndex(qpos - 1);
    }
  }

  void actionSeek(double delta) => player.restartAt(player.position + delta);

  void setVolume(int gain) {
    gain = gain.clamp(-30, 12);
    if (gain == player.gain) return;
    player.gain = gain;
    player.restartAt(player.position);
  }

  void actionVolume(int delta) => setVolume(player.gain + delta);

  void actionTab(String p) {
    pane = p;
    focus = tableFocus;
    if (p == 'library' && !activeSide.startsWith('lib:')) activeSide = 'lib:$libSort';
    side = sideItems.indexWhere((s) => s.key == (p == 'library' ? 'lib:$libSort' : activeSide));
    if (side < 0) side = 1;
  }

  // ---------------------------------------------------------- biblioteca

  Future<void> scanLibrary() async {
    final token = ++scanToken;
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
      if (token != scanToken) return;
      if (n % 10 == 0) {
        libStatus = 'Escaneando ${n + 1}/${added.length}…';
        dirty = true;
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

  void renderLibrary({bool keepCursor = true}) {
    var tracks = lib.all();
    final q = filter.value.trim().toLowerCase();
    if (q.isNotEmpty) {
      tracks = [
        for (final t in tracks)
          if (['title', 'artist', 'filename', 'genre'].any((k) => (str(t[k]) ?? '').toLowerCase().contains(q))) t,
      ];
    }
    final (key, label) = libSorts[libSort];
    String title(Track t) => (str(t['title']) ?? str(t['filename']) ?? '').toLowerCase();
    String artist(Track t) => (str(t['artist']) ?? '~').toLowerCase(); // «~» deja los desconocidos al final
    int byTitle(Track a, Track b) => title(a).compareTo(title(b));
    int intOf(Track t, String k) => (t[k] as int?) ?? 0;
    tracks = switch (key) {
      'alfa' => sortedBy(tracks, byTitle),
      'artista' => sortedBy(tracks, (a, b) {
          final c = artist(a).compareTo(artist(b));
          return c != 0 ? c : byTitle(a, b);
        }),
      'popular' => sortedBy(tracks, (a, b) {
          final c = intOf(b, 'ma_downloads').compareTo(intOf(a, 'ma_downloads'));
          return c != 0 ? c : byTitle(a, b);
        }),
      'escuchadas' => sortedBy(tracks, (a, b) {
          final c = intOf(b, 'plays').compareTo(intOf(a, 'plays'));
          return c != 0 ? c : byTitle(a, b);
        }),
      'recientes' => sortedBy(tracks, (a, b) => (str(b['added_at']) ?? '').compareTo(str(a['added_at']) ?? '')),
      _ => sortedBy(tracks.where((t) => intOf(t, 'favorite') != 0), byTitle),
    };

    final playing = player.active ? player.track!['path'] : null;
    final counts = <String, int>{};
    if (key == 'artista') {
      for (final t in tracks) {
        counts[artist(t)] = (counts[artist(t)] ?? 0) + 1;
      }
    }
    libRows = [];
    final out = <List<Span>>[];
    String? lastArtist;
    for (final t in tracks) {
      if (key == 'artista' && artist(t) != lastArtist) {
        lastArtist = artist(t);
        final name = str(t['artist']) ?? 'Artista desconocido';
        out.add([const Span(''), Span('▾ $name (${counts[lastArtist]})', attr: bold), for (var i = 0; i < 5; i++) const Span('')]);
        libRows.add(null);
      }
      final isPlaying = t['path'] == playing;
      final fmt = str(t['format']) ?? '';
      out.add([
        Span(intOf(t, 'favorite') != 0 ? '★' : '', fg: C.yellow),
        Span((isPlaying ? '▶ ' : '') + (str(t['title']) ?? str(t['filename']) ?? ''),
            fg: isPlaying ? C.green : C.text, attr: isPlaying ? bold : 0),
        Span(str(t['artist']) ?? '', fg: C.secondary),
        Span(fmt, fg: formatColor(fmt), attr: bold),
        Span(fmtTime(t['duration'] as num?), fg: C.secondary),
        Span(intOf(t, 'ma_downloads') > 0 ? thousands(intOf(t, 'ma_downloads')) : '', fg: C.secondary),
        Span(intOf(t, 'plays') > 0 ? '${t['plays']}' : '', fg: C.secondary),
      ]);
      libRows.add(t);
    }
    library.set([
      const Col('★'), const Col('Título', shrink: true, weight: 2), const Col('Artista', shrink: true), const Col('Formato'),
      const Col('Duración', right: true), const Col('Descargas MA', right: true), const Col('Escuchas', right: true),
    ], out, keep: keepCursor);
    library.empty = q.isNotEmpty
        ? 'Nada coincide con «${filter.value.trim()}»'
        : 'La biblioteca está vacía: descarga algo desde modarchive';
    if (!checking) {
      final n = libRows.where((t) => t != null).length;
      libStatus = '$n canciones · orden: $label (o) · f favorita · r reescanear · u buscar actualizaciones';
    }
    dirty = true;
  }

  void selectLibrary(int idx) {
    if (idx >= libRows.length) return;
    final track = libRows[idx];
    if (track == null) return;
    queue = [for (final t in libRows) if (t != null) t];
    playIndex(queue.indexOf(track));
  }

  void actionSortLibrary() {
    libSort = (libSort + 1) % libSorts.length;
    activeSide = 'lib:$libSort';
    side = sideItems.indexWhere((s) => s.key == activeSide);
    renderLibrary(keepCursor: false);
  }

  void actionFavorite() {
    final t = libRows.isEmpty ? null : libRows[library.cursor];
    if (t == null) return;
    lib.toggleFavorite(t['path'] as String);
    renderLibrary();
  }

  // ---------------------------------------------------------- dibujo

  int sideW = 28; // en terminales estrechas la barra lateral se queda en solo iconos

  void render() {
    dirty = false;
    final w = stdout.hasTerminal ? stdout.terminalColumns : 100;
    final h = stdout.hasTerminal ? stdout.terminalLines : 30;
    final c = Canvas(w, h);
    if (w < 70 || h < 20) {
      final msg = 'Agranda la ventana (mínimo 70×20)';
      c.text(math.max(0, (w - textWidth(msg)) ~/ 2), h ~/ 2, msg, fg: C.secondary);
      hits = [];
      screen.draw(c);
      return;
    }
    final bodyEnd = h - 9; // última fila del cuerpo
    sideW = w >= 110 ? 28 : 6;
    drawTitleBar(c, w);
    drawSidebar(c, 1, bodyEnd);
    final cx = sideW + 2, cw = w - sideW - 4;
    if (pane == 'explore') {
      drawPane(c, cx, cw, bodyEnd, search, 'search', heading, status, results, 'results',
          (row, again) => again ? selectResult(row) : null);
    } else {
      final (_, label) = libSorts[libSort];
      drawPane(c, cx, cw, bodyEnd, filter, 'filter', 'Biblioteca · $label', libStatus, library, 'library',
          (row, again) => again ? selectLibrary(row) : null);
    }
    drawPlayer(c, w, h - 8);
    drawFooter(c, w, h - 1);
    drawToasts(c, w, bodyEnd);
    hits = c.hits;
    screen.draw(c);
  }

  void drawTitleBar(Canvas c, int w) {
    c.fill(0, 0, w, 1, C.sidebar);
    c.text(2, 0, '●', fg: C.red);
    c.text(4, 0, '●', fg: C.yellow);
    c.text(6, 0, '●', fg: C.green);
    c.hit(2, 0, 1, 1, onClick: (_, _) => quit());
    const title = 'DartTracker';
    final sub = pane == 'explore' ? '  ·  Explorar modarchive' : '  ·  Biblioteca';
    final tx = (w - textWidth(title + sub)) ~/ 2;
    c.text(tx, 0, 'Dart', fg: C.accent, attr: bold);
    c.text(tx + 4, 0, 'Tracker', attr: bold);
    c.text(tx + title.length, 0, sub, fg: C.secondary);
    // pestañas tipo control segmentado, a la derecha
    var x = w - 30;
    if (tx + textWidth(title + sub) + 2 > x) return;
    for (final (p, label) in [('explore', ' Explorar '), ('library', ' Biblioteca ')]) {
      final on = pane == p;
      final n = c.pill(x, 0, label, bg: on ? C.controlHi : C.card, fg: on ? C.text : C.secondary, attr: on ? bold : 0);
      c.hit(x, 0, n, 1, onClick: (_, _) => actionTab(p));
      x += n;
    }
  }

  void drawSidebar(Canvas c, int top, int bottom) {
    c.fill(0, top, sideW, bottom - top + 1, C.sidebar);
    final focused = focus == 'sidebar';
    final rowsAvail = bottom - top;
    var y = top + 1;
    // si no cabe todo, desplaza para que se vea la fila del cursor
    final skip = math.max(0, side + 2 - rowsAvail);
    for (var i = skip; i < sideItems.length && y <= bottom; i++, y++) {
      final it = sideItems[i];
      if (it.header) {
        if (i > skip && i > 0) y++;
        if (y > bottom) break;
        c.text(2, y, sideW > 6 ? it.label : '──', fg: C.tertiary, attr: bold);
        continue;
      }
      final cur = i == side && focused;
      final active = it.key == activeSide && (pane == 'library') == it.key.startsWith('lib:');
      if (cur || active) c.pill(1, y, ' ' * (sideW - 4), bg: cur ? C.accent : C.control);
      c.text(3, y, it.icon, fg: cur ? C.text : C.accent, attr: bold);
      if (sideW > 6) c.text(6, y, fit(it.label, sideW - 8), fg: C.text, attr: active ? bold : 0);
      final idx = i;
      c.hit(0, y, sideW, 1, onClick: (_, _) {
        focus = 'sidebar';
        activateSide(idx);
      });
    }
    c.hit(0, top, sideW, bottom - top + 1, onWheel: (d) => sideKey(d < 0 ? 'up' : 'down'));
  }

  void drawPane(Canvas c, int x, int w, int bottom, TextField field, String fieldFocus, String title, String info,
      Table table, String tableName, void Function(int row, bool again) onRow) {
    field.draw(c, x, 2, w, focused: focus == fieldFocus, icon: fieldFocus == 'search' ? '⌕' : '≡');
    c.hit(x, 2, w, 1, onClick: (_, _) => focus = fieldFocus);
    c.text(x + 1, 4, fit(title, w - 2), attr: bold);
    c.text(x + 1, 5, fit(info, w - 2), fg: info.startsWith('Error') ? C.red : C.secondary);
    table.draw(c, x, 7, w, bottom - 6, focused: focus == tableName, bg: C.window, onClick: (row, again) {
      focus = tableName;
      onRow(row, again);
    });
  }

  void drawPlayer(Canvas c, int w, int top) {
    c.card(1, top, w - 2, 7, C.card);
    final t = player.track;
    final playing = player.active;
    final duration = (t?['duration'] as num?)?.toDouble() ?? 0;
    final pos = duration > 0 ? math.min(player.position, duration) : player.position;

    // botones en el centro
    final buttons = <(String, void Function(), bool)>[
      (' ◀◀ ', actionPrev, false),
      (' ↺ ', () => actionSeek(-10), false),
      (playing && !player.paused ? '  ❚❚  ' : '  ▶  ', actionPause, true),
      (' ↻ ', () => actionSeek(10), false),
      (' ▶▶ ', actionNext, false),
      (' ■ ', actionStop, false),
    ];
    final bw = buttons.fold(0, (a, b) => a + textWidth(b.$1) + 3) - 1;
    var bx = (w - bw) ~/ 2;
    final by = top + 1;
    for (final (label, action, primary) in buttons) {
      final n = c.pill(bx, by, label, bg: primary ? C.accent : C.control, attr: bold);
      c.hit(bx, by, n, 1, onClick: (_, _) => action());
      bx += n + 1;
    }

    // canción a la izquierda
    final leftW = (w - bw) ~/ 2 - 6;
    final title = noteTitle ?? (t == null ? null : str(t['title']) ?? str(t['filename']));
    if (title != null) {
      c.text(4, by, fit(title, leftW), attr: bold);
      final artist = noteTitle != null ? '' : str(t!['artist']) ?? 'artista desconocido';
      final fmt = t == null || noteTitle != null ? '' : str(t['format']) ?? extOf(t['path'] as String).toUpperCase();
      final ch = t?['channels'];
      final x = 4 + c.text(4, by + 1, fit(artist, leftW), fg: C.secondary);
      if (fmt.isNotEmpty && x + 2 + fmt.length < 4 + leftW) {
        c.text(x + 2 + c.text(x + 2, by + 1, fmt, fg: formatColor(fmt), attr: bold), by + 1,
            ch != null ? ' · $ch canales' : '', fg: C.tertiary, maxW: 4 + leftW - x - 2 - fmt.length);
      }
    } else {
      c.text(4, by, 'Nada sonando', fg: C.secondary, attr: bold);
      c.text(4, by + 1, fit('Elige una canción y pulsa Enter', leftW), fg: C.tertiary);
    }

    // estado bajo los botones
    final state = note ??
        (playing ? (player.paused ? 'En pausa' : 'Reproduciendo') : 'Parado') +
            (queue.isNotEmpty && qpos >= 0 && playing ? ' · ${qpos + 1} de ${queue.length}' : '');
    c.text((w - textWidth(state)) ~/ 2, by + 1, state, fg: note == 'Error de descarga' ? C.red : C.tertiary);

    // volumen a la derecha
    final vx = (w + bw) ~/ 2 + 4, vw = w - 4 - vx;
    if (vw >= 22) {
      const sliderW = 12;
      var x = w - 4 - (sliderW + 12);
      final n1 = c.pill(x, by, ' − ', bg: C.control);
      c.hit(x, by, n1, 1, onClick: (_, _) => actionVolume(-3));
      x += n1 + 1;
      final frac = (player.gain + 30) / 42;
      final knob = (frac * (sliderW - 1)).round();
      for (var i = 0; i < sliderW; i++) {
        c.text(x + i, by, i == knob ? '●' : '━', fg: i == knob ? C.text : i < knob ? C.accent : C.controlHi);
      }
      final sx = x;
      c.hit(sx, by, sliderW, 1, onClick: (px, _) => setVolume((((px - sx) / (sliderW - 1) * 42 - 30) / 3).round() * 3));
      x += sliderW + 1;
      final n2 = c.pill(x, by, ' + ', bg: C.control);
      c.hit(x, by, n2, 1, onClick: (_, _) => actionVolume(3));
      final vol = 'volumen ${player.gain > 0 ? '+' : ''}${player.gain} dB';
      c.text(w - 4 - textWidth(vol), by + 1, vol, fg: C.tertiary);
    } else if (player.gain != 0) {
      final vol = 'vol ${player.gain > 0 ? '+' : ''}${player.gain} dB';
      c.text(w - 4 - textWidth(vol), by + 1, vol, fg: C.tertiary);
    }

    // barra de progreso
    final py = top + 3;
    final t0 = fmtTime(pos), t1 = fmtTime(duration);
    c.text(4, py, t0, fg: C.secondary);
    c.text(w - 4 - t1.length, py, t1, fg: C.secondary);
    final px = 4 + t0.length + 2, pw = w - 8 - t0.length - t1.length - 4;
    final done = duration > 0 ? (pos / duration * pw).round().clamp(0, pw) : 0;
    for (var i = 0; i < pw; i++) {
      final knob = playing && duration > 0 && i == math.min(done, pw - 1);
      c.text(px + i, py, knob ? '●' : '━', fg: knob ? C.text : i < done ? mix(C.accent, C.teal, i / pw) : C.control);
    }
    c.hit(px, py, pw, 1, onClick: (x, _) {
      if (duration > 0) player.restartAt((x - px) / pw * duration);
    });

    // vúmetro: el canal izquierdo crece hacia la izquierda y el derecho hacia la derecha
    final vy = top + 5;
    final half = math.max(1, (w - 14) ~/ 2);
    final mid = w ~/ 2;
    c.text(mid - half - 3, vy, 'L', fg: C.tertiary, attr: bold);
    c.text(mid + half + 2, vy, 'R', fg: C.tertiary, attr: bold);
    c.text(mid, vy, '┃', fg: C.tertiary);
    for (var side = 0; side < 2; side++) {
      final n = (levels[side] * half).round(), p = (peaks[side] * half).round();
      for (var i = 0; i < half; i++) {
        final f = i / half;
        final col = f < 0.6 ? mix(C.green, C.yellow, f / 0.6) : f < 0.85 ? mix(C.yellow, C.orange, (f - 0.6) / 0.25) : mix(C.orange, C.red, (f - 0.85) / 0.15);
        final lit = i < n, peak = i == p - 1;
        c.text(side == 0 ? mid - 1 - i : mid + 1 + i, vy, '▮', fg: lit || peak ? (peak && !lit ? mix(col, 0xffffff, 0.35) : col) : 0x343437);
      }
    }
  }

  void drawFooter(Canvas c, int w, int y) {
    final keys = switch (focus) {
      'results' => [('Enter', 'Reproducir'), ('[ ]', 'Página'), ('⌫', 'Volver'), ('d', 'Descargar'), ('o', 'Ordenar')],
      'library' => [('Enter', 'Reproducir'), ('o', 'Ordenar'), ('f', 'Favorita'), ('r', 'Reescanear'), ('u', 'Actualizar')],
      'sidebar' => [('↑↓', 'Elegir'), ('Enter', 'Abrir'), ('→', 'Lista')],
      _ => [('Enter', 'Aceptar'), ('Esc', 'Lista')],
    };
    final all = [...keys, ('Tab', 'Foco'), ('Espacio', 'Pausa'), ('n b', 'Sig./Ant.'), (', .', '±10s'), ('- +', 'Volumen'), ('/', 'Buscar'), ('q', 'Salir')];
    var x = 1;
    for (final (k, label) in all) {
      final need = textWidth(k) + textWidth(label) + 5;
      if (x + need > w - 1) break;
      x += c.pill(x, y, k, bg: C.control, fg: C.text, attr: bold) + 1;
      x += c.text(x, y, label, fg: C.secondary) + 2;
    }
    final v = 'v$version';
    if (x + v.length < w - 1) c.text(w - 1 - v.length, y, v, fg: C.tertiary);
  }

  void drawToasts(Canvas c, int w, int bottom) {
    final now = DateTime.now();
    toasts.removeWhere((t) => t.until.isBefore(now));
    var y = bottom;
    for (final t in toasts.reversed) {
      final tw = math.min(w ~/ 2, textWidth(t.text) + 8);
      if (y - 2 < 2) break;
      final x = w - tw - 2;
      c.card(x, y - 2, tw, 3, t.error ? 0x3a2224 : C.control);
      final (icon, color) = t.error ? ('✕', C.red) : t.text.endsWith('…') ? ('⇣', C.accent) : ('✓', C.green);
      c.text(x + 2, y - 1, icon, fg: color, attr: bold);
      c.text(x + 4, y - 1, fit(t.text, tw - 6));
      y -= 3;
    }
  }
}
