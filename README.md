<div align="center">

<img src="android/app/src/main/res/drawable-nodpi/masari_launcher.webp" alt="Masari application icon" width="180" />

# مساري | Masari

**Masari (formerly Moodle Reminder)** — a privacy-friendly Flutter companion for Moodle deadlines, background calendar sync, and reliable local reminders.

[![Flutter CI](https://github.com/MohammedEmad333/moodle-reminder/actions/workflows/flutter-ci.yml/badge.svg)](https://github.com/MohammedEmad333/moodle-reminder/actions/workflows/flutter-ci.yml)
[![Release](https://github.com/MohammedEmad333/moodle-reminder/actions/workflows/release.yml/badge.svg)](https://github.com/MohammedEmad333/moodle-reminder/actions/workflows/release.yml)
[![Latest release](https://img.shields.io/github/v/release/MohammedEmad333/moodle-reminder?display_name=tag)](https://github.com/MohammedEmad333/moodle-reminder/releases/latest)
[![Platform](https://img.shields.io/badge/platform-Android-3DDC84)](https://github.com/MohammedEmad333/moodle-reminder/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-3.47.6-02569B?logo=flutter)](https://flutter.dev/)

[**Download latest APK**](https://github.com/MohammedEmad333/moodle-reminder/releases/latest) · [**View releases**](https://github.com/MohammedEmad333/moodle-reminder/releases) · [**Changelog**](CHANGELOG.md)

</div>

---

## Overview

Masari turns Moodle's official private iCalendar (`.ics`) export into a focused deadline companion. It keeps an offline cache, refreshes deadlines in the background, schedules local reminders, and never asks for or stores a Moodle password.

The project is designed around privacy, offline usefulness, predictable reminder behavior, and a clean separation between UI, state, parsing, storage, background work, and notifications.

## Latest release

**Masari v2.2.1 (build 5)** is prepared for verified, consistently signed distribution.

- GitHub release APK: [`masari-v2.2.1.apk`](https://github.com/MohammedEmad333/moodle-reminder/releases/download/v2.2.1/masari-v2.2.1.apk) (available only after green `main` CI and successful signed publishing).
- Google Play release: run the manual **Google Play AAB** workflow; it uses the *same existing upload-key secrets*.
- Store application ID: `com.mohammedemad333.masari`.

> **Important migration warning:** Earlier GitHub APKs used `com.example.moodle_reminder` and a temporary debug signing key. The new APK will not replace that installation or move its local data. Keep your original app installed until your records are safely backed up. Google Play App Signing may use a different signing certificate from the upload key, so prefer **Play Internal Testing** when testing eventual Play upgrades.

## Highlights

| Area | What Moodle Reminder provides |
| --- | --- |
| Deadline tracking | Home dashboard, urgency states, countdowns, calendar agenda, and course grouping |
| Reminders | Multiple offsets: 3 days, 2 days, 1 day, 6 hours, 1 hour, plus due-now |
| Background sync | Android WorkManager refresh approximately every six hours when constraints allow |
| Offline support | Cached deadlines and last-sync state remain available without a connection |
| Completion state | Mark deadlines completed locally to suppress further reminders |
| Languages | English and Arabic with RTL support |
| Appearance | System, light, and dark themes |
| Moodle integration | Uses Moodle's exported private iCalendar URL; no Moodle password is requested |
| ICS parsing | `UID`, `DTSTART`, `DTEND`, `TZID`, `URL`, `LOCATION`, `STATUS`, `SEQUENCE`, `LAST-MODIFIED`, folded lines, escaped text, and date-only events |
| Reliability | Stable notification IDs derived from Moodle event UIDs and exact-alarm fallback behavior |

## Privacy and security

The Moodle calendar export URL contains a private access token, so Moodle Reminder treats it as a secret.

- The private calendar URL is stored with `flutter_secure_storage`, not plain preferences.
- The app never asks for a Moodle username or password.
- Deadline metadata is cached locally for offline use.
- Disconnecting Moodle removes the secure URL, cached deadlines, sync timestamp, and local completion state from the app.
- `USE_EXACT_ALARM` is intentionally not requested. The app uses `SCHEDULE_EXACT_ALARM` with user approval where Android requires it and falls back to inexact scheduling when necessary.

See [SECURITY.md](SECURITY.md) for vulnerability reporting and the supported security model.

## Getting started

### 1. Export your Moodle calendar

1. Open Moodle.
2. Open **Calendar**.
3. Choose **Export calendar**.
4. Generate and copy the private calendar URL.
5. Open Moodle Reminder.
6. Paste the URL and choose **Connect securely**.

### 2. Install the app

Download the latest Android APK from the [Releases page](https://github.com/MohammedEmad333/moodle-reminder/releases/latest).

If you want to verify the downloaded file, compare its SHA-256 digest with the `.sha256` file attached to the same release.

## Architecture

```text
lib/
├── main.dart
├── app_controller.dart
├── models/
│   └── deadline.dart
├── screens/
│   └── home_shell.dart
└── services/
    ├── background_sync_service.dart
    ├── calendar_repository.dart
    ├── ics_parser.dart
    └── notification_service.dart
```

### Responsibilities

- **`CalendarRepository`** owns network access, secure calendar URL storage, cached deadlines, and sync metadata.
- **`AppController`** owns application state and coordinates user-facing actions.
- **ICS parser** converts Moodle iCalendar data into normalized deadline models.
- **Background sync service** refreshes the feed under Android WorkManager constraints.
- **Notification service** schedules and updates local reminders using stable IDs.
- **UI layer** consumes controller state and does not directly own persistence or network logic.

Compatibility export files remain at `lib/ics_parser.dart` and `lib/notification_service.dart` for code importing the original paths.

## Reminder model

For each upcoming deadline, Moodle Reminder can schedule reminders at:

- 3 days before
- 2 days before
- 1 day before
- 6 hours before
- 1 hour before
- due time

Completed or expired deadlines are excluded from future reminder scheduling. Stable IDs derived from Moodle event UIDs reduce duplicate-notification problems across refreshes.

## Background behavior

Android WorkManager refreshes the calendar approximately every six hours, subject to operating-system scheduling, connectivity, and battery constraints. It is intentionally not treated as an exact six-hour timer.

After a successful refresh, the app updates its offline cache and rebuilds the local reminder schedule from the latest Moodle data.

## Android permissions

Moodle Reminder uses:

- `INTERNET` — download the Moodle calendar feed.
- `POST_NOTIFICATIONS` — request notification permission on supported Android versions.
- `SCHEDULE_EXACT_ALARM` — request precise alarm access where applicable.
- `RECEIVE_BOOT_COMPLETED` — allow reminder scheduling to recover after device reboot.

## Android distribution identities

- **Official APK from GitHub Releases:** `com.mohammedemad333.masari`, using the stored Play **upload** key; signing is stable across these official GitHub builds.
- **Google Play AAB:** the same registered app ID, signed with the upload key. Google Play may re-sign installed APKs with a different **app-signing** key.
- **Flutter CI APK artifact:** legacy `com.example.moodle_reminder` with a temporary debug signature, intended **only for smoke tests**. Do not use it for updating an installed app.
- Existing legacy installations and new Masari installations are **two different Android applications**. App data does not move across package IDs automatically. Do not uninstall your old installation before backing up local data.
- The Kotlin source namespace and existing `moodlereminder://course` sharing scheme are preserved for compatibility.

See [Google Play publishing](docs/GOOGLE_PLAY_PUBLISHING.md) for signing and upload instructions.

## Development

### Requirements

- Flutter 3.38.1 or newer
- Dart 3.10 or newer
- Java 17 for Android builds

The CI and release workflows currently pin Flutter **3.47.6**.

### Local verification

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --release # legacy test APK only; never publish
```

### Run locally

```bash
flutter pub get
flutter run
```

## Testing and CI

The project uses GitHub Actions for continuous verification. Application, dependency, Android, and CI changes run formatting checks, static analysis, unit tests, and a release APK build. Documentation-only pull requests and pushes are skipped to avoid unnecessary Android builds.

`test/ics_parser_test.dart` covers important calendar parsing behavior including:

- UTC timestamps
- folded iCalendar lines
- date-only events
- event metadata
- malformed event handling

The release workflow independently verifies the source before publishing a versioned APK and SHA-256 checksum to GitHub Releases.

## Release process

Release publishing is automated.

1. Update `version` in `pubspec.yaml`.
2. Add the matching version section to `CHANGELOG.md`.
3. Merge the release metadata to `main`.
4. The release workflow verifies the source, builds the APK, generates its checksum, and publishes the GitHub Release.

For app version `2.2.0+4`, the public tag is `v2.2.0`. The historical package and deep-link identifiers remain unchanged for upgrade compatibility.

## Project goals

Masari focuses on a small, reliable product surface rather than trying to replace Moodle itself:

- make upcoming work visible at a glance;
- keep useful deadline data available offline;
- deliver reminders even when the Moodle web UI is not open;
- protect the private calendar token;
- support Arabic and English cleanly;
- keep the calendar parser and reminder pipeline testable.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) for setup, required checks, pull request expectations, and release guidance.

Use the repository's structured issue forms for public bugs and feature requests. Security-sensitive findings should follow [SECURITY.md](SECURITY.md) and must not expose private Moodle calendar tokens publicly.

## Author

**Mohammed Emad Elrefy**  
Al-Aqsa University — Department of Computer Science  
Software Engineering Project — Supervisor: Eng. Firas Fouad Al-ijla
