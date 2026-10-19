# Changelog

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
