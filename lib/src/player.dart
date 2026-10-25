// Reproducción con openmpt123, datos de los módulos y niveles del vúmetro.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'library.dart';
import 'modarchive.dart';

/// Ejecuta un comando y devuelve su salida; lo mata si tarda más de [timeout].
Future<Uint8List> runCapture(List<String> cmd, Duration timeout) async {
  final p = await Process.start(cmd.first, cmd.sublist(1));
  unawaited(p.stdin.close());
  unawaited(p.stderr.drain<void>());
  final out = BytesBuilder(copy: false);
  final timer = Timer(timeout, p.kill);
  await p.stdout.forEach(out.add);
  await p.exitCode;
  timer.cancel();
  return out.takeBytes();
}

Future<Map<String, Object?>> openmptInfo(String path) async {
  String out;
  try {
    out = utf8.decode(await runCapture(['openmpt123', '--info', '--banner', '0', '--', path],
        const Duration(seconds: 20)), allowMalformed: true);
  } on ProcessException {
    return {};
  }
  final info = <String, String>{};
  for (final line in const LineSplitter().convert(out)) {
    if (RegExp(r'^(\w[\w ]*?)\.*:\s?(.*)$').firstMatch(line) case final m?) {
      info[m.group(1)!.trim().toLowerCase()] = m.group(2)!.trim();
    }
  }
  var secs = 0.0;
  for (final part in (info['duration'] ?? '').split(':')) {
    if (double.tryParse(part) case final v?) secs = secs * 60 + v;
  }
  String? s(String k) => (info[k] ?? '').isEmpty ? null : info[k];
  return {'title': s('title'), 'artist': s('artist'), 'duration': secs == 0 ? null : secs, 'channels': toInt(info['channels'])};
}

/// Envuelve openmpt123: pausa con SIGSTOP/SIGCONT y reinicia con --seek para saltar o cambiar volumen.
class Player {
  Process? _proc;
  Future<void>? _starting;
  int _gen = 0;
  bool _done = false;

  Track? track;
  bool active = false; // hay una canción en marcha (aunque esté en pausa)
  bool paused = false;
  double _offset = 0, _started = 0;
  int gain = 0;
  final _clock = Stopwatch()..start();

  double get _now => _clock.elapsedMicroseconds / 1e6;

  void play(Track t, [double seek = 0]) {
    stop();
    track = t;
    _offset = seek;
    _started = _now;
    paused = false;
    active = true;
    _done = false;
    final gen = ++_gen;
    _starting = Process.start('openmpt123',
        ['--batch', '-q', '--gain', '$gain', '--seek', '${seek.toInt()}', '--', t['path'] as String]).then((p) {
      unawaited(p.stdin.close());
      unawaited(p.stdout.drain<void>());
      unawaited(p.stderr.drain<void>());
      if (gen != _gen) {
        p.kill();
        return;
      }
      _proc = p;
      if (paused) p.kill(ProcessSignal.sigstop);
      p.exitCode.then((_) {
        if (identical(_proc, p)) _done = true;
      });
    }, onError: (Object _) {
      if (gen == _gen) _done = true;
    });
  }

  void stop() {
    _gen++;
    final p = _proc;
    _proc = null;
    if (p != null) {
      if (paused) p.kill(ProcessSignal.sigcont);
      p.kill();
      var exited = false;
      p.exitCode.then((_) => exited = true);
      Timer(const Duration(seconds: 2), () {
        if (!exited) p.kill(ProcessSignal.sigkill);
      });
    }
    active = false;
    paused = false;
  }

  void togglePause() {
    if (!active) return;
    if (paused) {
      _proc?.kill(ProcessSignal.sigcont);
      _started = _now;
    } else {
      _proc?.kill(ProcessSignal.sigstop);
      _offset += _now - _started;
    }
    paused = !paused;
  }

  void restartAt(double pos) {
    if (!active) return;
    final wasPaused = paused;
    final duration = (track!['duration'] as num?)?.toDouble() ?? 0;
    play(track!, math.max(0, duration > 0 ? math.min(pos, duration - 1) : pos));
    if (wasPaused) togglePause();
  }

  double get position => !active ? 0 : paused ? _offset : _offset + _now - _started;

  bool get finished => active && _done;

  /// La canción acabó sola: se queda como última reproducida pero sin proceso.
  void markFinished() {
    _proc = null;
    active = false;
    paused = false;
  }

  /// Para la música antes de salir, esperando a que arranque un proceso que estuviera a medias.
  Future<void> dispose() async {
    stop();
    await _starting;
  }
}

// ---------------------------------------------------------------- vúmetro

const vuRate = 11025; // frecuencia a la que se analiza (no hace falta más para medir volumen)
const vuFps = 30; // niveles por segundo
const _vuDb = 36; // rango en dB que cubre la barra
const _vuTop = -6; // dBFS que llenan la barra (la música casi nunca llega a 0 dB de media)

/// Niveles izquierdo y derecho (0-1, alternos) de cada 1/[vuFps] s de la canción.
///
/// openmpt123 renderiza el módulo entero a PCM mucho más rápido que en tiempo real, así que
/// se analiza aparte (en otro isolate) y el audio que suena no se toca.
Future<Float32List> vuEnvelope(String path) => Isolate.run(() async {
      Uint8List raw;
      try {
        raw = await runCapture(['openmpt123', '--stdout', '--batch', '-q', '--no-float', '--samplerate', '$vuRate',
            '--channels', '2', '--', path], const Duration(seconds: 120));
      } on ProcessException {
        return Float32List(0);
      }
      final pcm = ByteData.sublistView(raw);
      final n = raw.length ~/ 2;
      const win = vuRate ~/ vuFps * 2;
      final out = Float32List(((n + win - 1) ~/ win) * 2);
      double level(double sum, int count) {
        if (count == 0) return 0;
        final rms = math.sqrt(sum / count);
        final db = 20 * math.log(math.max(rms, 1) / 32768) / math.ln10;
        return (1 + (db - _vuTop) / _vuDb).clamp(0.0, 1.0);
      }

      for (var i = 0, k = 0; i < n; i += win, k += 2) {
        var l = 0.0, r = 0.0;
        var nl = 0, nr = 0;
        for (var j = i; j < i + win && j < n; j++) {
          final v = pcm.getInt16(j * 2, Endian.little).toDouble();
          if ((j - i).isEven) {
            l += v * v;
            nl++;
          } else {
            r += v * v;
            nr++;
          }
        }
        out[k] = level(l, nl);
        out[k + 1] = level(r, nr);
      }
      return out;
    });
