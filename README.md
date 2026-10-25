# DartTracker

Explorador de [The Mod Archive](https://modarchive.org) y reproductor de música tracker
(MOD, XM, S3M, IT y [muchos más formatos](https://lib.openmpt.org/libopenmpt/)) para el escritorio
Linux, escrito en Dart con Flutter y [Yaru](https://pub.dev/packages/yaru), el kit de widgets de
GNOME/Ubuntu. Es la versión gráfica de [python-tracker](https://github.com/jlcampana/python-tracker).

Navegas por modarchive y, al elegir una canción, se descarga sola en `~/Música/Tracker` y empieza a
sonar. Lo descargado (y cualquier módulo que copies en esa carpeta) queda en una biblioteca local
que puedes escuchar sin conexión.

La ventana sigue el modo claro u oscuro y el color de acento de GNOME.

## Instalación

Sin clonar nada (Fedora y Ubuntu / Debian, x86_64 y arm64):

```bash
curl -fsSL https://raw.githubusercontent.com/jlcampana/DartTracker/main/install.sh | bash
```

El script instala `openmpt123`, GTK 3 y la biblioteca de SQLite (pide `sudo`), descarga la última
[release](https://github.com/jlcampana/DartTracker/releases) en `~/.local/share/darttracker`,
enlaza el comando `darttracker` en `~/.local/bin` y añade DartTracker al menú de aplicaciones con
su icono. Volver a ejecutar la misma línea lo actualiza. No hace falta tener Flutter instalado.

Desde una copia del repositorio, `./install.sh` compila con `flutter` si lo tienes y, si no,
descarga la release igual que antes.

## Funciones

**Explorar modarchive**
- Buscar canciones (por nombre de archivo o título) y artistas
- Rankings: más descargadas, mejor puntuadas, favoritas de la gente y destacadas
- Navegar por géneros, por orden alfabético (A-Z) o sacar canciones aleatorias
- Páginas de resultados, volver atrás y ordenar la página por título o popularidad
- Las canciones que ya tienes salen marcadas con ✓; el resto se pueden descargar sin reproducirlas

**Biblioteca local**
- Ver todas, agrupar por artista, por popularidad en modarchive, por más escuchadas, por añadidas
  recientemente o solo tus favoritas
- Filtrar por título, artista, archivo o género
- Contador de escuchas y marcado de favoritas
- Comprobar actualizaciones: vuelve a consultar modarchive, refresca los datos (artista,
  descargas, favoritos, género) y, si el MD5 del archivo publicado ya no coincide con el tuyo,
  lo vuelve a bajar

**Reproductor**
- Anterior, −10 s, reproducir/pausa, +10 s, siguiente y parar
- Barra de progreso que se puede arrastrar, y volumen
- Al acabar una canción pasa a la siguiente de la lista desde la que la elegiste
- Vúmetro LED estéreo con marcadores de pico

## Atajos de teclado

| Tecla | Acción |
|---|---|
| `Espacio` | Pausa / reanudar |
| `N` / `B` | Siguiente / anterior |
| `,` / `.` | Retroceder / avanzar 10 s |
| `-` / `+` | Bajar / subir volumen |
| `S` | Parar |
| `Ctrl+F` | Ir al buscador o al filtro |
| `Retroceso` / `Esc` | Volver al listado anterior (en el buscador, `Esc` sale de él) |

## Dónde guarda las cosas

- Canciones: `~/Música/Tracker` (se puede cambiar con la variable de entorno `TRACKER_DIR`)
- Base de datos: `~/.local/share/trackerplay/biblioteca.db` (SQLite)

Son las mismas rutas que usa python-tracker, así que las dos versiones comparten biblioteca.

## Dependencias

| Dependencia | Para qué | Fedora | Ubuntu |
|---|---|---|---|
| [openmpt123](https://lib.openmpt.org/libopenmpt/) | Reproducir los módulos (libopenmpt) | `openmpt123` | `openmpt123` (universe) |
| GTK 3 | Ventana | `gtk3` | `libgtk-3-0t64` / `libgtk-3-0` |
| SQLite | Base de datos de la biblioteca | `sqlite-libs` | `libsqlite3-0` |

## Desarrollo

Hace falta [Flutter](https://docs.flutter.dev/get-started/install/linux) y, para compilar la
aplicación de escritorio, `clang cmake ninja-build gtk3-devel` (Fedora) o
`clang cmake ninja-build libgtk-3-dev` (Ubuntu).

```bash
flutter pub get
flutter run -d linux
flutter analyze
```

Para publicar una versión nueva: sube `version` en `pubspec.yaml` y en `lib/src/controller.dart`,
haz commit y ejecuta `./release.sh`. Sube la etiqueta `v<versión>` y GitHub Actions compila los
paquetes para x64 y arm64 y publica la release.

El código está en `lib/`: `main.dart` (arranque y tema), `src/controller.dart` (estado y lógica),
`src/modarchive.dart` (descargas y parsers del HTML de modarchive, que no tiene API pública sin
clave), `src/library.dart` (SQLite), `src/player.dart` (openmpt123 y vúmetro) y `src/gui/`
(ventana, listas y barra del reproductor).
