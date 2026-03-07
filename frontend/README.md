# diaspora_equb_frontend

Flutter mobile app for Diaspora Equb (DeFi).

## Firebase auth setup

Email/password and Google sign-in require Firebase config.

This repo now includes generated native Firebase config:

- `lib/firebase_options.dart`
- `android/app/google-services.json`

That means Android can run without passing the full Firebase app config through dart-defines. Web still commonly uses runtime dart-defines when you want to override the checked-in config.

Required dart-defines:

- `FIREBASE_API_KEY`
- `FIREBASE_APP_ID`
- `FIREBASE_MESSAGING_SENDER_ID`
- `FIREBASE_PROJECT_ID`

Optional dart-defines:

- `FIREBASE_AUTH_DOMAIN`
- `FIREBASE_STORAGE_BUCKET`
- `FIREBASE_MEASUREMENT_ID`
- `FIREBASE_ANDROID_CLIENT_ID`
- `FIREBASE_IOS_CLIENT_ID`
- `FIREBASE_IOS_BUNDLE_ID`
- `GOOGLE_WEB_CLIENT_ID`

Current Android application ID in this repo:

- `com.example.diaspora_equb_frontend`

Current generated Firebase app IDs in this repo:

- Web: `1:608960233059:web:5a0bf553da2f8c6d170256`
- Android: `1:608960233059:android:0ec3ac064fb12375170256`
- iOS: `1:608960233059:ios:36e6ab1e90b3b859170256`
- Windows: `1:608960233059:web:4d0706e55e3e43c9170256`

Firebase app mapping:

- Web: create a Firebase Web app and use its config for browser sign-in.
- Android: the repo already contains `android/app/google-services.json` for package name `com.example.diaspora_equb_frontend`.
- Google sign-in on Android should use both:
  - `FIREBASE_ANDROID_CLIENT_ID`: optional override if you want to force a native client ID at runtime
  - `GOOGLE_WEB_CLIENT_ID`: the server client ID used during Google sign-in

Example web run:

```bash
flutter run -d chrome \
  --dart-define=API_BASE_URL=http://localhost:3001/api \
  --dart-define=WALLETCONNECT_PROJECT_ID=your_walletconnect_project_id \
  --dart-define=FIREBASE_API_KEY=your_api_key \
  --dart-define=FIREBASE_APP_ID=your_app_id \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=your_sender_id \
  --dart-define=FIREBASE_PROJECT_ID=your_project_id \
  --dart-define=FIREBASE_AUTH_DOMAIN=your_project.firebaseapp.com \
  --dart-define=FIREBASE_STORAGE_BUCKET=your_project.firebasestorage.app \
  --dart-define=GOOGLE_WEB_CLIENT_ID=your_web_client_id.apps.googleusercontent.com
```

Example Android run:

```bash
flutter run -d android \
  --dart-define=API_BASE_URL=http://10.0.2.2:3001/api \
  --dart-define=WALLETCONNECT_PROJECT_ID=your_walletconnect_project_id \
  --dart-define=RPC_URL=https://rpc.cc3-testnet.creditcoin.network \
  --dart-define=GOOGLE_WEB_CLIENT_ID=608960233059-mhrm5pcc4o7bhqvtuvn3n5dd0tn7c08b.apps.googleusercontent.com
```

Android notes:

- Use `http://10.0.2.2:3001/api` for the backend when running on the Android emulator.
- Use your machine's LAN IP instead of `localhost` when running on a physical Android device.
- If you change the Android package name, update both Firebase and `android/app/build.gradle.kts` to match.
- Because `firebase_options.dart` and `google-services.json` are already present, the exact Android run command above does not need the full Firebase app config defines.

Backend Firebase session exchange also requires these backend env vars:

- `FIREBASE_PROJECT_ID`
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY`

Without both sides configured, the app can render the auth UI but cannot complete a true Firebase-to-backend login flow.

## Android build (APK under 30 MB)

If you get **"unsupported Gradle project"**, run once from **frontend**: `.\repair_android_gradle.bat` (or `flutter create . --project-name diaspora_equb_frontend`). Then from the **frontend** directory run:

If Android Studio or VS Code shows a `dev.flutter.flutter-plugin-loader` failure with `metadata.bin` / `Buffer underflow`, the same repair script also clears the corrupted Gradle Kotlin DSL cache before regenerating `android/`.

- **Windows:** From frontend folder run `.\build_android_under_30mb.bat` (PowerShell) or `build_android_under_30mb.bat` (CMD). From repo root: `frontend\build_android_under_30mb.bat`
- **Or:** `flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols`

APKs are in `build/app/outputs/flutter-apk/`. See [ANDROID_BUILD_UNDER_30MB.md](ANDROID_BUILD_UNDER_30MB.md) for details.
