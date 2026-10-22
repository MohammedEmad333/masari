# Changelog

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
