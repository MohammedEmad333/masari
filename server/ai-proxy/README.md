# Masari AI proxy: Oracle + PostgreSQL

The AI proxy accepts only short-lived Oracle-issued bearer sessions. It has no
Firebase Admin SDK, Firebase Authentication, Firebase App Check, or Firestore
runtime dependency.

## Runtime requirements

- Node.js 22+
- Masari PostgreSQL database, shared with the Oracle accounts API
- TokenRouter API key supplied through a protected server-side secret file
- Google OAuth Web client ID configured on the standalone Oracle accounts API
- HTTPS reverse proxy for public traffic

The Android application sends a user question only after an explicit send
action. The AI proxy verifies the opaque Oracle bearer against PostgreSQL,
reserves a per-account and global quota in PostgreSQL, then calls TokenRouter.
It never reads Moodle links, calendar data or local task records.

## Oracle deployment

The PostgreSQL Compose overlay adds the Masari-only database and account API.
It must be combined with the AI proxy Compose file. The account API and AI
proxy share the same private PostgreSQL volume and credentials. No Firebase
project, Admin SDK JSON or Firestore database is required.

Keep database and provider credentials in protected files under the server's
private directory. Never commit them, include them in the APK, or paste them
into logs.

## Quotas and privacy

The PostgreSQL quota engine atomically enforces per-minute, per-day and global
request caps across proxy instances. These are request limits, not provider
billing limits. Configure TokenRouter spending controls separately.

The server does not log prompts, bearer tokens or upstream response bodies.
The model receives only the text and language explicitly submitted by the
student. The app rejects obvious URLs and credential-bearing text before
sending; this is defence in depth, not a guarantee that every private detail
can be detected.

## Verify

Run Node syntax checks and tests from the server directory, then validate
both Oracle Compose files. CI also runs PostgreSQL integration tests for
account isolation, revision conflicts, session revocation and account deletion.
