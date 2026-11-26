# Google OIDC and Oracle account integration

Google is used only as the identity provider. The app obtains a Google OIDC
ID token using google_sign_in and exchanges that token directly with the
Masari Oracle account API. Firebase Authentication and Firestore are not
used.

Oracle verifies the Google signature, issuer, audience, expiry and subject.
It owns account IDs, revocable sessions, profile data and account backups.
PostgreSQL stores account mappings and session-token hashes.

Moodle credentials, private ICS URLs and browser sessions remain on-device.
Personal task/plan backups are stored on Oracle after explicit user action or
opt-in sync. Moodle calendar URLs are encrypted on the device before upload.

Google sign-in is optional. Local tasks, Moodle calendars, offline access and
notifications remain usable without an account.
