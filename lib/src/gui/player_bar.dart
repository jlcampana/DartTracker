// Barra del reproductor: canción, botones, progreso, vúmetro y volumen.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:yaru/yaru.dart';

import '../controller.dart';
import 'lists.dart';

class PlayerBar extends StatefulWidget {
  const PlayerBar({super.key, required this.c});
  final Controller c;

  @override
  State<PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends State<PlayerBar> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _vu = _VuLevels();
  double? _dragging; // posición mientras se arrastra la barra de progreso

  @override
  void initState() {
    super.initState();
    // un fotograma por vsync: el vúmetro y el tiempo se mueven suaves
    _ticker = createTicker((elapsed) {
      final changed = _vu.update(widget.c.vuNow(), elapsed.inMicroseconds / 1e6);
      if (changed || widget.c.player.active) setState(() {});
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final p = c.player;
    final theme = Theme.of(context);
    final t = p.track;
    final duration = (t?['duration'] as num?)?.toDouble() ?? 0;
    final pos = _dragging ?? (duration > 0 ? math.min(p.position, duration) : p.position);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final title = c.noteTitle ?? (t == null ? null : str(t['title']) ?? str(t['filename']));
    final subtitle = c.note ??
        (t == null
            ? 'Elige una canción para empezar'
            : [str(t['artist']) ?? 'Artista desconocido', if (t['channels'] != null) '${t['channels']} canales'].join(' · '));
    final format = c.noteTitle != null ? '' : str(t?['format']) ?? '';

    return Container(
      height: 112,
      color: YaruMasterDetailTheme.of(context).sideBarColor,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          // canción
          Expanded(
            flex: 3,
            child: Row(
              children: [
                FormatBadge(format, size: 64),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title ?? 'Nada sonando', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: c.note == 'Error de descarga' ? theme.colorScheme.error : muted)),
                      if (c.queue.isNotEmpty && c.qpos >= 0 && p.active)
                        Text('${c.qpos + 1} de ${c.queue.length} en la cola', style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // controles y progreso
          Expanded(
            flex: 4,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Btn(icon: Icons.replay_10_rounded, tip: 'Retroceder 10 s (,)', onTap: p.active ? () => c.seek(-10) : null),
                    _Btn(icon: YaruIcons.skip_backward, tip: 'Anterior (B)', onTap: c.prev, size: 22),
                    const SizedBox(width: 6),
                    _PlayButton(playing: p.active && !p.paused, onTap: () => c.playPause()),
                    const SizedBox(width: 6),
                    _Btn(icon: YaruIcons.skip_forward, tip: 'Siguiente (N)', onTap: c.next, size: 22),
                    _Btn(icon: Icons.forward_10_rounded, tip: 'Avanzar 10 s (.)', onTap: p.active ? () => c.seek(10) : null),
                    const SizedBox(width: 6),
                    _Btn(icon: YaruIcons.media_stop, tip: 'Parar (S)', onTap: p.active ? c.stop : null),
                  ],
                ),
                Row(
                  children: [
                    SizedBox(width: 44, child: Text(fmtTime(pos), style: theme.textTheme.labelSmall?.copyWith(color: muted, fontFeatures: const [FontFeature.tabularFigures()]))),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(trackHeight: 4, overlayShape: SliderComponentShape.noOverlay),
                        child: Slider(
                          value: duration > 0 ? pos.clamp(0, duration) : 0,
                          max: duration > 0 ? duration : 1,
                          onChanged: p.active && duration > 0 ? (v) => setState(() => _dragging = v) : null,
                          onChangeEnd: p.active && duration > 0
                              ? (v) {
                                  _dragging = null;
                                  c.seekTo(v);
                                }
                              : null,
                        ),
                      ),
                    ),
                    SizedBox(width: 44, child: Text(fmtTime(duration), textAlign: TextAlign.right, style: theme.textTheme.labelSmall?.copyWith(color: muted, fontFeatures: const [FontFeature.tabularFigures()]))),
                  ],
                ),
              ],
            ),
          ),
          // vúmetro y volumen
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: SizedBox(height: 44, child: CustomPaint(size: Size.infinite, painter: _VuPainter(_vu, theme))),
                  ),
                ),
                const SizedBox(width: 16),
                Icon(
                  p.gain <= -30 ? YaruIcons.speaker_muted : p.gain < -10 ? YaruIcons.speaker_low : p.gain <= 0 ? YaruIcons.speaker_medium : YaruIcons.speaker_high,
                  size: 18,
                  color: muted,
                ),
                SizedBox(
                  width: 110,
                  child: Tooltip(
                    message: 'Volumen: ${p.gain > 0 ? '+' : ''}${p.gain} dB',
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(trackHeight: 3, overlayShape: SliderComponentShape.noOverlay),
                      child: Slider(
                        value: p.gain.toDouble(),
                        min: -30,
                        max: 12,
                        divisions: 14,
                        onChanged: (v) => c.setVolume(v.round()),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({required this.icon, required this.tip, required this.onTap, this.size = 20});
  final IconData icon;
  final String tip;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) =>
      YaruIconButton(icon: Icon(icon, size: size), iconSize: size, tooltip: tip, onPressed: onTap);
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.onTap});
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: playing ? 'Pausa (espacio)' : 'Reproducir (espacio)',
      child: Material(
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        elevation: 2,
        color: primary,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(
            dimension: 46,
            child: Icon(playing ? YaruIcons.media_pause : YaruIcons.media_play, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- vúmetro

class _VuLevels {
  final levels = [0.0, 0.0], peaks = [0.0, 0.0], _peakAt = [0.0, 0.0];
  double _last = 0;

  /// Sube al instante y baja poco a poco, como un vúmetro de verdad. Devuelve si cambió algo.
  bool update((double, double)? target, double now) {
    final dt = (now - _last).clamp(0.0, 0.1);
    _last = now;
    var changed = false;
    for (var i = 0; i < 2; i++) {
      final t = target == null ? 0.0 : (i == 0 ? target.$1 : target.$2);
      final before = (levels[i], peaks[i]);
      levels[i] = t > levels[i] ? t : math.max(t, levels[i] - 1.5 * dt);
      if (levels[i] >= peaks[i]) {
        peaks[i] = levels[i];
        _peakAt[i] = now;
      } else if (now - _peakAt[i] > 0.6) {
        peaks[i] = math.max(levels[i], peaks[i] - 0.45 * dt);
      }
      changed |= before != (levels[i], peaks[i]);
    }
    return changed;
  }
}

class _VuPainter extends CustomPainter {
  _VuPainter(this.vu, this.theme);
  final _VuLevels vu;
  final ThemeData theme;

  static const _segments = 24;

  static Color _color(double f) {
    const green = Color(0xff30d158), yellow = Color(0xffffd60a), orange = Color(0xffff9f0a), red = Color(0xffff453a);
    if (f < 0.6) return Color.lerp(green, yellow, f / 0.6)!;
    if (f < 0.85) return Color.lerp(yellow, orange, (f - 0.6) / 0.25)!;
    return Color.lerp(orange, red, (f - 0.85) / 0.15)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // dos filas de LEDs: canal izquierdo arriba y derecho abajo
    final off = theme.colorScheme.onSurface.withValues(alpha: 0.08);
    final gap = 2.0;
    final w = (size.width - gap * (_segments - 1)) / _segments;
    final h = (size.height - 6) / 2;
    for (var ch = 0; ch < 2; ch++) {
      final y = ch * (h + 6);
      final lit = (vu.levels[ch] * _segments).round();
      final peak = (vu.peaks[ch] * _segments).round() - 1;
      for (var i = 0; i < _segments; i++) {
        final on = i < lit || i == peak;
        final color = on ? _color(i / _segments) : off;
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(i * (w + gap), y, w, h), const Radius.circular(2));
        if (on) canvas.drawRRect(r.inflate(1.5), Paint()..color = color.withValues(alpha: 0.25));
        canvas.drawRRect(r, Paint()..color = i == peak && i >= lit ? Color.lerp(color, Colors.white, 0.35)! : color);
      }
    }
  }

  @override
  bool shouldRepaint(_VuPainter old) => true;
}
