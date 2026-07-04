# Contributing to Mushi Player

Thanks for your interest in contributing!

## Development setup

```bash
flutter pub get
flutter run   # Android device or emulator
```

## Before opening a PR

1. Run `flutter analyze` — should report **no issues**
2. Run `flutter test` — all tests should pass
3. Keep changes focused; match existing code style and structure

## Platform scope

Playback is **Android-only**. Changes to `ios/`, `web/`, `linux/`, `macos/`, or
`windows/` are welcome for scaffolding/consistency, but the native music engine
lives under `android/app/src/main/kotlin/com/gennaro16/mushiplayer/`.

## Release builds

Release APKs currently use the **debug signing key** so `flutter build apk
--release` works without extra setup. Before publishing to the Play Store, add
your own signing config in `android/app/build.gradle.kts`. See the
[Flutter app signing guide](https://docs.flutter.dev/deployment/android#signing-the-app).

## Questions or ideas?

Open an issue describing the bug, feature, or question. Screenshots help for UI
issues.
