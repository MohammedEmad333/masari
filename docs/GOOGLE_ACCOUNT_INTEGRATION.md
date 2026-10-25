# Google account integration — Masari

## Product behavior
- Optional Google account sign-in; offline ICS usage works without login.
- Never use Google sign-in as Moodle authentication. The private ICS URL remains separate and device-protected.
- Account settings: sign in, account display name, sign out, disconnect cloud synchronization.
- A clear consent screen before enabling cloud backup, explaining what data leaves the device.
- Phase 1 backs up **user-created tasks and plans only** (including group assignments that do not contain email by default), after authentication is working. Exclude Moodle ICS tokens, browser cookies, and Moodle passwords entirely.
- On login, offer merge / keep local / restore cloud choices and show conflicts before overwriting any local work.
- Deleting a Google-linked account from Masari must remove server-stored backups after explicit confirmation, not merely sign out.

## Proposed technology
- Flutter google_sign_in + Firebase Authentication for Google identity; Cloud Firestore for per-account synchronization.
- Firebase project has to be created by the app owner, enable Google sign-in, register Android application ID `com.mohammedemad333.masari`, and configure all appropriate signing fingerprints (official upload/release and Play app-signing fingerprints).
- Use Firebase CLI / FlutterFire CLI to generate official configuration. Do not hand-create or commit private service account keys.
- Firestore rules: users may read/write only records beneath their own Firebase Auth UID. Tests must prove cross-user reads/writes are denied.
- No account should ever be mandatory for local notifications, offline task management, or ICS synchronization.

## Delivery increments
1. Authentication adapter + mock-backed unit tests + bilingual sign-in screen; no change to existing startup/ICS path.
2. Configure Firebase credentials and verify Android official APK Google sign-in on a physical device.
3. Explicit opt-in cloud backup of manual tasks and personal plans. Model document version and updatedAt, deterministic IDs, conflict resolution and offline replay.
4. Cross-account task collaboration only after user identity and access controls are verified; use group membership and authorization rather than local labels.
5. Document OAuth scopes, data retention, disconnect/delete workflow, user disclosure, and test cases for privacy.

## Acceptance criteria
- New user can use Masari with no Google account.
- Valid Google sign-in and sign-out do not reset the local task cache.
- Invalid/cancelled sign-in does not crash Masari.
- Official release signing configuration works (SHA fingerprints verified).
- Two devices logged into one account can restore tasks without duplication.
- Two different accounts cannot access one another's data.
- No Moodle authentication token is ever uploaded.
