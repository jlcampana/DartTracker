// Acceso a modarchive.org: descargas y parsers de sus páginas HTML (no tiene API pública sin clave).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const base = 'https://modarchive.org/index.php';
const userAgent = 'Mozilla/5.0 (X11; Linux x86_64) tracker/1.0';

String downloadUrl(int id) => 'https://api.modarchive.org/downloads.php?moduleid=$id';
String moduleUrl(int id) => 'https://modarchive.org/index.php?request=view_by_moduleid&query=$id';

final _client = HttpClient()
  ..userAgent = userAgent
  ..connectionTimeout = const Duration(seconds: 30);

Future<Uint8List> fetchBytes(String url) async {
  const timeout = Duration(seconds: 30);
  final res = await (await _client.getUrl(Uri.parse(url))).close().timeout(timeout);
  final out = BytesBuilder(copy: false);
  await for (final chunk in res.timeout(timeout)) {
    out.add(chunk);
  }
  if (res.statusCode >= 400) throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
  return out.takeBytes();
}

Future<String> fetch(String url) async => utf8.decode(await fetchBytes(url), allowMalformed: true);

String pageUrl(Map<String, String> params, [int page = 1]) {
  final p = {...params, if (page > 1) 'page': '$page'};
  return '$base?${p.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
}

int? toInt(String? s) => s == null || s.isEmpty ? null : int.tryParse(s.replaceAll(',', ''));

String thousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => '.');

/// Extensión de un nombre de archivo, sin el punto ("" si no tiene).
String extOf(String name) {
  final base = name.substring(name.lastIndexOf('/') + 1);
  final i = base.lastIndexOf('.');
  return i <= 0 ? '' : base.substring(i + 1);
}

// ---------------------------------------------------------------- entidades HTML

const _entities = {
  'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ', 'copy': '©',
  'reg': '®', 'trade': '™', 'hellip': '…', 'ndash': '–', 'mdash': '—', 'laquo': '«', 'raquo': '»',
  'lsquo': '‘', 'rsquo': '’', 'ldquo': '“', 'rdquo': '”', 'middot': '·', 'deg': '°', 'szlig': 'ß',
  'iexcl': '¡', 'iquest': '¿', 'euro': '€', 'pound': '£', 'yen': '¥', 'times': '×', 'divide': '÷',
};
const _accents = {'acute': '́', 'grave': '̀', 'circ': '̂', 'tilde': '̃',
    'uml': '̈', 'ring': '̊', 'cedil': '̧', 'slash': '̸'};

String unescape(String s) => s.replaceAllMapped(RegExp(r'&(#[xX][0-9a-fA-F]+|#\d+|[a-zA-Z][a-zA-Z0-9]*);'), (m) {
      final e = m.group(1)!;
      if (e.startsWith('#')) {
        final code = e[1] == 'x' || e[1] == 'X' ? int.tryParse(e.substring(2), radix: 16) : int.tryParse(e.substring(1));
        return code != null && code > 0 && code <= 0x10ffff ? String.fromCharCode(code) : m.group(0)!;
      }
      if (_entities[e] case final v?) return v;
      // áéíóú, ñ, ü, ç... = letra + acento combinado, normalizado a la forma compuesta más habitual
      for (final MapEntry(key: name, value: mark) in _accents.entries) {
        if (e.length == name.length + 1 && e.endsWith(name)) return _compose(e[0], mark);
      }
      return m.group(0)!;
    });

String _compose(String letter, String mark) {
  const table = {
    'á': 'á', 'é': 'é', 'í': 'í', 'ó': 'ó', 'ú': 'ú', 'ý': 'ý',
    'Á': 'Á', 'É': 'É', 'Í': 'Í', 'Ó': 'Ó', 'Ú': 'Ú', 'Ý': 'Ý',
    'à': 'à', 'è': 'è', 'ì': 'ì', 'ò': 'ò', 'ù': 'ù',
    'À': 'À', 'È': 'È', 'Ì': 'Ì', 'Ò': 'Ò', 'Ù': 'Ù',
    'â': 'â', 'ê': 'ê', 'î': 'î', 'ô': 'ô', 'û': 'û',
    'Â': 'Â', 'Ê': 'Ê', 'Î': 'Î', 'Ô': 'Ô', 'Û': 'Û',
    'ã': 'ã', 'õ': 'õ', 'ñ': 'ñ', 'Ã': 'Ã', 'Õ': 'Õ', 'Ñ': 'Ñ',
    'ä': 'ä', 'ë': 'ë', 'ï': 'ï', 'ö': 'ö', 'ü': 'ü', 'ÿ': 'ÿ',
    'Ä': 'Ä', 'Ë': 'Ë', 'Ï': 'Ï', 'Ö': 'Ö', 'Ü': 'Ü',
    'å': 'å', 'Å': 'Å', 'ç': 'ç', 'Ç': 'Ç', 'o̸': 'ø', 'O̸': 'Ø',
  };
  return table[letter + mark] ?? letter + mark;
}

String _unquote(String s) {
  try {
    return Uri.decodeComponent(s);
  } on ArgumentError {
    return s;
  }
}

// ---------------------------------------------------------------- listados

class Module {
  final int id;
  final String filename, title, format, info;
  final int pop;
  Module(this.id, this.filename, this.title, this.format, this.info, this.pop);
}

/// Género, artista o letra del índice A-Z.
class Entry {
  final String id, name;
  Entry(this.id, this.name);
}

final _idRe = RegExp(r'(?:moduleid=|view_by_moduleid&amp;query=|module\.php\?)(\d+)');

/// Saca los módulos de cualquier listado de modarchive (búsquedas, charts, listas...).
List<Module> parseModules(String doc) {
  final marks = <(int, int)>[];
  final seen = <int>{};
  for (final m in _idRe.allMatches(doc)) {
    final mid = int.parse(m.group(1)!);
    if (seen.add(mid)) marks.add((doc.lastIndexOf('<', m.start).clamp(0, doc.length), mid));
  }
  final mods = <Module>[];
  for (var n = 0; n < marks.length; n++) {
    final (pos, mid) = marks[n];
    final seg = doc.substring(pos, n + 1 < marks.length ? marks[n + 1].$1 : doc.length);
    final fm = RegExp('moduleid=$mid#' r'''([^"'\s<>]+)''').firstMatch(seg);
    if (fm == null) continue;
    final filename = unescape(_unquote(fm.group(1)!));
    final tm = RegExp(r'<h1>(.*?)\s*<span class="module-sub-header">').firstMatch(doc) ??
        RegExp('class="chart-listing-title" href="module\\.php\\?$mid">([^<]*)<').firstMatch(seg) ??
        RegExp(r'<span class="module-listing">\s*([^<]+?)\s*</span>').firstMatch(seg) ??
        RegExp('query=$mid" title="([^"]*)"').firstMatch(seg);
    final title = tm == null ? '' : unescape(tm.group(1)!).trim();
    var info = '';
    var pop = 0;
    RegExpMatch? m;
    if ((m = RegExp(r'Downloaded ([\d,]+) times').firstMatch(seg)) != null) {
      pop = toInt(m!.group(1)) ?? 0;
      info = '${thousands(pop)} descargas';
    } else if ((m = RegExp(r'favourite of ([\d,]+) member').firstMatch(seg)) != null) {
      pop = toInt(m!.group(1)) ?? 0;
      info = '$pop favoritos';
    } else if ((m = RegExp(r'Rated</a>\s*(\d+) / 10').firstMatch(seg)) != null) {
      pop = int.parse(m!.group(1)!);
      info = '$pop/10';
    } else if ((m = RegExp(r'Downloads:\s*</b>?\s*([\d,]+)').firstMatch(seg)) != null) {
      pop = toInt(m!.group(1)) ?? 0;
      info = '${thousands(pop)} descargas';
    }
    mods.add(Module(mid, filename, title.isEmpty ? filename : title, extOf(filename).toUpperCase(), info, pop));
  }
  return mods;
}

int parsePages(String doc) =>
    RegExp(r'[?&](?:amp;)?page=(\d+)').allMatches(doc).map((m) => int.parse(m.group(1)!)).fold(1, (a, b) => a > b ? a : b);

List<Entry> parseGenres(String doc) {
  final seen = <String>{};
  return [
    for (final m in RegExp(r'href="index\.php\?query=(\d+)&amp;request=search&amp;search_type=genre">([^<]+)<').allMatches(doc))
      if (seen.add(m.group(1)!)) Entry(m.group(1)!, unescape(m.group(2)!).trim()),
  ];
}

List<Entry> parseArtists(String doc) => [
      for (final m in RegExp(r'''href="member\.php\?(\d+)" class='search-result-link'>([^<]+)</a>''').allMatches(doc))
        Entry(m.group(1)!, unescape(m.group(2)!).trim()),
    ];

Future<Uint8List> fetchModuleFile(String url) async {
  final data = await fetchBytes(url);
  final head = latin1.decode(data.sublist(0, data.length < 200 ? data.length : 200)).trimLeft().toLowerCase();
  if (head.startsWith('<!doctype') || head.startsWith('<html') || data.length < 400) {
    throw const FormatException('modarchive devolvió una página en vez del archivo');
  }
  return data;
}

/// Datos de la ficha de un módulo: artista, descargas, favoritos, género...
Future<Map<String, Object?>> moduleInfo(int mid) async {
  final doc = await fetch(moduleUrl(mid));
  final text = unescape(doc.replaceAll(RegExp(r'<[^>]+>'), ' '));
  String? g(String pat) => RegExp(pat).firstMatch(text)?.group(1)?.trim();

  var artists = <String>[];
  if (RegExp(r'Registered Artist\(s\):(.*?)</ul>', dotAll: true).firstMatch(doc) case final am?) {
    artists = [for (final a in RegExp(r'member\.php\?\d+">([^<]+)</a>').allMatches(am.group(1)!)) unescape(a.group(1)!).trim()];
  }
  final genre = g(r'Genre:\s*([^\n]+?)\s{2,}');
  final tm = RegExp(r'<h1>(.*?)\s*<span').firstMatch(doc);
  return {
    'artist': artists.isEmpty ? null : artists.join(', '),
    'title': tm == null ? null : unescape(tm.group(1)!).trim(),
    'ma_downloads': toInt(g(r'Downloads:\s*([\d,]+)')),
    'ma_favourites': toInt(g(r'Favourited:\s*([\d,]+)')),
    'genre': genre == null || genre == 'n/a' ? null : genre,
    'channels': toInt(g(r'Channels:\s*(\d+)')),
    'md5': g(r'MD5:\s*([0-9a-f]{32})'),
  };
}
