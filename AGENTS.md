# AGENTS.md

## Cursor Cloud specific instructions

This is a pure Flutter/Dart mobile app ("Offline A4 Studio") with no backend, no database, and no external services. All processing is on-device.

### Development commands

- **Install deps:** `flutter pub get`
- **Lint/analyze:** `flutter analyze`
- **Run tests:** `flutter test`
- **Run app (web):** `flutter run -d web-server --web-port=8080 --web-hostname=0.0.0.0`
- **Build web:** `flutter build web`

### Environment notes

- Flutter SDK is installed at `/opt/flutter`. PATH must include `/opt/flutter/bin` and `/opt/flutter/bin/cache/dart-sdk/bin`.
- The `main` branch contains only `README.md`. All application code lives on the `cursor/offline-flutter-editor-f236` branch.
- The app targets Android and iOS natively. For Cloud Agent testing, add web platform support via `flutter create --platforms=web .` then use the web dev server. Clean up generated `web/` directory before committing if it was not in the original branch.
- Linux desktop build requires additional native toolchain packages (`libstdc++-13-dev`, `lld`, `llvm-18`, `g++`) and still has linking issues in the Cloud Agent VM. Prefer the web target for testing.
- Dart SDK constraint is `^3.11.5`; Flutter 3.41.9 (stable) satisfies this.
