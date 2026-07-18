#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter was not found. Install Flutter and run flutter doctor first."
  exit 1
fi

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

flutter pub get
flutter analyze
flutter test

echo "Checks complete. Run: flutter run"
