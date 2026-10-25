// DartTracker: explorador de modarchive.org y reproductor de música tracker para el escritorio.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import 'src/controller.dart';
import 'src/gui/home.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--version')) {
    stdout.writeln('DartTracker $version');
    exit(0); // sin esto la ventana GTK se queda abierta aunque no se arranque la interfaz
  }
  await YaruWindowTitleBar.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DartTrackerApp());
}

class DartTrackerApp extends StatelessWidget {
  const DartTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return YaruTheme(
      builder: (context, yaru, child) => MaterialApp(
        title: 'DartTracker',
        debugShowCheckedModeBanner: false,
        theme: yaru.theme,
        darkTheme: yaru.darkTheme,
        themeMode: ThemeMode.system,
        home: const HomePage(),
      ),
    );
  }
}
