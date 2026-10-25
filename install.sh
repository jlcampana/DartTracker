#!/usr/bin/env bash
# Instalación de DartTracker en Fedora o Ubuntu / Debian.
#
# Sin clonar nada:
#   curl -fsSL https://raw.githubusercontent.com/jlcampana/DartTracker/main/install.sh | bash
# Desde una copia del repositorio:  ./install.sh  (compila con flutter si lo tienes)
#
# Instala openmpt123, GTK y SQLite (pide sudo), descarga la última release de GitHub en
# ~/.local/share/darttracker, enlaza el comando darttracker en ~/.local/bin y añade la aplicación
# al menú con su icono. Volver a ejecutarlo actualiza la aplicación.
set -euo pipefail

REPO="jlcampana/DartTracker"
APP_ID="io.github.jlcampana.darttracker"
BIN_DIR="$HOME/.local/bin"
DEST="$HOME/.local/share/darttracker"

# Todo va dentro de main() para que bash lea el script entero antes de ejecutarlo: con
# 'curl | bash' el script llega por la entrada estándar y dnf/apt podrían comerse el resto.
main() {

# ------------------------------------------------------------ paquetes del sistema

. /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in
    *" fedora "*)
        echo "==> Instalando paquetes del sistema (dnf)"
        sudo dnf install -y curl tar gtk3 sqlite-libs openmpt123
        ;;
    *" debian "*|*" ubuntu "*)
        echo "==> Instalando paquetes del sistema (apt)"
        # openmpt123 está en el repositorio "universe" de Ubuntu
        if [[ ${ID:-} == ubuntu ]] \
           && ! grep -rqs '^[^#].* universe' /etc/apt/sources.list /etc/apt/sources.list.d/ \
           && ! grep -rqs '^Components:.*universe' /etc/apt/sources.list.d/; then
            sudo add-apt-repository -y universe
        fi
        sudo apt-get update
        # en Ubuntu 24.04+ la biblioteca de GTK se llama libgtk-3-0t64
        GTK=libgtk-3-0t64
        apt-cache show "$GTK" >/dev/null 2>&1 || GTK=libgtk-3-0
        sudo apt-get install -y curl tar "$GTK" libsqlite3-0 openmpt123
        ;;
    *)
        echo "Distribución no soportada (${PRETTY_NAME:-desconocida})." >&2
        echo "Instala a mano curl, GTK 3, la biblioteca de SQLite y openmpt123 y vuelve a ejecutarlo." >&2
        exit 1
        ;;
esac

# ------------------------------------------------------------ aplicación

case "$(uname -m)" in
    x86_64|amd64) ARCH=x64 ;;
    aarch64|arm64) ARCH=arm64 ;;
    *) echo "Arquitectura no soportada: $(uname -m)" >&2; exit 1 ;;
esac

# Con 'curl | bash' no hay archivo de script: BASH_SOURCE está vacío o apunta a la entrada estándar.
SRC="${BASH_SOURCE[0]:-}"
APP_DIR=""
if [[ -n $SRC && -f $SRC ]]; then
    APP_DIR="$(dirname "$(readlink -f "$SRC")")"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
if [[ -n $APP_DIR && -f $APP_DIR/pubspec.yaml ]] && command -v flutter >/dev/null; then
    echo "==> Compilando desde $APP_DIR"
    (cd "$APP_DIR" && flutter build linux --release)
    cp -r "$APP_DIR/build/linux/$ARCH/release/bundle" "$TMP/darttracker"
else
    URL="https://github.com/$REPO/releases/latest/download/darttracker-linux-$ARCH.tar.gz"
    echo "==> Descargando $URL"
    curl -fL --progress-bar "$URL" | tar -xz -C "$TMP"
fi
rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")" "$BIN_DIR"
mv "$TMP/darttracker" "$DEST"
ln -sfn "$DEST/darttracker" "$BIN_DIR/darttracker"

echo "==> Añadiendo DartTracker al menú de aplicaciones"
ICON_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"
APPS_DIR="$HOME/.local/share/applications"
mkdir -p "$ICON_DIR" "$APPS_DIR"
cp "$DEST/data/flutter_assets/assets/darttracker.svg" "$ICON_DIR/darttracker.svg"
# El nombre del .desktop es el ID de la aplicación: así GNOME asocia la ventana con su icono.
# Ruta absoluta en Exec: el entorno gráfico no siempre tiene ~/.local/bin en el PATH.
rm -f "$APPS_DIR/darttracker.desktop" # versiones anteriores
cat > "$APPS_DIR/$APP_ID.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=DartTracker
GenericName=Reproductor de música tracker
Comment=Explora modarchive.org y reproduce módulos MOD, XM, S3M e IT
Exec=$DEST/darttracker
Icon=darttracker
Terminal=false
StartupWMClass=$APP_ID
Categories=AudioVideo;Audio;Player;
Keywords=mod;xm;s3m;it;tracker;modarchive;chiptune;música;
DESKTOP
gtk-update-icon-cache -q -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
update-desktop-database -q "$APPS_DIR" 2>/dev/null || true

echo "==> Creando la carpeta de música"
mkdir -p "${TRACKER_DIR:-$HOME/Música/Tracker}"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "Aviso: $BIN_DIR no está en tu PATH. Añade esto a ~/.bashrc:"
       echo "  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

echo "==> Listo. Abre DartTracker desde el menú de aplicaciones o con: darttracker"
}

main "$@"
