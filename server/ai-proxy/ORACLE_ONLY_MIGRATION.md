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

## Isolated database provisioning (not deployed automatically)

This overlay does not touch any existing EduBridge/Postgres or Caddy containers.
It creates `masari-ai-postgres` with its own named volume and **no published
database port**. The client and server need two protected copies of the same
generated password because their container UIDs differ.

On Oracle, from `~/masari-ai-source/server/ai-proxy`:

```bash
cd ~/masari-ai-source/server/ai-proxy
# Use the actual PostgreSQL user UID in postgres:17-alpine (normally 70).
docker run --rm --entrypoint id postgres:17-alpine -u postgres
# Confirm before using 70 in the chown command below.
umask 077
password="$(openssl rand -hex 32)"
printf '%s' "$password" > private/postgres_client_password
printf '%s' "$password" > private/postgres_server_password
unset password
chmod 600 private/postgres_client_password
sudo chown 70:70 private/postgres_server_password
sudo chmod 600 private/postgres_server_password
# Do not print the passwords.
docker compose -f compose.oracle.yaml -f compose.oracle-postgres.yaml config --quiet
```

**Important:** these commands prepare the password only. They do not switch
the running proxy. The owner must verify the UID returned by `docker run`
before setting the server-file ownership. The server file may not be readable
by Ubuntu, and that is intentional.

When ready to switch, run explicitly:

```bash
docker compose -f compose.oracle.yaml -f compose.oracle-postgres.yaml up -d --build
docker compose -f compose.oracle.yaml -f compose.oracle-postgres.yaml ps
curl -fsS http://127.0.0.1:8097/health
```

A working `/health` alone does not prove DB quota writes. Before release,
validate quota reservations with an authenticated user and inspect the
private Postgres logs. Retain the existing Firebase service credentials until
the Oracle session-auth migration is completed. Do not delete Firestore
counters during the transition.

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
