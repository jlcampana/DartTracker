#!/usr/bin/env bash
# Compila los ejecutables (x64 y arm64) y publica la release v<versión de pubspec.yaml> en GitHub.
# Necesita dart y gh con sesión iniciada.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

VERSION="$(sed -n 's/^version: *//p' pubspec.yaml)"
grep -q "const version = '$VERSION';" lib/src/app.dart \
    || { echo "La versión de lib/src/app.dart no coincide con pubspec.yaml ($VERSION)" >&2; exit 1; }

dart pub get >/dev/null
mkdir -p build
for ARCH in x64 arm64; do
    echo "==> Compilando tracker-linux-$ARCH"
    dart compile exe --target-os=linux --target-arch="$ARCH" bin/tracker.dart -o "build/tracker-linux-$ARCH" >/dev/null
done

echo "==> Publicando v$VERSION"
gh release create "v$VERSION" build/tracker-linux-x64 build/tracker-linux-arm64 \
    --title "tracker $VERSION" --generate-notes
