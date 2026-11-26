# Oracle-only deployment: Masari AI and accounts

This deployment uses one isolated Masari PostgreSQL database for Oracle
accounts, opaque sessions, personal backups, encrypted calendar backups and
AI quotas. It does not require Firebase or Firestore.

## Required private files

From the server directory, create and protect these files:

- private/tokenrouter_api_key
- private/postgres_client_password
- private/postgres_server_password

Do not create or mount a Firebase Admin JSON file. Do not add Firebase project
IDs or client configuration to the server environment.

## Validate before deployment

1. Inspect the existing Oracle host, Docker networks, ports and Caddy mode.
2. Confirm the dedicated Masari PostgreSQL volume and secret-file ownership.
3. Configure the Google OAuth Web client ID expected by the Oracle OIDC verifier.
4. Confirm the account API and AI proxy share the same private PostgreSQL
   network and credentials.
5. Validate Compose configuration before starting any container.
6. Keep database ports private. Publish only HTTPS routes through the existing
   Caddy instance after verifying its actual network mode.

## Health and security checks

- GET /health confirms process health only.
- Verify account OIDC login with a test account.
- Verify the AI proxy rejects missing, expired and revoked Oracle sessions.
- Verify per-user and global quota counters persist across restarts.
- Verify personal backup ownership, revision conflicts and account deletion.
- Verify encrypted calendar backup round-trip on two test devices.
- Configure TokenRouter provider-side spending caps and alerts.
- Do not expose database credentials, pairing codes, bearer tokens or calendar
  URLs in chat, screenshots, logs or GitHub.

## Migration safety

The Firebase-free application does not query Firestore. Existing Firestore
backups are deliberately left untouched. If users need old Firestore data,
they must export or restore it using a legacy application build before
upgrading, then verify the corresponding Oracle backup. No production
Firestore records are automatically copied or deleted by this code change.

This runbook documents the target deployment. It does not itself change the
live Oracle VM, Caddy configuration, DNS, PostgreSQL volume or production
containers.
