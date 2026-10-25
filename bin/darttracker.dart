// Explorador de modarchive.org y reproductor de música tracker para la terminal.
import 'dart:async';
import 'dart:io';

import 'package:darttracker/src/app.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--version') || args.contains('-v')) {
    stdout.writeln('DartTracker $version');
    return;
  }
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('Uso: darttracker\n\nDartTracker: explorador de modarchive.org y reproductor de música tracker.\n'
        'Las canciones se guardan en $musicDir (variable TRACKER_DIR) y la base de datos en $dbPath.');
    return;
  }
  if (!stdin.hasTerminal || !stdout.hasTerminal) {
    stderr.writeln('darttracker necesita una terminal interactiva.');
    exit(1);
  }
  try {
    await Process.run('openmpt123', ['--version']);
  } on ProcessException {
    stderr.writeln('Falta openmpt123. Instálalo con: dnf install openmpt123 (Fedora) o apt install openmpt123 (Ubuntu)');
    exit(1);
  }
  App? app;
  runZonedGuarded(() {
    app = App();
    app!.run();
  }, (e, st) {
    app?.screen.leave();
    stderr.writeln('Error: $e\n$st');
    exit(1);
  });
}
