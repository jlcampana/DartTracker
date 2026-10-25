#!/usr/bin/env bash
# Crea y sube la etiqueta v<versión de pubspec.yaml>; GitHub Actions compila los ejecutables
# (x64 y arm64) y publica la release.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

VERSION="$(sed -n 's/^version: *//p' pubspec.yaml)"
grep -q "const version = '$VERSION';" lib/src/app.dart \
    || { echo "La versión de lib/src/app.dart no coincide con pubspec.yaml ($VERSION)" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Hay cambios sin confirmar" >&2; exit 1; }

git tag -a "v$VERSION" -m "DartTracker $VERSION"
git push origin main "v$VERSION"
echo "==> Etiqueta v$VERSION subida. La release sale en unos minutos:"
echo "    https://github.com/jlcampana/DartTracker/actions"
