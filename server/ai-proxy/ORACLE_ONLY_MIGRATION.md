# Oracle-only AI migration — incremental rollout

Only the Masari **AI assistant** moves off Firebase. Google sign-in,
Google backup, Google sync and Moodle calendar functions remain unchanged.

## Stage 1 (this PR): local durable quota engine

- `postgres_quota.mjs` reserves per-minute, per-UTC-day and global counters
  atomically in PostgreSQL using a transaction and a fixed advisory lock.
- Backend selection: `MASARI_QUOTA_BACKEND=postgres`; otherwise the running
  `firestore` implementation remains the default.
- A separate **Masari-specific** database, credentials and Docker service
  must be prepared. Do not reuse or modify EduBridge or other applications'
  databases or roles.
- The Postgres URL is a secret. Store it in a root-restricted server-side
  environment file and **never** put it in an APK or the repository.
- This phase is code-only. No Oracle container, Caddy or live Firestore settings
  have been changed. Leave the live backend on Firestore until the new isolated
  database is provisioned and migrations are verified.

## Stage 2: Oracle-issued owner sessions and pairing

Implement a dedicated on-server owner account and short-lived, revocable
device sessions. Pairing must use a one-time secret that is generated and shown
only in an SSH session, transmitted to the server over TLS, and stored in
Android secure storage. Never use a hard-coded API key in the distributed APK.
Protect pairing with replay prevention and strict request limits, with all
new devices denied until the owner explicitly authorizes them.

## Stage 3: switch Masari AI client

Use the Oracle owner session **only for the AI client**. Do not change the
existing Google Account screen or Google backup/sync credentials. Remove
Firebase ID token and App Check headers from the AI flow only after Oracle
sessions are verified end-to-end and have adequate revocation/rate limiting.

## Stage 4: deployment and rollback

- Deploy a **separate PostgreSQL database** isolated on a Docker internal
  network. Create credentials locally and use persistent volume backups.
- Validate ownership of secret files and `MASARI_UID` / `MASARI_GID`.
- Verify health, authenticated quota writes, 401, 429, restart persistence and
  rejection of forged/revoked sessions.
- Keep the old assistant auth path until the new official signed APK works.
- Preserve existing Caddy `ai.edubridge.win` TLS route to localhost:8097.
- TokenRouter remains the LLM provider; do not expose its API key.

A PostgreSQL request-count limit is not a TokenRouter billing limit. Keep a
provider-side budget limit before granting access beyond the owner.
