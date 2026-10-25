// Listas del explorador y de la biblioteca.
import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../controller.dart';
import '../library.dart';
import '../modarchive.dart';

Color formatColor(String f) => switch (f.toUpperCase()) {
      'XM' => const Color(0xffbf5af2),
      'IT' => const Color(0xff30b0c7),
      'MOD' => const Color(0xffff9f0a),
      'S3M' => const Color(0xffff375f),
      'MPTM' => const Color(0xff30d158),
      _ => const Color(0xff8e8e93),
    };

/// Etiqueta de color con el formato del módulo (XM, IT, MOD...).
class FormatBadge extends StatelessWidget {
  const FormatBadge(this.format, {super.key, this.size = 40, this.playing = false});
  final String format;
  final double size;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final color = formatColor(format);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, 0.15)!, Color.lerp(color, Colors.black, 0.25)!],
        ),
      ),
      alignment: Alignment.center,
      child: playing
          ? Icon(YaruIcons.speaker_high_filled, color: Colors.white, size: size * 0.5)
          : FittedBox(
              child: Padding(
                padding: EdgeInsets.all(size * 0.14),
                child: Text(format.isEmpty ? '♪' : format,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              ),
            ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: muted),
          const SizedBox(height: 16),
          Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: muted)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// Fila redondeada con efecto al pasar el ratón, como las listas de GNOME.
class _Row extends StatelessWidget {
  const _Row({required this.child, this.onTap, this.selected = false});
  final Widget child;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Material(
        color: selected ? theme.colorScheme.primary.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: child),
        ),
      ),
    );
  }
}

TextStyle? _muted(BuildContext context) =>
    Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6));

// ---------------------------------------------------------------- explorador

class ResultsView extends StatelessWidget {
  const ResultsView({super.key, required this.c});
  final Controller c;

  @override
  Widget build(BuildContext context) {
    if (c.loading && c.shown.isEmpty || c.loading && c.view?.kind != 'modules') {
      return const Center(child: YaruCircularProgressIndicator());
    }
    if (c.error != null) {
      return _Empty(
        icon: YaruIcons.network_error_filled,
        text: c.error!,
        action: OutlinedButton(onPressed: () => c.loadView(c.view!), child: const Text('Reintentar')),
      );
    }
    final v = c.view;
    if (v == null) {
      return _Empty(
        icon: c.section == 'artista' ? YaruIcons.music_artist : YaruIcons.search,
        text: c.section == 'artista' ? 'Busca un artista en modarchive' : 'Busca canciones en modarchive\npor título o nombre de archivo',
      );
    }
    if (c.shown.isEmpty) return const _Empty(icon: YaruIcons.search, text: 'Sin resultados');

    final list = switch (v.kind) {
      'modules' => ListView.builder(
          padding: const EdgeInsets.only(bottom: 12),
          itemCount: c.shown.length,
          itemBuilder: (context, i) => _ModuleRow(c: c, index: i, mod: c.shown[i] as Module),
        ),
      'letters' => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 4, 28, 20),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < c.shown.length; i++)
                SizedBox.square(
                  dimension: 64,
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    onPressed: () => c.selectResult(i),
                    child: Text((c.shown[i] as Entry).name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
        ),
      _ => ListView.builder(
          padding: const EdgeInsets.only(bottom: 12),
          itemCount: c.shown.length,
          itemBuilder: (context, i) => _Row(
            onTap: () => c.selectResult(i),
            child: Row(children: [
              Icon(v.kind == 'genres' ? YaruIcons.tag : YaruIcons.music_artist),
              const SizedBox(width: 14),
              Expanded(child: Text((c.shown[i] as Entry).name, style: Theme.of(context).textTheme.bodyLarge)),
              const Icon(YaruIcons.go_next, size: 16),
            ]),
          ),
        ),
    };
    return Stack(children: [
      list,
      if (c.loading) const Align(alignment: Alignment.topCenter, child: LinearProgressIndicator()),
    ]);
  }
}

class _ModuleRow extends StatelessWidget {
  const _ModuleRow({required this.c, required this.index, required this.mod});
  final Controller c;
  final int index;
  final Module mod;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final have = c.haveIds.contains(mod.id);
    final playing = c.isPlaying(mod);
    final downloading = c.noteTitle == mod.title && c.note == 'Descargando…' && c.queue.isNotEmpty && c.queue[c.qpos] == mod;
    return _Row(
      selected: playing || downloading,
      onTap: () => c.selectResult(index),
      child: Row(
        children: [
          FormatBadge(mod.format, playing: playing),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mod.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: playing ? theme.colorScheme.primary : null)),
                Text(mod.filename, maxLines: 1, overflow: TextOverflow.ellipsis, style: _muted(context)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (mod.info.isNotEmpty) Text(mod.info, style: _muted(context)),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: downloading
                ? const Center(child: SizedBox.square(dimension: 18, child: YaruCircularProgressIndicator(strokeWidth: 2)))
                : have
                    ? Tooltip(message: 'En tu biblioteca', child: Icon(YaruIcons.checkmark, color: Colors.green.shade400))
                    : YaruIconButton(icon: const Icon(YaruIcons.download), tooltip: 'Descargar sin reproducir', onPressed: () => c.download(mod)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- biblioteca

class LibraryList extends StatelessWidget {
  const LibraryList({super.key, required this.c});
  final Controller c;

  @override
  Widget build(BuildContext context) {
    if (c.libItems.isEmpty) {
      return _Empty(
        icon: c.filter.isNotEmpty ? YaruIcons.search : YaruIcons.library_music,
        text: c.filter.isNotEmpty
            ? 'Nada coincide con «${c.filter.trim()}»'
            : c.libSort == 5
                ? 'Aún no tienes favoritas'
                : 'La biblioteca está vacía\nDescarga algo desde modarchive',
      );
    }
    final theme = Theme.of(context);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: c.libItems.length,
      itemBuilder: (context, i) {
        final item = c.libItems[i];
        if (item is String) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(30, 18, 20, 6),
            child: Text(item, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
          );
        }
        return _TrackRow(c: c, track: item as Track);
      },
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.c, required this.track});
  final Controller c;
  final Track track;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playing = c.isPlaying(track);
    final fav = (track['favorite'] as int? ?? 0) != 0;
    final downloads = track['ma_downloads'] as int? ?? 0;
    final plays = track['plays'] as int? ?? 0;
    final details = [
      str(track['artist']) ?? 'Artista desconocido',
      ?str(track['genre']),
    ].join(' · ');
    return _Row(
      selected: playing,
      onTap: () => c.selectLibrary(track),
      child: Row(
        children: [
          FormatBadge(str(track['format']) ?? '', playing: playing),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(str(track['title']) ?? str(track['filename']) ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: playing ? theme.colorScheme.primary : null)),
                Text(details, maxLines: 1, overflow: TextOverflow.ellipsis, style: _muted(context)),
              ],
            ),
          ),
          if (downloads > 0)
            Tooltip(
              message: 'Descargas en modarchive',
              child: Row(children: [
                Icon(YaruIcons.download, size: 14, color: _muted(context)?.color),
                const SizedBox(width: 4),
                Text(thousands(downloads), style: _muted(context)),
              ]),
            ),
          const SizedBox(width: 18),
          SizedBox(
            width: 56,
            child: Tooltip(
              message: 'Escuchas',
              child: plays > 0
                  ? Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Text('$plays', style: _muted(context)),
                      const SizedBox(width: 4),
                      Icon(YaruIcons.media_play, size: 12, color: _muted(context)?.color),
                    ])
                  : const SizedBox.shrink(),
            ),
          ),
          SizedBox(width: 56, child: Text(fmtTime(track['duration'] as num?), textAlign: TextAlign.right, style: _muted(context))),
          const SizedBox(width: 6),
          YaruIconButton(
            icon: Icon(fav ? YaruIcons.star_filled : YaruIcons.star, color: fav ? Colors.amber : null),
            tooltip: fav ? 'Quitar de favoritas' : 'Marcar como favorita',
            onPressed: () => c.toggleFavorite(track),
          ),
        ],
      ),
    );
  }
}
