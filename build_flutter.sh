#!/bin/bash
set -e

echo "=== Installing Flutter ==="
git clone https://github.com/flutter/flutter.git -b stable --depth 1 /opt/flutter
export PATH="$PATH:/opt/flutter/bin"

echo "=== Flutter Doctor ==="
flutter doctor --android-licenses || true
flutter doctor

echo "=== Getting Dependencies ==="
cd cafe
flutter pub get

echo "=== Building Flutter Web ==="
flutter build web --release --base-href "/"

echo "=== Build complete ==="
ls -la build/web/
