# Google Play publishing checklist

This project has a separate manually triggered workflow at **Actions → Google Play AAB**. It never uploads to the Play Store automatically.

## Blockers to finish before the first Play upload

1. **Choose a permanent unique application ID.** Replace `com.example.moodle_reminder` in `android/app/build.gradle.kts` and adjust Android Kotlin package paths/namespace and activity/widget names together. Confirm ownership and avoid changing it after the app is published. The workflow deliberately rejects the sample ID.
2. Create a Google Play Console app under the account that will own the release. Enroll in **Play App Signing**.
3. Generate and retain a private **upload keystore** in a secure backup; never commit the keystore or its passwords. Add GitHub Actions secrets:
   - `PLAY_UPLOAD_KEYSTORE_BASE64` — base64-encoded full `.jks` bytes, without line breaks.
   - `PLAY_STORE_PASSWORD` — upload keystore password.
   - `PLAY_KEY_ALIAS` — upload key alias.
   - `PLAY_KEY_PASSWORD` — key password.
4. Run **Actions → Google Play AAB → Run workflow** and download the signed `masari-play-aab` artifact. It expires after 14 days. GitHub APK release artifacts are **not Play-ready** because the normal APK build uses debug signing.
5. Upload AAB to **Internal testing** first; test fresh install, Moodle connection, push/local reminders, background sync, widgets, ZIP imports/exports, course QR links, RTL, notifications and Android 16 behavior.
6. Prepare a publicly accessible privacy-policy URL, content rating, target audience, Data safety disclosure, app access instructions if necessary, ads declaration, screenshots, store icon (512 × 512), feature graphic (1024 × 500), title and descriptions. Verify every disclosure against the final implementation. Do not publish an unverified privacy claim.
7. Review the **SCHEDULE_EXACT_ALARM** permission with Play Console and confirm the app's exact-reminder behavior; avoid restricted `USE_EXACT_ALARM` unless eligibility is established.
8. Check Play Console's account-specific testing eligibility and production access requirements before rollout. Review the final AAB's target SDK (36), signing certificate and version code. Increase `pubspec.yaml` build number for each Play upload.

## Local upload-key generation (keep private)

```sh
keytool -genkeypair -v -keystore upload-keystore.jks -keyalg RSA -keysize 4096 -validity 10000 -alias upload
base64 -w 0 upload-keystore.jks
```

Place only the base64 result in GitHub Actions **Secrets and variables → Actions** and securely store the original file and passwords. Do not send the key or passwords in a chat.

## Publishing metadata draft (review before submission)

**English short description:** Track Moodle deadlines, get reminders, and organize courses offline.

**Arabic short description:** تابع مواعيد مودل وواجباتك ونظّم مساقاتك مع تذكيرات ذكية.

Masari is an independent companion for Moodle's private calendar feed. It does not claim affiliation with or endorsement by the Moodle project or any university.

## Privacy-policy preparation

Before publishing, write a public policy describing: private iCalendar tokens stored securely on device; deadline metadata cached locally; external Moodle server requests and optional Moodle web services; local notifications/background refresh; file imports and course sharing; whether analytics, crash reports or other SDKs transmit data; deletion and contact instructions. Audit all dependencies and Android components before completing the Google Play Data safety form.

## Verification

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build appbundle --release
```

The last command **without the Play secrets** produces a debug-signed test artifact; use the dedicated GitHub workflow for a Play upload bundle.
