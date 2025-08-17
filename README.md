# Orgami

## Flavors and configuration

Android flavors are configured: `dev`, `staging`, `prod`.

Run commands:

- Dev: `flutter run --flavor dev -t lib/main.dart`
- Staging: `flutter run --flavor staging -t lib/main.dart`
- Prod: `flutter run --flavor prod -t lib/main.dart`

Environment variables:

- GOOGLE_MAPS_API_KEY: set in CI or local shell, consumed via Android manifest placeholders.
- VAPID_KEY (Web FCM): provide at runtime or via `--dart-define=VAPID_KEY=...` when building web. The code path should read from env/defines before falling back.

Firebase options per flavor: run `flutterfire configure` for each flavor and commit generated options, or maintain separate options files and select by flavor using `--dart-define=FLAVOR=dev|staging|prod`.

## CI

GitHub Actions workflow runs analyze, tests, and prints upgradable dependencies via `flutter pub outdated --mode=upgradable`.
