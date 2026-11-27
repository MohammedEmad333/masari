# Oracle Accounts staging and production rollout

This runbook applies only to the dedicated Masari Oracle services. Do not
run its commands against EduBridge databases or unrelated containers.

## Container names

Production:
- `masari-ai-proxy`
- `masari-accounts-api`
- `masari-postgres`

Staging:
- `masari-accounts-staging`
- `masari-postgres-staging`

Production and staging use separate PostgreSQL volumes and credentials.
Never attach a staging service to the production database volume.

## Read-only preflight

```bash
set -euo pipefail
cd ~/masari-ai-source/server/ai-proxy
git status --short
git rev-parse HEAD
docker ps --filter name=masari --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
docker volume inspect ai-proxy_masari-ai-pgdata
docker volume inspect masari-accounts-pr171_stage_pgdata
docker compose -p ai-proxy -f compose.oracle.yaml \
  -f compose.oracle-postgres.yaml config --quiet
```

Stop if the production database volume is not the expected existing volume,
the working tree has unexplained changes, or a verified backup is unavailable.

## Production endpoints

- AI health: `https://ai.edubridge.win/health`
- Accounts health: `https://masari-accounts.edubridge.win/health`
- AI proxy listens on localhost port 8097.
- Accounts API listens on localhost port 8101.
- PostgreSQL is private on `ai-proxy_default`.

A missing bearer must be rejected with HTTP 401 by
`/v1/assistant/ask` and `/v1/account/me`.

## Google OIDC and sessions

The Accounts API verifies Google OIDC ID tokens against the configured
Google Web Client ID and issues opaque Oracle bearer sessions. The AI proxy
validates those sessions against the same PostgreSQL database. Do not
enable account enrollment for untrusted or automated requests.

## Backups and two-device verification

1. Take a custom-format PostgreSQL backup before server changes.
2. Verify SHA-256 and `pg_restore --list`.
3. Restore a copy into an isolated test database/container.
4. Upload personal tasks and plans from the primary device.
5. Restore missing items on a second device.
6. Enable automatic sync on both devices and test a new task/plan.
7. Test encrypted Moodle calendar backup and restore with the same
   user-supplied passphrase. The passphrase is not stored by Masari.

Personal automatic sync merges missing tasks and plans. Local items win
conflicts. Deletions are not synchronized in this release.

## Rollback and data safety

Keep the prior application image tags and Compose files until the new
services pass health, authentication, backup, and AI checks. Rollback should
replace only the application container. Never delete or recreate the
PostgreSQL volume. Never run `docker compose down -v`, `docker volume rm`,
or `docker system prune` during deployment.
