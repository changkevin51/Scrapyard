#!/usr/bin/env bash
# Package python/mathreader_app for Serious Python.
# Usage (from repo root): ./tools/package_mathreader_python.sh Android
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PLATFORM="${1:?Platform: Android|iOS|Darwin|Windows|Linux}"

export SERIOUS_PYTHON_VERSION=3.12
export SERIOUS_PYTHON_SITE_PACKAGES="$ROOT/build/site-packages"
export SERIOUS_PYTHON_APP="$ROOT/build/python-app"
export SERIOUS_PYTHON_ANDROID_EXTRACT_PACKAGES=mathreader
export SERIOUS_PYTHON_BUNDLE_ID=com.example.koto
export SERIOUS_PYTHON_ALLOW_SOURCE_DISTRIBUTIONS=imutils,ply,idx2numpy

mkdir -p "$SERIOUS_PYTHON_SITE_PACKAGES" "$SERIOUS_PYTHON_APP"

if [[ "$PLATFORM" == "Android" || "$PLATFORM" == "iOS" ]]; then
  REQ="python/mathreader_app/requirements-mobile.txt"
else
  REQ="python/mathreader_app/requirements-desktop.txt"
fi

echo "Packaging MathReader sidecar for $PLATFORM (Python $SERIOUS_PYTHON_VERSION)"
dart run serious_python:main package python/mathreader_app -p "$PLATFORM" \
  -r -r -r "$REQ" \
  -r --no-deps -r mathreader==0.163

find "$SERIOUS_PYTHON_SITE_PACKAGES" "$SERIOUS_PYTHON_APP" \
  \( -name '*.h5' -o -name '*.npz' \) -delete 2>/dev/null || true

echo "Done. SERIOUS_PYTHON_APP=$SERIOUS_PYTHON_APP"
