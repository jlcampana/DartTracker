# tracker

Explorador de [The Mod Archive](https://modarchive.org) y reproductor de música tracker
(MOD, XM, S3M, IT y [muchos más formatos](https://lib.openmpt.org/libopenmpt/)) para la terminal,
escrito en Dart. Es la versión en Dart de [python-tracker](https://github.com/jlcampana/python-tracker),
con una interfaz al estilo de macOS: barra lateral, tarjetas con esquinas suavizadas, botones
redondeados que se pueden pulsar con el ratón y un vúmetro LED en degradado.

Navegas por modarchive de forma interactiva y, al elegir una canción, se descarga sola en
`~/Música/Tracker` y empieza a sonar. Lo descargado (y cualquier módulo que copies en esa carpeta)
queda en una biblioteca local que puedes escuchar sin conexión.

## Instalación

Sin clonar nada (Fedora y Ubuntu / Debian, x86_64 y arm64):

```bash
curl -fsSL https://raw.githubusercontent.com/jlcampana/tracker/main/install.sh | bash
```

El script instala `openmpt123` y la biblioteca de SQLite (pide `sudo`), descarga el ejecutable de la
última [release](https://github.com/jlcampana/tracker/releases) y lo deja en `~/.local/bin/tracker`.
Volver a ejecutar la misma línea lo actualiza. No hace falta tener Dart instalado.

Desde una copia del repositorio, `./install.sh` compila con `dart` si lo tienes y, si no, descarga
la release igual que antes.

## Funciones

**Explorar modarchive**
- Buscar canciones (por nombre de archivo o título) y artistas
- Rankings: más descargadas, mejor puntuadas, favoritas de la gente y destacadas
- Navegar por géneros, por orden alfabético (A-Z) o sacar canciones aleatorias
- Páginas de resultados, volver atrás y ordenar la página por título o popularidad
- Las canciones que ya tienes salen marcadas con ✓

**Biblioteca local**
- Ordenar alfabéticamente, agrupar por artista, por popularidad en modarchive, por más
  escuchadas, por añadidas recientemente o ver solo tus favoritas
- Filtrar por título, artista, archivo o género
- Contador de escuchas y marcado de favoritas
- Comprobar actualizaciones: vuelve a consultar modarchive, refresca los datos (artista,
  descargas, favoritos, género) y, si el MD5 del archivo publicado ya no coincide con el tuyo,
  lo vuelve a bajar

**Reproductor**
- Botones de anterior, −10 s, reproducir/pausa, +10 s, siguiente y parar
- Barra de progreso en la que puedes hacer clic para saltar, y control de volumen
- Al acabar una canción pasa a la siguiente de la lista desde la que la elegiste
- Vúmetro estéreo (el canal izquierdo crece hacia la izquierda y el derecho hacia la derecha,
  con marcadores de pico)

## Uso

```bash
tracker
```

Todo se puede hacer con el teclado o con el ratón (clic en la barra lateral, en las filas, en los
botones y en la barra de progreso; la rueda desplaza las listas). En una fila ya seleccionada, otro
clic la reproduce.

| Tecla | Acción |
|---|---|
| `1` / `2` | Explorar / Biblioteca |
| `Tab` / `Mayús+Tab` | Pasar el foco entre barra lateral, buscador y lista |
| `←` / `→` | Ir a la barra lateral / volver a la lista |
| `Enter` | Abrir sección, descargar y reproducir |
| `/` | Ir al buscador o al filtro |
| `Esc` | Salir del buscador; en la lista, volver al listado anterior |
| `[` / `]` | Página anterior / siguiente (explorar) |
| `Re Pág` / `Av Pág` | Desplazarse; en la primera o última fila cambia de página (explorar) |
| `Retroceso` | Volver al listado anterior (explorar) |
| `d` | Descargar sin reproducir (explorar) |
| `o` | Cambiar el orden |
| `f` | Marcar o desmarcar favorita (biblioteca) |
| `r` | Volver a escanear la carpeta (biblioteca) |
| `u` | Comprobar actualizaciones (biblioteca) |
| `Espacio` | Pausa (o reproducir la fila seleccionada si no suena nada) |
| `s` | Parar |
| `n` / `b` | Siguiente / anterior |
| `,` / `.` | Retroceder / avanzar 10 s |
| `-` / `+` | Bajar / subir volumen |
| `q` | Salir |

Se ve mejor en una terminal con color real (24 bits), como GNOME Terminal, Ptyxis, Konsole, kitty o
WezTerm. Por debajo de 110 columnas la barra lateral se queda solo con los iconos.

## Dónde guarda las cosas

- Canciones: `~/Música/Tracker` (se puede cambiar con la variable de entorno `TRACKER_DIR`)
- Base de datos: `~/.local/share/trackerplay/biblioteca.db` (SQLite)

Son las mismas rutas que usa python-tracker, así que las dos versiones comparten biblioteca.

## Dependencias

| Dependencia | Para qué | Fedora | Ubuntu |
|---|---|---|---|
| [openmpt123](https://lib.openmpt.org/libopenmpt/) | Reproducir los módulos (libopenmpt) | `openmpt123` | `openmpt123` (universe) |
| SQLite | Base de datos de la biblioteca | `sqlite-libs` | `libsqlite3-0` |

## Desarrollo

```bash
dart pub get
dart run bin/tracker.dart
dart analyze
```

Para publicar una versión nueva: sube `version` en `pubspec.yaml` y en `lib/src/app.dart` y ejecuta
`./release.sh`, que compila los ejecutables para x64 y arm64 y crea la release con `gh`.

El código está en `lib/src/`: `modarchive.dart` (descargas y parsers del HTML de modarchive, que no
tiene API pública sin clave), `library.dart` (SQLite), `player.dart` (openmpt123 y vúmetro),
`ui.dart` (lienzo, teclado, ratón y widgets) y `app.dart` (la aplicación).
