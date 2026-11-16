# Masari v2.2.19 release-candidate verification

Status: **Not approved for publication** until the device checks below are recorded as passing. This document is a manual test plan, not evidence that a device has been tested.

## Baseline

- Base main commit: `2dd1300e03fbe9212fc6bf3c6dc43382dbc752fc`
- Candidate version: `2.2.19+23`
- Android application ID: `com.mohammedemad333.masari`
- Kotlin: `2.4.21`; Android Gradle Plugin: `9.1.1`; Gradle: `9.3.1`
- Android compile SDK: `37`; target SDK: `36`
- Firebase Core `^5.1.0`; Firebase Auth `^7.0.1`; App Check `^0.5.1`; Firestore `^7.1.0`
- Flutter local notifications `^23.0.0`
- Previous published version: `v2.2.18`

## CI gate

- [ ] Flutter formatting, analysis and unit/widget tests pass on the candidate commit.
- [ ] Temporary-key APK smoke build passes with the stable application ID.
- [ ] Temporary-key Play AAB smoke build passes; these CI test artifacts **must not be distributed**.
- [ ] Release-signing workflow guard verifies the registered application ID and expected upload certificate before any official signed build.
- [ ] Official release is **not** created just to run the device tests. Use the manually-dispatched, separately labeled signed QA APK workflow and review its job logs.

## Real Android device matrix

Record the device model, Android version, package version and install source for each checked case. Prefer a device with Google Play services and, if available, a second Android device/OEM.

| Case | Steps | Expected | Result / evidence |
| --- | --- | --- | --- |
| Clean install | Install the officially signed QA APK; open app | Opens with package `com.mohammedemad333.masari`; no startup crash | Pending |
| Existing-install update | Upgrade a compatible signed `com.mohammedemad333.masari` installation | Tasks, local library and settings persist | Pending |
| Oracle sign-in | Sign in using the configured Google/Oracle account flow | Session is established, securely stored and restored | Pending |
| AI request | Consent to one safe test question | Oracle bearer flow responds without relying on Firebase App Check for an Oracle session | Pending |
| AI access denial | Test an expired/denied Oracle session in a controlled setup | Clear Oracle account error; no claim that Firebase App Check failed | Pending |
| Firebase fallback / App Check | If legacy fallback is enabled, test a device with missing Play Integrity token | Distinct retrieval diagnostic; no network request with missing token | Pending |
| Firebase server rejection | If fallback is enabled, exercise a controlled HTTP 403 response | Distinct server rejection message; no token output | Pending |
| Google sign-in / cloud | Sign in and run an opt-in backup/restore in a disposable test account | User-owned Firestore backup remains available with no Moodle credential exposure | Pending |
| Notifications | Grant notifications; schedule a reminder and send an in-app test notification | Notifications arrive in Arabic and English as selected | Pending |
| Exact alarm fallback | Without optional exact-alarm permission, schedule a future reminder | Inexact fallback works or displays actionable, non-misleading status | Pending |
| Reboot and package replace | Schedule reminder, reboot and update a compatible signed build | Reminder schedule survives or is restored as expected | Pending |
| Offline data | Open existing tasks and shared course files with network disabled | Cached tasks, local course files and ZIP imports remain available | Pending |
| ZIP safety | Attempt an invalid manifest / missing attachment import | Import is rejected without modifying local course data | Pending |
| Play internal test | Install the signed AAB using Google Play Internal Testing | Package and OAuth/Firebase signing registration are correct | Pending |

## Release decision

- [ ] All CI gates pass.
- [ ] Device evidence is attached to issue [#180](https://github.com/MohammedEmad333/masari/issues/180) for App Check / Play Integrity and to the release PR for general QA.
- [ ] No user data, account credentials or signing secrets are placed in logs/screenshots.
- [ ] Confirm the production Oracle endpoints and expected upload certificate in the official signed build.
- [ ] Approve candidate PR for merge only after QA, because a green `main` CI run automatically invokes the public GitHub APK publishing workflow.
- [ ] After merge, check the signed APK, its SHA-256 file and the immutable GitHub Release tag; then verify Google Play Internal Testing before broader distribution.

**Do not merge this release-candidate PR before the real-device gate is complete.**
