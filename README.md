# Offline A4 Studio

A fully offline Flutter app for Android and iOS that builds print-ready A4 photo layouts on-device.

## Features

- Camera capture and gallery import through native mobile pickers
- A4 editor with configurable row/column grid and automatic photo slot creation
- Tap-to-select slots with drag, pinch-resize, and crop gestures
- PNG overlay import with optional apply-to-all photo compositing
- Cutting border guides with adjustable spacing and border width
- 300 DPI PNG export (`2480 x 3508`) and A4 PDF export
- Direct mobile printing through the platform print sheet
- Dark professional UI optimized for phones and tablets
- Riverpod state management, CustomPainter rendering, GestureDetector interactions
- Local-only file storage; no server and no cloud processing

## Development

```sh
flutter pub get
flutter run
```

## Verification

```sh
flutter analyze
flutter test
```
