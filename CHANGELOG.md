# Changelog

## 2.2.16

- Add optional Oracle AI device pairing with a one-time code and encrypted Android session storage.
- Use a validated Oracle session for the AI assistant without Firebase App Check; retain Google calendar and backup authentication unchanged.
- Display Arabic and English pairing/session errors. Oracle authentication must be enabled and securely provisioned on the server before pairing works.

## 2.2.15

- Enable the optional TokenRouter-powered online study assistant in the normally signed Masari release, behind Firebase Google sign-in, Firebase App Check (Play Integrity) and explicit per-question consent.
- Route online questions exclusively through the existing Oracle proxy over HTTPS; never embed TokenRouter keys or Moodle calendar tokens in the APK.
- Keep offline calendar, manual tasks, and notifications available without online AI.

## 2.2.14

- Filter courses by primary or additional Moodle calendars, or show all together.
- Keep private Moodle calendar tokens hidden from the course filter UI.


## 2.2.13

- Open the Masari home screen without requiring a Moodle connection.
- Offer an optional calendar connection card on the home screen and move connection/import methods to Settings.
- Keep offline tasks, plans, Google sign-in and backups accessible without Moodle.


## 2.2.12

- Add optional Firestore backup and additive restore for manual tasks and plans.
- Add end-to-end encrypted backup of primary and additional Moodle calendar URLs using a separate user-provided passphrase.
- Keep Moodle passwords and session cookies off cloud storage; enforce user-owned backup access in Firestore security rules.


## 2.2.11

- Add optional Google account sign-in and sign-out using Firebase Authentication, without moving Moodle credentials or tasks to the cloud.
- Unify Android package identity to `com.mohammedemad333.masari` across APK and AAB builds.
- Require the stable official upload certificate for distributable GitHub and Google Play builds; prevent CI-only signatures from being published.
- Register Firebase configuration and Google OAuth for the official Masari package and signed releases.


## 2.2.10

- Localize immediate and scheduled Masari reminders, including test messages, due-date timestamps, and singular/plural minute/hour/day labels for Arabic and English.
- Preserve imported task and course names exactly as provided by students and Moodle.
- Propagate saved language to background Moodle notifications, re-schedule future alerts when switching languages, and display widget summaries according to Masari's selected language.
- Localize Android's course sharing chooser, replace raw browser connectivity errors with translated feedback, and complete Moodle calendar network error translations.
- Add automated regression tests for notifications, saved locale changes, native widget language propagation, and browser error coverage.

## 2.2.9

- Replace the manual task dialog with independent date and time pickers, optional notes, priority, and clear form validation.
- Provide 5, 15, and 30 minute reminders alongside 1, 6, and 24 hour options, a global default, and a no-notifications choice.
- Show task-specific reminder settings in the details sheet and allow editing or deleting saved manual tasks.
- Save or update manual tasks by stable ID before scheduling Android reminders, avoiding duplicate tasks after scheduling errors.
- Preserve existing tasks with backwards-compatible reminder settings and add regression tests.

## 2.2.8

- Fix Android notification initialization by replacing the old launcher mipmap reference with a dedicated white notification drawable, retained in release builds.
- Decouple immediate test notifications from device timezone-plugin lookups.
- Schedule one-shot reminder instants using UTC; preserve their absolute timestamps even if an Android OEM reports an unrecognized timezone alias.
- Add regression tests for UTC alarm conversion and release notification resources.

## 2.2.7

- Fix the misleading permission-denied message shown when Android reminders fail to initialize or schedule despite notification access being enabled.
- Skip redundant notification permission requests and optional exact-alarm prompts, while retaining inexact scheduling fallback when special alarm access is unavailable.
- Display separate permission, initialization, and scheduling errors; handle test notification failures in the UI.
- Add regression tests for each repair outcome.

## 2.2.6

- Correct false Moodle synchronization failures when Android notification scheduling fails after the calendar has already downloaded and been saved.
- Keep actual calendar download errors distinct from reminder errors, and show a reminder-repair warning in the app.
- Add regression tests for successful calendar refresh with notification failure and for real HTTP errors.

## 2.2.5

- Differentiate Moodle's HTTP 200 calendar-export authentication, disabled export, HTML and empty response failures without revealing tokens.
- Decode ICS response bytes as UTF-8 despite incorrect server charset headers.
- Add offline import of previously downloaded Moodle ICS files, with a clear note that manual imports do not auto-refresh.
- Translate these calendar error messages to Arabic.

## 2.2.4

- Allow primary Moodle calendar refresh to succeed when an additional feed is unavailable, while retaining previously cached deadlines and showing a partial-sync warning.
- Distinguish connection, timeout, HTTP and non-iCalendar responses to improve troubleshooting of private Moodle calendar links.
- Build a separately versioned, officially signed Android APK after successful main-branch CI, with application ID `com.mohammedemad333.masari`.

## 2.2.3

- Improved Moodle iCalendar feed validation and errors for HTML/login responses.
- Applied the clean Masari launcher icon without black corners.
- Removed downloadable legacy smoke APK from Flutter CI so users install only stable-signed official GitHub Releases.
- Prepared official version 2.2.3 (build 7) for publishing after verified main CI.

## 2.2.2

- Simplified Moodle connection to a secure iCalendar URL, with assisted university sign-in and on-device link capture where supported.
- Added safe editing of the private calendar URL; invalid replacements preserve the saved feed and deadlines.
- Added a reminder-repair control and platform timezone configuration with inexact alarm fallback and bounded scheduling.
- Kept manual tasks and existing offline caches intact.

## 2.2.1

- Incremented Android version and build number to **2.2.1+5**.
- Fixed startup black-screen risks and made failed initialization recoverable.
- Preserved manual, Moodle API and session reminders during background sync; improved offline planning and widget updates.
- Improved Arabic Moodle sync error feedback and RTL course filtering.
- Signed official Android APK releases with the existing Google Play upload secrets, instead of per-run debug keys.
- Explicitly separated legacy CI smoke artifacts from installable official releases.
- Preserved the legacy package and its data during transition to the registered Play package `com.mohammedemad333.masari`.

## 2.2.0

- Renamed the application to **مساري / Masari** with a refreshed launcher icon and localized Android app labels.
- Updated the widget and in-app branding while preserving the existing Android application ID and course-sharing links.
- Improved the verified GitHub APK release pipeline and added checksums for signed Google Play AAB artifacts.
- Prepared Android 16 (SDK 36) support and an opt-in signed Google Play bundle workflow.
- Updated the notification dependency and GitHub Actions checkout tooling.


## 2.1.0

- Added a local study library with courses, chapters, copied files, and educational links.
- Added course sharing with links, QR codes, and ZIP bundles that include local attachments.
- Added preview and confirmation before importing shared courses or extracting ZIP attachments.
- Added safe ZIP validation, size limits, and private storage for imported files.
- Added duplicate course detection and merging of new chapters and links.
- Added SHA-256 attachment comparison to skip identical content and preserve changed versions.
- Added a ZIP import preview showing new chapters, new files, changed versions, skipped duplicates and new links.
- Improved study planning and course workflows while retaining the Moodle deadline reminders.

## 2.0.0

- Added secure storage for the private Moodle calendar URL and migration from the old SharedPreferences key.
- Added periodic background calendar synchronization using Android WorkManager.
- Added multiple reminder offsets and stable notification IDs derived from Moodle event UIDs.
- Added exact-alarm permission handling for modern Android versions.
- Expanded ICS parsing to support UID, URL, location, status, sequence, last-modified and TZID values.
- Added local completed/deadline state that suppresses reminders for completed work.
- Added Home, Calendar, Courses and Settings destinations.
- Added Arabic/English UI switching and system/light/dark themes.
- Added onboarding for connecting a Moodle iCalendar feed.
- Added parser unit tests.
- Added GitHub Actions verification for formatting, analysis, tests, and release APK builds.
