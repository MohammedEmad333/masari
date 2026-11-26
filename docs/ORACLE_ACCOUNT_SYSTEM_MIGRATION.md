# Masari accounts on Oracle: Firebase-free architecture

## Current target architecture

Masari uses Google OpenID Connect only to establish identity. The Oracle
accounts API verifies the Google token and issues an opaque, short-lived
session. Account profiles, session hashes, personal task/plan backups,
encrypted calendar backups and AI quota counters are stored in the
Masari-owned PostgreSQL database.

The Android application has no Firebase Core, Firebase Authentication,
Firebase App Check or Cloud Firestore dependencies. The AI proxy accepts only
Oracle sessions and PostgreSQL is its only quota backend.

## Data and migration safety

Local Moodle ICS links, task cache, study plans, reminders and library files
remain local. Calendar links are encrypted on the device before an optional
Oracle backup.

Existing Firestore documents are not deleted or migrated automatically. The
new app cannot access legacy Firestore backups. Users who need them should
restore/export with a legacy Masari build before installing the Firebase-free
release, then verify the Oracle backup. No cloud records are deleted by this
repository change.

## Production rollout gate

This source migration does not deploy the Oracle VM, update Caddy, provision
PostgreSQL, change DNS or modify production records. Before publishing an APK,
verify:

1. The account API and AI proxy use the same Masari PostgreSQL database.
2. Google OIDC audience and signing identities match the official Android app.
3. Oracle sessions can be issued, renewed, revoked and deleted correctly.
4. Personal backups and encrypted calendar backups round-trip across devices.
5. PostgreSQL quotas persist and reject over-limit requests.
6. Android physical-device tests pass for sign-in, sign-out, offline use,
   reminders, backups and the AI assistant.

Do not claim the production migration is complete until those checks pass.
