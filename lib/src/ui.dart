// Piezas de la interfaz de terminal: colores, lienzo con diff por líneas, teclado y ratón,
// campo de texto y tabla.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

// ---------------------------------------------------------------- paleta (modo oscuro de macOS)

abstract final class C {
  static const window = 0x1c1c1e;
  static const sidebar = 0x232326;
  static const card = 0x2c2c2e;
  static const control = 0x3a3a3c;
  static const controlHi = 0x48484a;
  static const separator = 0x38383a;
  static const zebra = 0x202023;
  static const text = 0xf2f2f7;
  static const secondary = 0x98989d;
  static const tertiary = 0x636366;
  static const accent = 0x0a84ff;
  static const red = 0xff453a;
  static const orange = 0xff9f0a;
  static const yellow = 0xffd60a;
  static const green = 0x30d158;
  static const pink = 0xff375f;
  static const purple = 0xbf5af2;
  static const teal = 0x64d2ff;
}

const bold = 1, dim = 2, italic = 4, underline = 8;

int mix(int a, int b, double t) {
  int ch(int s) => ((a >> s & 255) + ((b >> s & 255) - (a >> s & 255)) * t).round() << s;
  return ch(16) | ch(8) | ch(0);
}

// ---------------------------------------------------------------- anchura de los caracteres

int charWidth(int r) {
  if (r < 0x20 || (r >= 0x7f && r < 0xa0)) return -1; // control: se pinta como espacio
  if ((r >= 0x300 && r <= 0x36f) || (r >= 0x200b && r <= 0x200f) || (r >= 0xfe00 && r <= 0xfe0f) ||
      (r >= 0x1ab0 && r <= 0x1aff) || (r >= 0x20d0 && r <= 0x20ff)) {
    return 0;
  }
  if ((r >= 0x1100 && r <= 0x115f) || (r >= 0x2e80 && r <= 0xa4cf && r != 0x303f) || (r >= 0xac00 && r <= 0xd7a3) ||
      (r >= 0xf900 && r <= 0xfaff) || (r >= 0xfe30 && r <= 0xfe4f) || (r >= 0xff00 && r <= 0xff60) ||
      (r >= 0xffe0 && r <= 0xffe6) || (r >= 0x1f300 && r <= 0x1faff) || (r >= 0x20000 && r <= 0x3fffd)) {
    return 2;
  }
  return 1;
}

int textWidth(String s) => s.runes.fold(0, (a, r) => a + math.max(0, charWidth(r) < 0 ? 1 : charWidth(r)));

/// Recorta [s] a [w] columnas, con «…» si no cabe.
String fit(String s, int w) {
  if (w <= 0) return '';
  if (textWidth(s) <= w) return s;
  final out = StringBuffer();
  var used = 0;
  for (final r in s.runes) {
    final cw = math.max(0, charWidth(r) < 0 ? 1 : charWidth(r));
    if (used + cw > w - 1) break;
    out.writeCharCode(r);
    used += cw;
  }
  return '$out…';
}

// ---------------------------------------------------------------- lienzo

class Hit {
  final int x, y, w, h;
  final void Function(int x, int y)? onClick;
  final void Function(int delta)? onWheel;
  Hit(this.x, this.y, this.w, this.h, {this.onClick, this.onWheel});
  bool contains(int px, int py) => px >= x && px < x + w && py >= y && py < y + h;
}

class Canvas {
  final int w, h;
  final List<String> _ch;
  final Int32List _fg, _bg;
  final Uint8List _attr;
  final hits = <Hit>[];

  Canvas(this.w, this.h)
      : _ch = List.filled(w * h, ' '),
        _fg = Int32List(w * h)..fillRange(0, w * h, C.text),
        _bg = Int32List(w * h)..fillRange(0, w * h, C.window),
        _attr = Uint8List(w * h);

  void fill(int x, int y, int fw, int fh, int bg, {String ch = ' ', int? fg}) {
    for (var yy = math.max(0, y); yy < math.min(h, y + fh); yy++) {
      for (var xx = math.max(0, x); xx < math.min(w, x + fw); xx++) {
        final i = yy * w + xx;
        _ch[i] = ch;
        _bg[i] = bg;
        _attr[i] = 0;
        if (fg != null) _fg[i] = fg;
      }
    }
  }

  int bgAt(int x, int y) => x >= 0 && x < w && y >= 0 && y < h ? _bg[y * w + x] : C.window;

  /// Escribe [s] en (x, y) sin pasar de [maxW] columnas; [bg] nulo respeta el fondo que haya.
  /// Devuelve las columnas ocupadas.
  int text(int x, int y, String s, {int fg = C.text, int? bg, int attr = 0, int? maxW}) {
    if (y < 0 || y >= h) return 0;
    final limit = maxW == null ? w : math.min(w, x + maxW);
    var cx = x;
    for (final r in s.runes) {
      var cw = charWidth(r);
      var ch = String.fromCharCode(r);
      if (cw < 0) {
        cw = 1;
        ch = ' ';
      }
      if (cw == 0) {
        if (cx > 0 && cx - 1 < w && cx > x) _ch[y * w + cx - 1] += ch;
        continue;
      }
      if (cx + cw > limit) break;
      for (var k = 0; k < cw; k++) {
        if (cx + k < 0) continue;
        final i = y * w + cx + k;
        _ch[i] = k == 0 ? ch : '';
        _fg[i] = fg;
        if (bg != null) _bg[i] = bg;
        _attr[i] = attr;
      }
      cx += cw;
    }
    return cx - x;
  }

  /// Tarjeta de fondo [bg] con las esquinas suavizadas con semibloques.
  void card(int x, int y, int cw, int ch, int bg) {
    final outside = bgAt(x, y);
    fill(x, y + 1, cw, ch - 2, bg);
    text(x, y, '▗${'▄' * (cw - 2)}▖', fg: bg, bg: outside);
    text(x, y + ch - 1, '▝${'▀' * (cw - 2)}▘', fg: bg, bg: outside);
  }

  /// Píldora de una línea: «▐ texto ▌». Devuelve su anchura.
  int pill(int x, int y, String label, {required int bg, int fg = C.text, int attr = 0, int? outside}) {
    final out = outside ?? bgAt(x, y);
    text(x, y, '▐', fg: bg, bg: out);
    final n = text(x + 1, y, label, fg: fg, bg: bg, attr: attr);
    text(x + 1 + n, y, '▌', fg: bg, bg: out);
    return n + 2;
  }

  void hit(int x, int y, int hw, int hh, {void Function(int x, int y)? onClick, void Function(int delta)? onWheel}) =>
      hits.add(Hit(x, y, hw, hh, onClick: onClick, onWheel: onWheel));

  String _sgr(int fg, int bg, int attr) {
    final b = StringBuffer('\x1b[0');
    if (attr & bold != 0) b.write(';1');
    if (attr & dim != 0) b.write(';2');
    if (attr & italic != 0) b.write(';3');
    if (attr & underline != 0) b.write(';4');
    b.write(';38;2;${fg >> 16 & 255};${fg >> 8 & 255};${fg & 255}');
    b.write(';48;2;${bg >> 16 & 255};${bg >> 8 & 255};${bg & 255}m');
    return b.toString();
  }

  String line(int y) {
    final b = StringBuffer();
    String? cur;
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      var ch = _ch[i];
      // restos de un carácter ancho pisado por otro
      if (ch.isEmpty && (x == 0 || charWidth(_ch[i - 1].runes.first) != 2)) ch = ' ';
      if (ch.isNotEmpty && charWidth(ch.runes.first) == 2 && (x + 1 >= w || _ch[i + 1].isNotEmpty)) ch = ' ';
      final s = _sgr(_fg[i], _bg[i], _attr[i]);
      if (s != cur) {
        b.write(s);
        cur = s;
      }
      b.write(ch);
    }
    return b.toString();
  }
}

/// Escribe en la terminal solo las líneas que cambian respecto al fotograma anterior.
class Screen {
  List<String>? _prev;

  void enter() {
    stdin.echoMode = false;
    stdin.lineMode = false;
    // pantalla alternativa, sin cursor, sin salto de línea automático y con ratón (SGR)
    stdout.write('\x1b[?1049h\x1b[?25l\x1b[?7l\x1b[?1000h\x1b[?1006h');
  }

  void leave() {
    stdout.write('\x1b[?1000l\x1b[?1006l\x1b[0m\x1b[?7h\x1b[?25h\x1b[?1049l');
    try {
      stdin.lineMode = true;
      stdin.echoMode = true;
    } on StdinException {
      // la terminal ya no está
    }
  }

  void invalidate() => _prev = null;

  void draw(Canvas c) {
    final lines = [for (var y = 0; y < c.h; y++) c.line(y)];
    final b = StringBuffer();
    final prev = _prev;
    if (prev == null || prev.length != lines.length) b.write('\x1b[0m\x1b[2J');
    for (var y = 0; y < lines.length; y++) {
      if (prev != null && prev.length == lines.length && prev[y] == lines[y]) continue;
      b.write('\x1b[${y + 1};1H${lines[y]}');
    }
    _prev = lines;
    if (b.isNotEmpty) stdout.write('$b\x1b[0m');
  }
}

// ---------------------------------------------------------------- entrada

class Mouse {
  final int button, x, y; // x, y desde 0
  final bool press;
  Mouse(this.button, this.x, this.y, this.press);
}

/// Traduce lo leído de la terminal en teclas ("up", "enter", "a"...) y clics de ratón.
List<Object> parseInput(String s) {
  final out = <Object>[];
  final r = s.runes.toList();
  var i = 0;
  while (i < r.length) {
    final c = r[i];
    if (c == 0x1b) {
      if (i + 1 >= r.length || r[i + 1] == 0x1b) {
        out.add('escape');
        i++;
        continue;
      }
      if (r[i + 1] == 0x5b || r[i + 1] == 0x4f) {
        var j = i + 2;
        final params = StringBuffer();
        while (j < r.length && (r[j] < 0x40 || r[j] > 0x7e)) {
          params.writeCharCode(r[j++]);
        }
        if (j >= r.length) break; // secuencia cortada
        final fin = String.fromCharCode(r[j]);
        i = j + 1;
        if (_csi(params.toString(), fin) case final k?) out.add(k);
        continue;
      }
      out.add('escape'); // Alt+tecla: Esc y después la tecla
      i++;
      continue;
    }
    i++;
    out.add(switch (c) {
      0x0d || 0x0a => 'enter',
      0x7f || 0x08 => 'backspace',
      0x09 => 'tab',
      0x03 => 'ctrl+c',
      0x15 => 'ctrl+u',
      < 0x20 => '',
      _ => String.fromCharCode(c),
    });
  }
  out.remove('');
  return out;
}

Object? _csi(String p, String f) {
  if (p.startsWith('<') && (f == 'M' || f == 'm')) {
    final n = p.substring(1).split(';').map(int.tryParse).toList();
    if (n.length == 3 && !n.contains(null)) return Mouse(n[0]!, n[1]! - 1, n[2]! - 1, f == 'M');
    return null;
  }
  return switch (f) {
    'A' => 'up',
    'B' => 'down',
    'C' => 'right',
    'D' => 'left',
    'H' => 'home',
    'F' => 'end',
    'Z' => 'shift+tab',
    '~' => switch (p.split(';').first) {
        '1' || '7' => 'home',
        '4' || '8' => 'end',
        '3' => 'delete',
        '5' => 'pageup',
        '6' => 'pagedown',
        _ => null,
      },
    _ => null,
  };
}

// ---------------------------------------------------------------- campo de texto

class TextField {
  String placeholder;
  List<int> _runes = [];
  int _cur = 0;
  TextField(this.placeholder);

  String get value => String.fromCharCodes(_runes);

  /// Devuelve true si la tecla era para el campo; [changed] avisa si cambió el texto.
  bool key(String k, void Function() changed) {
    switch (k) {
      case 'left':
        _cur = math.max(0, _cur - 1);
      case 'right':
        _cur = math.min(_runes.length, _cur + 1);
      case 'home':
        _cur = 0;
      case 'end':
        _cur = _runes.length;
      case 'backspace':
        if (_cur == 0) return true;
        _runes.removeAt(--_cur);
        changed();
      case 'delete':
        if (_cur >= _runes.length) return true;
        _runes.removeAt(_cur);
        changed();
      case 'ctrl+u':
        _runes = [];
        _cur = 0;
        changed();
      default:
        if (k.runes.length != 1) return false;
        _runes.insert(_cur++, k.runes.first);
        changed();
    }
    return true;
  }

  /// Campo con forma de píldora y lupa delante.
  void draw(Canvas c, int x, int y, int w, {required bool focused, String icon = '⌕'}) {
    final bg = focused ? C.controlHi : C.control;
    final out = c.bgAt(x, y);
    c.text(x, y, '▐', fg: bg, bg: out);
    c.fill(x + 1, y, w - 2, 1, bg);
    c.text(x + w - 1, y, '▌', fg: bg, bg: out);
    c.text(x + 2, y, icon, fg: focused ? C.accent : C.secondary, bg: bg);
    final tx = x + 4, tw = w - 6;
    if (_runes.isEmpty) {
      if (focused) c.text(tx, y, ' ', bg: C.text);
      c.text(focused ? tx + 1 : tx, y, fit(placeholder, tw - 1), fg: C.tertiary, bg: bg);
      return;
    }
    // desplaza el texto para que el cursor siempre se vea
    var start = 0;
    while (textWidth(String.fromCharCodes(_runes.sublist(start, _cur))) > tw - 1) {
      start++;
    }
    var cx = tx;
    for (var i = start; i <= _runes.length; i++) {
      final ch = i < _runes.length ? String.fromCharCode(_runes[i]) : ' ';
      if (cx + textWidth(ch) > tx + tw) break;
      final isCur = focused && i == _cur;
      cx += c.text(cx, y, ch, fg: isCur ? C.window : C.text, bg: isCur ? C.text : bg);
    }
  }
}

// ---------------------------------------------------------------- tabla

class Span {
  final String text;
  final int fg, attr;
  const Span(this.text, {this.fg = C.text, this.attr = 0});
}

class Col {
  final String title;
  final bool shrink, right;
  final int weight; // las columnas con más peso se encogen más tarde
  const Col(this.title, {this.shrink = false, this.right = false, this.weight = 1});
}

class Table {
  List<Col> cols = [];
  List<List<Span>> rows = [];
  List<int> _natural = [];
  int cursor = 0, scroll = 0, _visible = 10;
  String empty = '';

  int get length => rows.length;

  void set(List<Col> cols, List<List<Span>> rows, {bool keep = false}) {
    this.cols = cols;
    this.rows = rows;
    _natural = [
      for (var i = 0; i < cols.length; i++)
        rows.fold(textWidth(cols[i].title), (a, r) => math.max(a, textWidth(r[i].text))),
    ];
    if (!keep) cursor = scroll = 0;
    cursor = rows.isEmpty ? 0 : cursor.clamp(0, rows.length - 1);
  }

  void moveTo(int row) => cursor = rows.isEmpty ? 0 : row.clamp(0, rows.length - 1);

  /// Mueve el cursor; devuelve false si la tecla no es de la tabla.
  bool key(String k) {
    switch (k) {
      case 'up':
        moveTo(cursor - 1);
      case 'down':
        moveTo(cursor + 1);
      case 'pageup':
        moveTo(cursor - _visible);
      case 'pagedown':
        moveTo(cursor + _visible);
      case 'home':
        moveTo(0);
      case 'end':
        moveTo(rows.length - 1);
      default:
        return false;
    }
    return true;
  }

  List<int> _widths(int avail) {
    final w = [for (final n in _natural) n];
    var excess = w.fold(0, (a, b) => a + b + 2) - avail;
    while (excess > 0) {
      var best = -1;
      for (var i = 0; i < w.length; i++) {
        if (cols[i].shrink && w[i] > 8 && (best < 0 || w[i] / cols[i].weight > w[best] / cols[best].weight)) best = i;
      }
      // si no basta, se encoge también el resto, empezando por la más ancha
      if (best < 0) {
        for (var i = 0; i < w.length; i++) {
          if (w[i] > 3 && (best < 0 || w[i] > w[best])) best = i;
        }
      }
      if (best < 0) break;
      w[best]--;
      excess--;
    }
    // lo que sobra se lo lleva la primera columna que se puede encoger (el título)
    final first = cols.indexWhere((c) => c.shrink);
    if (excess < 0 && first >= 0) w[first] -= excess;
    return w;
  }

  void draw(Canvas c, int x, int y, int w, int h,
      {required bool focused, required int bg, void Function(int row, bool again)? onClick}) {
    _visible = math.max(1, h - 2);
    final widths = _widths(w - 2);
    // cabecera
    var cx = x + 1;
    for (var i = 0; i < cols.length; i++) {
      final t = fit(cols[i].title, widths[i]);
      c.text(cols[i].right ? cx + 1 + widths[i] - textWidth(t) : cx + 1, y, t,
          fg: C.secondary, attr: bold, maxW: math.max(0, x + w - 1 - (cx + 1)));
      cx += widths[i] + 2;
    }
    c.text(x + 1, y + 1, '─' * (w - 2), fg: C.separator);
    if (rows.isEmpty) {
      c.text(x + 2, y + 3, fit(empty, w - 4), fg: C.tertiary, attr: italic);
      return;
    }
    if (cursor < scroll) scroll = cursor;
    if (cursor >= scroll + _visible) scroll = cursor - _visible + 1;
    scroll = scroll.clamp(0, math.max(0, rows.length - _visible));
    for (var n = 0; n < _visible && scroll + n < rows.length; n++) {
      final r = scroll + n, ry = y + 2 + n;
      final sel = r == cursor;
      final rowBg = sel ? (focused ? C.accent : C.controlHi) : (r.isOdd ? C.zebra : bg);
      if (sel) {
        c.text(x, ry, '▐', fg: rowBg, bg: bg);
        c.fill(x + 1, ry, w - 2, 1, rowBg);
        c.text(x + w - 1, ry, '▌', fg: rowBg, bg: bg);
      } else {
        c.fill(x + 1, ry, w - 2, 1, rowBg);
      }
      cx = x + 1;
      for (var i = 0; i < cols.length; i++) {
        final s = rows[r][i];
        final t = fit(s.text, widths[i]);
        final fg = sel && focused && s.fg == C.secondary ? C.text : s.fg;
        c.text(cols[i].right ? cx + 1 + widths[i] - textWidth(t) : cx + 1, ry, t,
            fg: fg, attr: s.attr, maxW: math.max(0, x + w - 1 - (cx + 1)));
        cx += widths[i] + 2;
      }
    }
    if (rows.length > _visible) {
      // barra de desplazamiento fina
      final th = math.max(1, _visible * _visible ~/ rows.length);
      final ty = (scroll * (_visible - th) / math.max(1, rows.length - _visible)).round();
      for (var n = 0; n < _visible; n++) {
        c.text(x + w - 1, y + 2 + n, n >= ty && n < ty + th ? '┃' : ' ', fg: C.tertiary, bg: bg);
      }
    }
    c.hit(x, y + 2, w, _visible, onClick: (_, py) {
      final r = scroll + py - (y + 2);
      if (r < rows.length) {
        final again = r == cursor;
        moveTo(r);
        onClick?.call(r, again);
      }
    }, onWheel: (d) => moveTo(cursor + d * 3));
  }
}
