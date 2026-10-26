// Ventana principal: barra lateral, contenido (explorador o biblioteca) y reproductor abajo.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yaru/yaru.dart';

import '../controller.dart';
import '../library.dart';
import 'lists.dart';
import 'player_bar.dart';

IconData sectionIcon(String key) => switch (key) {
      'buscar' => YaruIcons.search,
      'artista' => YaruIcons.music_artist,
      'tophits' => YaruIcons.download,
      'topscore' => YaruIcons.star,
      'favs' => YaruIcons.heart,
      'featured' => YaruIcons.thumb_up,
      'generos' => YaruIcons.tag,
      'az' => YaruIcons.font,
      'random' => YaruIcons.shuffle,
      'lib:0' => YaruIcons.library_music,
      'lib:1' => YaruIcons.users,
      'lib:2' => YaruIcons.globe,
      'lib:3' => YaruIcons.music_history,
      'lib:4' => YaruIcons.clock,
      'lib:5' => YaruIcons.star_filled,
      _ => YaruIcons.music_note,
    };

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final Controller c;
  final searchFocus = FocusNode();
  final searchText = TextEditingController();

  @override
  void initState() {
    super.initState();
    c = Controller(Library(dbPath), notify: _toast)..start();
  }

  @override
  void dispose() {
    c.dispose();
    searchFocus.dispose();
    searchText.dispose();
    super.dispose();
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      width: 520,
      duration: const Duration(seconds: 4),
      backgroundColor: error ? theme.colorScheme.error : null,
      content: Text(msg, maxLines: 2, overflow: TextOverflow.ellipsis),
    ));
  }

  void _open(String key) {
    c.openSection(key);
    searchText.text = key.startsWith('lib:') ? c.filter : '';
    if (c.isSearch || c.inLibrary) {
      WidgetsBinding.instance.addPostFrameCallback((_) => searchFocus.requestFocus());
    }
  }

  @override
  Widget build(BuildContext context) {
    bool typing() => searchFocus.hasFocus;
    void key(void Function() f) {
      if (!typing()) f();
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () => key(() => c.playPause()),
        const SingleActivator(LogicalKeyboardKey.keyN): () => key(c.next),
        const SingleActivator(LogicalKeyboardKey.keyB): () => key(c.prev),
        const SingleActivator(LogicalKeyboardKey.keyS): () => key(c.stop),
        const SingleActivator(LogicalKeyboardKey.comma): () => key(() => c.seek(-10)),
        const SingleActivator(LogicalKeyboardKey.period): () => key(() => c.seek(10)),
        const SingleActivator(LogicalKeyboardKey.minus): () => key(() => c.setVolume(c.player.gain - 3)),
        const SingleActivator(LogicalKeyboardKey.add): () => key(() => c.setVolume(c.player.gain + 3)),
        const SingleActivator(LogicalKeyboardKey.equal): () => key(() => c.setVolume(c.player.gain + 3)),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => searchFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.backspace): () => key(c.back),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (typing()) {
            searchFocus.unfocus();
          } else {
            c.back();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (context, _) => Column(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Sidebar(c: c, onOpen: _open),
                      const VerticalDivider(width: 1),
                      Expanded(child: _Content(c: c, searchFocus: searchFocus, searchText: searchText)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                PlayerBar(c: c),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- barra lateral

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.c, required this.onOpen});
  final Controller c;
  final void Function(String key) onOpen;

  @override
  Widget build(BuildContext context) {
    final bg = YaruMasterDetailTheme.of(context).sideBarColor;
    final theme = Theme.of(context);
    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 6),
          child: Text(text.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.1, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface.withValues(alpha: 0.55))),
        );
    Widget tile(Section s) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          child: YaruMasterTile(
            selected: c.section == s.key,
            leading: Icon(sectionIcon(s.key)),
            title: Text(s.label),
            onTap: () => onOpen(s.key),
          ),
        );
    return SizedBox(
      width: 250,
      child: ColoredBox(
        color: bg ?? theme.colorScheme.surface,
        child: Column(
          children: [
            YaruWindowTitleBar(
              backgroundColor: Colors.transparent,
              border: BorderSide.none,
              isClosable: false,
              isMaximizable: false,
              isMinimizable: false,
              isRestorable: false,
              title: const _AppTitle(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  header('Biblioteca'),
                  for (final s in librarySections) tile(s),
                  header('Modarchive'),
                  for (final s in exploreSections) tile(s),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppTitle extends StatelessWidget {
  const _AppTitle();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'Dart', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w800)),
        const TextSpan(text: 'Tracker', style: TextStyle(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ---------------------------------------------------------------- contenido

class _Content extends StatelessWidget {
  const _Content({required this.c, required this.searchFocus, required this.searchText});
  final Controller c;
  final FocusNode searchFocus;
  final TextEditingController searchText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lib = c.inLibrary;
    final v = c.view;
    final title = lib
        ? librarySections[c.libSort].label
        : c.isSearch && (v == null || !v.title.startsWith(c.section == 'artista' ? 'Artistas' : 'Búsqueda'))
            ? exploreSections.firstWhere((s) => s.key == c.section).label
            : v?.title ?? '';
    final subtitle = lib
        ? c.libStatus
        : c.loading
            ? 'Cargando…'
            : v == null
                ? ''
                : '${c.shown.length} resultados${v.pages > 1 ? ' · página ${v.page} de ${v.pages}' : ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        YaruWindowTitleBar(
          border: BorderSide.none,
          backgroundColor: Colors.transparent,
          leading: !lib && c.history.isNotEmpty
              ? YaruIconButton(icon: const Icon(YaruIcons.go_previous), tooltip: 'Volver', onPressed: c.back)
              : null,
          title: SizedBox(
            width: 360,
            child: (lib || c.isSearch)
                ? YaruSearchField(
                    key: ValueKey(lib ? 'filter' : c.section),
                    controller: searchText,
                    focusNode: searchFocus,
                    autofocus: false,
                    hintText: lib
                        ? 'Filtrar por título, artista, archivo o género'
                        : c.section == 'artista'
                            ? 'Buscar artista en modarchive'
                            : 'Buscar canción en modarchive',
                    onChanged: lib ? c.setFilter : null,
                    onSubmitted: lib ? null : (q) => c.search(q ?? ''),
                    onClear: lib ? () => c.setFilter('') : null,
                  )
                : const SizedBox.shrink(),
          ),
          actions: [
            if (lib) ...[
              YaruIconButton(icon: const Icon(YaruIcons.refresh), tooltip: 'Volver a escanear la carpeta', onPressed: c.scanLibrary),
              YaruIconButton(
                icon: c.checking
                    ? const SizedBox.square(dimension: 16, child: YaruCircularProgressIndicator(strokeWidth: 2))
                    : const Icon(YaruIcons.sync),
                tooltip: 'Comprobar actualizaciones en modarchive',
                onPressed: c.checking ? null : c.checkUpdates,
              ),
            ],
            const SizedBox(width: 8),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (!lib && v?.kind == 'modules' && !c.loading)
                PopupMenuButton<int>(
                  tooltip: 'Ordenar',
                  initialValue: c.resultSort,
                  onSelected: c.setResultSort,
                  itemBuilder: (_) => [for (var i = 0; i < resultSorts.length; i++) PopupMenuItem(value: i, child: Text(resultSorts[i]))],
                  child: Chip(avatar: const Icon(YaruIcons.sort_ascending, size: 16), label: Text(resultSorts[c.resultSort])),
                ),
              if (!lib && v != null && v.pages > 1) ...[
                const SizedBox(width: 12),
                YaruIconButton(icon: const Icon(YaruIcons.go_previous), tooltip: 'Página anterior', onPressed: c.canPage(-1) ? () => c.page(-1) : null),
                Text('${v.page} / ${v.pages}', style: theme.textTheme.bodyMedium),
                YaruIconButton(icon: const Icon(YaruIcons.go_next), tooltip: 'Página siguiente', onPressed: c.canPage(1) ? () => c.page(1) : null),
              ],
            ],
          ),
        ),
        Expanded(child: lib ? LibraryList(c: c) : ResultsView(c: c)),
      ],
    );
  }
}
