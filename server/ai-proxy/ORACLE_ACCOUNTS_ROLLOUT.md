# Oracle-only Masari account service: safe staging rollout

**Do not run this against EduBridge databases or containers.** These steps
apply only to the dedicated `~/masari-ai-source/server/ai-proxy` checkout
and its `masari-ai-postgres` Compose volume. Commands are not executed by CI.

## Read-only server preflight

On the Oracle VM (do not paste secret values in chat or logs):

```bash
set -euo pipefail
cd ~/masari-ai-source/server/ai-proxy
git status --short
git rev-parse --abbrev-ref HEAD
docker --version
docker compose version
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
docker network ls --format 'table {{.Name}}\t{{.Driver}}'
sudo ss -lntp | grep -E ':80 |:443 |:8097 |:8099 ' || true
test -f private/postgres_client_password
test -f private/postgres_server_password
test -r private/postgres_client_password
test -n "${MASARI_GOOGLE_OAUTH_CLIENT_ID:-}"
docker compose -f compose.oracle.yaml -f compose.oracle-postgres.yaml config --quiet
```

**Stop** if the working tree is dirty, port 8099 belongs to another service,
the current Masari database is not identified, the Caddy network is unknown,
or a tested PostgreSQL backup/snapshot is unavailable. Do not run `git reset`,
`docker compose down -v`, `docker volume rm`, or `docker system prune`.

## Test deployment (only after backup and staging approval)

The account service is a separate process; its Docker entrypoint is
`node accounts_index.mjs`. It uses Google OIDC **without Firebase
credentials, Firestore, Firebase Auth, or App Check**.

```bash
cd ~/masari-ai-source/server/ai-proxy
export MASARI_UID="$(id -u)"
export MASARI_GID="$(id -g)"
# Set MASARI_GOOGLE_OAUTH_CLIENT_ID to the app's verified Google Web OAuth ID.
# Never put database passwords, Firebase private keys, or Google credentials here.
docker compose -f compose.oracle.yaml -f compose.oracle-postgres.yaml \
  up -d --build masari-accounts
docker compose -f compose.oracle.yaml -f compose.oracle-postgres.yaml \
  ps masari-accounts masari-ai-postgres
curl --fail-with-body --silent http://127.0.0.1:8099/health
curl -s -o /dev/null -w '%{http_code}\n' \
  http://127.0.0.1:8099/v1/account/me
```

Expect `{"status":"ok"}` and **401** for a missing bearer. Do not run
against an unverified or shared database; automatic schema setup occurs on
service startup. No real account data is migrated by starting the service.

If using existing Caddy **host networking**, the private upstream is
`127.0.0.1:8099`. If using a **bridge network**, inspect its true network
name and use `compose.oracle-accounts-caddy-network.yaml` with
`CADDY_NETWORK` so Caddy can access `masari-accounts:8098`.
Only add an HTTPS virtual host after a backup and `caddy validate`.
Never expose PostgreSQL or port 8099 publicly.

## Android staging gates

1. Confirm the OAuth Web client ID, official Android package and release
   signing fingerprint match the app registered with Google.
2. Build and install a signed **test** APK with
   `MASARI_ACCOUNTS_API_URL=https://<account-host>` only after TLS and Caddy
   have been verified. Do not publish the APK before device testing.
3. Test real Google sign-in, session restart/renewal, logout/revocation,
   account deletion and 401/409/429/503 handling.
4. Test two accounts on two devices; verify neither can view or overwrite
   the other's private backup. Simulate simultaneous edits to confirm
   revision conflicts are retried without losing tasks.
5. Opt-in migration: in a legacy build, restore Firestore backups to local
   data; only after the user confirms their data is intact, sign in to Oracle
   and manually upload. Verify Oracle restore on a second test device.
   Leave old Firestore backups intact until the user verifies the transfer.
6. AI must use the same **Masari** PostgreSQL session database and have
   Oracle auth enabled to accept its new account bearer; otherwise keep AI
   disabled in the Oracle test build.

No instructions above operate on EduBridge's Postgres/database, Caddy
deployment, DNS, Firestore console, or any production customer records.
