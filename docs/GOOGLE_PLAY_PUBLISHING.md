# Google Play publishing checklist

## Google Play identity

- **Google Play application ID:** `com.mohammedemad333.masari` (selected when `PLAY_STORE_BUILD=true`).
- **Legacy GitHub APK application ID:** `com.example.moodle_reminder` (used for normal APK builds).
- The Google Play Console app has been created by the developer with the Masari ID.
- The Kotlin namespace remains `com.example.moodle_reminder`. It identifies the compiled Android classes, **not** the app ID used by Play; the manifest's relative activity and widget provider names continue to resolve against that namespace.
- Both variants use the same Dart app and features, but Android treats them as **separate apps**. The Play edition will not automatically import data from the old APK, and both may be installed together. Do not rename the registered Play app ID after the first upload.
- Existing `moodlereminder://course` sharing links and method channels are retained for compatibility.


This project has a separate manually triggered workflow at **Actions → Google Play AAB**. It never uploads to the Play Store automatically.

## Blockers to finish before the first Play upload

1. **Package identity prepared:** Play builds select `com.mohammedemad333.masari`; legacy APKs keep their existing ID. Confirm the Play Console app uses the same ID before first upload. The Play workflow checks that the registered ID remains in Gradle.
2. The developer has created a Google Play Console app. Before upload, finish **Play App Signing** enrollment in that app.
3. Generate and retain a private **upload keystore** in a secure backup; never commit the keystore or its passwords. Add GitHub Actions secrets:
   - `PLAY_UPLOAD_KEYSTORE_BASE64` — base64-encoded full `.jks` bytes, without line breaks.
   - `PLAY_STORE_PASSWORD` — upload keystore password.
   - `PLAY_KEY_ALIAS` — upload key alias.
   - `PLAY_KEY_PASSWORD` — key password.
4. From the repository's `main` branch, run **Actions → Google Play AAB → Run workflow** and download the signed `masari-play-aab` artifact (AAB and SHA-256). It expires after 14 days. Ordinary GitHub APK release artifacts use the legacy ID and debug signing and are **not Play-ready**. The upload artifact is not published automatically to Play Console.
5. Upload AAB to **Internal testing** first; test fresh install, Moodle connection, push/local reminders, background sync, widgets, ZIP imports/exports, course QR links, RTL, notifications and Android 16 behavior.
6. Prepare a publicly accessible privacy-policy URL, content rating, target audience, Data safety disclosure, app access instructions if necessary, ads declaration, screenshots, store icon (512 × 512), feature graphic (1024 × 500), title and descriptions. Verify every disclosure against the final implementation. Do not publish an unverified privacy claim.
7. Review the **SCHEDULE_EXACT_ALARM** permission with Play Console and confirm the app's exact-reminder behavior; avoid restricted `USE_EXACT_ALARM` unless eligibility is established.
8. Check Play Console's account-specific testing eligibility and production access requirements before rollout. Review the final AAB's target SDK (36), **application ID `com.mohammedemad333.masari`**, signing certificate, and version code (currently `4` from `2.2.0+4`). Increase `pubspec.yaml` build number for each subsequent Play upload.

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

The last command **without Play environment variables** produces a debug-signed, legacy-ID test artifact; use the dedicated GitHub workflow to produce a Play-signed bundle with the registered application ID. Never send or commit signing keys or passwords.
