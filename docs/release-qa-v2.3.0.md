# Masari 2.3 | UI redesign release-candidate QA

**Status: DEVICE QA REPORTED PASS; RELEASE CANDIDATE CI PENDING.** On 2026-11-19 the project owner confirmed that the requested physical-device tests succeeded. No separate device logs or sanitized screenshots were attached to this record, so device results are owner-reported rather than independently evidenced here. The release candidate must still pass CI on the exact version-bump commit and the official signed APK must be verified. Google Play Internal Testing is tracked separately.

## Scope and traceability

The UI refresh is split into isolated changes. Confirm these commits are reachable from the eventual release candidate's `main` history before evaluating the release:

| PR | Behavior to preserve or verify |
| --- | --- |
| [#182](https://github.com/MohammedEmad333/masari/pull/182) | Brand tokens, Material 3 light/dark and RTL-friendly components |
| [#183](https://github.com/MohammedEmad333/masari/pull/183) | Five bottom tabs: Home, Tasks, Schedule, Courses, More; Calendar/Week segmented switch |
| [#184](https://github.com/MohammedEmad333/masari/pull/184) | Dashboard insight counts and offline/error banners |
| [#185](https://github.com/MohammedEmad333/masari/pull/185) | Tasks search, course filtering, completed items and reset |
| [#186](https://github.com/MohammedEmad333/masari/pull/186) | Agenda chronological order, empty day and Today button |
| [#189](https://github.com/MohammedEmad333/masari/pull/189) | Read-only local library search, hierarchy and course totals |
| [#190](https://github.com/MohammedEmad333/masari/pull/190) | File/link tiles and chapter counts; no file ID changes |
| [#191](https://github.com/MohammedEmad333/masari/pull/191) | More quick actions: account, backups, plans and assistant |
| [#192](https://github.com/MohammedEmad333/masari/pull/192) | Assistant privacy notice explaining the external model and data limits |
| [#194](https://github.com/MohammedEmad333/masari/pull/194) | Remove repeat consent checkbox; only Ask AI tap sends the typed question and a bilingual send disclosure stays visible |

Keep `com.mohammedemad333.masari`, existing local storage, OAuth/Oracle/Firebase configuration, notification scheduling and signing identity unchanged. UI review is not permission to migrate or delete user records. The current public release remains `v2.2.19` until a separately approved candidate is signed and verified.

## Automated gate (record commit SHA and run URL)

- [ ] `dart format lib test` produces no diff.
- [ ] `flutter analyze` passes without errors.
- [ ] `flutter test` passes, including `test/masari_redesign_smoke_test.dart`, navigation, design system, calendar agenda, task filters, library and assistant disclosure.
- [ ] Android release **smoke** APK builds with the correct package ID. A CI smoke APK is not the official signed installation artifact.
- [ ] Google Play AAB **smoke** builds with a temporary CI key. Do not distribute a CI-signed AAB.
- [ ] No unexpected changes to `pubspec.yaml` version, application ID, persistence data model, permissions, or release signing.
- [ ] Dependency PRs, if any, are assessed separately: a green test does not automatically authorize a notification-plugin upgrade.

## Physical device matrix (record device / Android / language / theme / evidence)

| Area | Test actions | Expected behavior | Result |
| --- | --- | --- | --- |
| First start | Clean install signed test build, choose Arabic; switch to English | No crash, each of five tabs labeled and reachable | PASS (owner-reported) |
| Upgrade | Upgrade from *compatible signed* 2.2.19 with existing manual tasks and local library | All records, files, reminders, theme and language preserved | PASS (owner-reported) |
| RTL | Arabic, 320–360dp screen, system font scale 1.3–1.5 | Navigation, back chevrons, date rows and buttons readable; no overflow | PASS (owner-reported) |
| Dark mode | Test main 5 tabs, cards, dialogs, filters and assistant notice | Legible foreground/background and semantic error contrast | PASS (owner-reported) |
| Navigation | Open Home shortcuts, Schedule Calendar/Week, Courses library and More shortcuts | All original routes accessible; back returns to correct destination | PASS (owner-reported) |
| Tasks | Search a title, filter a course, inspect Today/Completed, clear filters | Results and search field agree; stored tasks unaffected | PASS (owner-reported) |
| Calendar | Select day with two deadlines in reverse source order; jump to Today | Ordered by due time; no reordering or deletion in stored records | PASS (owner-reported) |
| Offline | Disable data with previously cached tasks and saved course files | Offline warning is actionable; tasks and local resources open | PASS (owner-reported) |
| Library | Search by course, chapter, and material; open local file, web link, ZIP import/export and QR share | Counts correct; hierarchy, links, files and imports preserved | PASS (owner-reported) |
| Sync | Connect primary/additional Moodle calendars, refresh, and revisit Courses | Source filters, synced events and error states preserved | PASS (owner-reported) |
| Backups | Open Google/Oracle account and backup from More; restore *test-only data* | No inadvertent overwrite, lost credentials or broken route | PASS (owner-reported) |
| Assistant | Open More → assistant; type a harmless question without tapping Ask AI, then tap Ask AI once; repeat in Arabic and English | No checkbox or auto-send; clearly visible external-service disclosure; one intentional tap sends only the typed question; auth and secret screening still enforced | PASS (owner-reported) |
| Notifications | Test now and schedule a near-future manual-task reminder in Arabic then English | Delivery and language match; permission and alarm fallback clear | PASS (owner-reported) |
| Reboot | Restart Android with pending reminders; reopen app | Records persist and reminder restoration behaves as expected | PASS (owner-reported) |
| Play test | Install separately signed candidate through Google Play Internal Testing | OAuth/App Check/Play Integrity behavior verified on real Play install | Pending (separate Play verification) |

For device results, attach sanitized screenshots (no tokens, private iCalendar URLs, identities, or signed-in personal information) and record any reproducible failures in the release PR.

## Release decision

- [ ] All automated checks green on **the same** candidate commit (pending version-bump PR CI).
- [x] Project owner reports all requested physical-device matrix tests passed on 2026-11-19; attach sanitized device evidence when available.
- [x] Upgrade and backup/restore tests reported passed by the project owner (no separate device logs attached).
- [x] App Check / Play Integrity and Oracle sign-in device checks reported passed by the project owner; issue [#180](https://github.com/MohammedEmad333/masari/issues/180) will retain this report.
- [x] Official upload signing certificate and Android application ID were verified by the existing signed release workflow.
- [x] Candidate version set to 2.3.0+24 in this separate release PR.
- [ ] Production release and immutable tag published after candidate CI succeeds, then APK SHA-256 verified.

**Do not claim Masari 2.3 is released merely because the redesign PRs are merged.**
