# Masari Oracle production deployment

Masari production uses one dedicated PostgreSQL 17 database for Oracle
accounts, opaque sessions, personal backups, encrypted calendar backups,
and AI quotas. The Android application and both server services use Google
OIDC plus short-lived Oracle bearer sessions. Firebase Authentication,
Firebase App Check, Firestore and Firebase Admin are not runtime dependencies.

## Live production topology

| Purpose | Container | Image | Host binding |
|---|---|---|---|
| AI proxy | `masari-ai-proxy` | `masari-ai-proxy:oracle-e5e57de` | `127.0.0.1:8097 -> 8096` |
| Accounts API | `masari-accounts-api` | `masari-accounts:oracle-e5e57de` | `127.0.0.1:8101 -> 8098` |
| PostgreSQL | `masari-postgres` | `postgres:17-alpine` | private Compose network only |

The production Compose project for AI and PostgreSQL is `ai-proxy`.
The Accounts API is maintained as a separate Compose project named
`masari-accounts-production`, attached to the external network
`ai-proxy_default`. Caddy routes
`ai.edubridge.win` to localhost port 8097 and
`masari-accounts.edubridge.win` to localhost port 8101.

The existing production PostgreSQL volume is
`ai-proxy_masari-ai-pgdata`. Do not rename, remove, recreate empty, or
prune this volume during application deployments. PostgreSQL's internal
service alias remains `masari-ai-postgres` for backwards-compatible DNS
resolution, even though its container name is `masari-postgres`.

## Staging topology

Staging is isolated from production:

- Accounts: `masari-accounts-staging`
- PostgreSQL: `masari-postgres-staging`
- Compose project: `masari-accounts-pr171`
- PostgreSQL volume: `masari-accounts-pr171_stage_pgdata`
- Accounts host binding: `127.0.0.1:8099 -> 8098`

Never connect staging to the production volume or production credentials.

## Private runtime files

The server directory requires protected files:

- `private/tokenrouter_api_key`
- `private/postgres_client_password`
- `private/postgres_server_password`

The production Accounts API reads the same PostgreSQL client password file
as the AI proxy. Google OAuth Web Client ID is supplied as
`MASARI_GOOGLE_OAUTH_CLIENT_ID`. Do not commit secret files or expose
their contents in logs, chat, screenshots, or GitHub.

## Compose configuration

From `~/masari-ai-source/server/ai-proxy`, validate the AI and database
configuration:

```bash
export MASARI_UID="$(id -u)"
export MASARI_GID="$(id -g)"
docker compose -p ai-proxy -f compose.oracle.yaml \
  -f compose.oracle-postgres.yaml config --quiet
```

Validate production Accounts separately:

```bash
export MASARI_GOOGLE_OAUTH_CLIENT_ID="<configured Google Web Client ID>"
docker compose -p masari-accounts-production \
  --project-directory "$PWD" \
  -f compose.oracle-accounts-production.yaml config --quiet
```

Do not paste the OAuth value into logs or chat. The actual production
deployment may be managed from the existing
`~/masari-accounts-production/compose.yaml`; keep that file synchronized
with this canonical template.

## Backup and deployment safety

Before changing the PostgreSQL container, take a custom-format dump and
verify it with `sha256sum` and `pg_restore --list`. For a stronger restore
test, restore into an isolated temporary PostgreSQL container and compare
the required schema and row counts.

Never run `docker compose down -v`, `docker volume rm`, or
`docker system prune` as part of a Masari deployment. Application image
updates must not recreate the PostgreSQL volume. Keep an independently
stored backup outside this VM for disaster recovery.

## Health and functional verification

- GET `/health` confirms process health only.
- Verify unauthenticated account and AI requests return HTTP 401.
- Verify Google OIDC sign-in and Oracle session persistence on a real device.
- Verify the AI proxy accepts the same Oracle bearer session.
- Verify PostgreSQL quota reservations persist across restarts.
- Verify personal backup ownership, revision conflicts, and account deletion.
- Verify encrypted Moodle calendar backup round-trip on two devices.
- Configure provider-side TokenRouter spending limits separately.
- Never expose prompts, bearer tokens, pairing codes, Moodle calendar URLs,
  or personal backup contents in logs.

## Migration status

The deployed production services use Oracle/PostgreSQL and have passed
real-device Google sign-in, two AI questions, personal backup upload/restore,
two-device automatic task/plan sync, and encrypted calendar-link restore.
Database backups have been restored successfully in an isolated test.

This document records the verified deployment state; it does not execute
commands or modify the live server.
