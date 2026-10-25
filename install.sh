#!/usr/bin/env bash
# Instalación de DartTracker en Fedora o Ubuntu / Debian.
#
# Sin clonar nada:
#   curl -fsSL https://raw.githubusercontent.com/jlcampana/DartTracker/main/install.sh | bash
# Desde una copia del repositorio:  ./install.sh  (compila con dart si lo tienes)
#
# Instala openmpt123 y SQLite (pide sudo), descarga el ejecutable de la última release de GitHub
# y lo deja en ~/.local/bin/darttracker. Volver a ejecutarlo actualiza la aplicación.
set -euo pipefail

REPO="jlcampana/DartTracker"
BIN_DIR="$HOME/.local/bin"

# Todo va dentro de main() para que bash lea el script entero antes de ejecutarlo: con
# 'curl | bash' el script llega por la entrada estándar y dnf/apt podrían comerse el resto.
main() {

# ------------------------------------------------------------ paquetes del sistema

. /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in
    *" fedora "*)
        echo "==> Instalando paquetes del sistema (dnf)"
        sudo dnf install -y curl sqlite-libs openmpt123
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
        sudo apt-get install -y curl libsqlite3-0 openmpt123
        ;;
    *)
        echo "Distribución no soportada (${PRETTY_NAME:-desconocida})." >&2
        echo "Instala a mano curl, la biblioteca de SQLite y openmpt123 y vuelve a ejecutarlo." >&2
        exit 1
        ;;
esac

# ------------------------------------------------------------ ejecutable

mkdir -p "$BIN_DIR"
# Con 'curl | bash' no hay archivo de script: BASH_SOURCE está vacío o apunta a la entrada estándar.
SRC="${BASH_SOURCE[0]:-}"
APP_DIR=""
if [[ -n $SRC && -f $SRC ]]; then
    APP_DIR="$(dirname "$(readlink -f "$SRC")")"
fi
if [[ -n $APP_DIR && -f $APP_DIR/pubspec.yaml ]] && command -v dart >/dev/null; then
    echo "==> Compilando desde $APP_DIR"
    (cd "$APP_DIR" && dart pub get >/dev/null && dart compile exe bin/darttracker.dart -o build/darttracker)
    install -m 755 "$APP_DIR/build/darttracker" "$BIN_DIR/darttracker"
else
    case "$(uname -m)" in
        x86_64|amd64) ARCH=x64 ;;
        aarch64|arm64) ARCH=arm64 ;;
        *) echo "Arquitectura no soportada: $(uname -m)" >&2; exit 1 ;;
    esac
    URL="https://github.com/$REPO/releases/latest/download/darttracker-linux-$ARCH"
    echo "==> Descargando $URL"
    TMP="$(mktemp)"
    curl -fL --progress-bar -o "$TMP" "$URL"
    install -m 755 "$TMP" "$BIN_DIR/darttracker"
    rm -f "$TMP"
fi

echo "==> Creando la carpeta de música"
mkdir -p "${TRACKER_DIR:-$HOME/Música/Tracker}"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "Aviso: $BIN_DIR no está en tu PATH. Añade esto a ~/.bashrc:"
       echo "  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

echo "==> Listo ($("$BIN_DIR/darttracker" --version)). Ejecuta: darttracker"
}

main "$@"
