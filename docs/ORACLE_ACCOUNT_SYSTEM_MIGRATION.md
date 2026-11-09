# Masari accounts on Oracle — staged migration (no Firebase for new account API)

## Scope and rollout status

This branch introduces a **Firebase-free** Oracle account API, backed by the
**Masari-owned PostgreSQL database** already used for Oracle AI sessions.
It also adds an opt-in Flutter account screen and manual personal backup.

**Not yet a production cutover.** No Oracle VM, DNS, Caddy, PostgreSQL data,
existing Firebase accounts or EduBridge services are changed by this PR.
Do not remove Firebase services or delete existing backups during migration.

### Existing vs. new

| Feature | Existing Firebase route | New Oracle route |
| --- | --- | --- |
| Identity | Google Sign-In -> Firebase Auth | Google OIDC verified by Oracle |
| Server session | Firebase ID token / App Check | Expiring opaque `msr_` bearer; hash in PostgreSQL |
| Profile | Firebase user | `masari_account_profiles` |
| Manual task/plan backup | Firestore | `masari_account_documents/personal` |
| Encrypted calendar backup | Firestore | API supports `calendar` encrypted envelopes; client migration pending |
| Automatic task synchronization | Firestore | **Not yet migrated**; disabled in Oracle UI mode |
| Account deletion | Firebase / unavailable | Oracle deletes linked data, sessions and mappings |
| AI assistant | Firebase fallback or separate Oracle sessions | Existing AI unchanged pending full review |

Local Moodle/ICS operation does **not** require signing in.

## HTTPS API contract (Oracle only)

The app supplies `MASARI_ACCOUNTS_API_URL=https://<dedicated-host>`.
This is a public base URL and **not a credential**.

- `POST /v1/auth/google-oidc`: Google-issued OIDC ID token in Authorization;
  exactly empty JSON body `{}`. Oracle verifies Google RSA signatures, issuer,
  audience, expiration and subject, rate-limits attempts, then issues an opaque
  1-hour session. No Firebase authentication or App Check.
- `GET /v1/account/me`: current account profile.
- `PATCH /v1/account/me`: edit display name.
- `DELETE /v1/account/me`: explicit confirmation header; delete Oracle
  account data, revoke sessions, remove Google mappings.
- `POST /v1/auth/logout`: revoke this bearer token server-side.
- `GET|PUT|DELETE /v1/backups/personal`: user-owned manual tasks and plans.
- `GET|PUT|DELETE /v1/backups/calendar`: **encrypted envelope only**; keep
  the calendar passphrase exclusively on the client.
- `GET /health`: process-only health, no auth. Do not treat this as DB readiness.

No API route accepts `uid` or `accountId` from clients: the server derives
ownership strictly from the verified session's PostgreSQL account ID.
Sensitive values must not appear in URL query strings or logs. Limit HTTP
body size, use TLS and add reverse-proxy abuse controls before public use.

## Oracle deployment preparation — no production commands executed

1. Confirm the actual Masari PostgreSQL volume and credential locations.
   Never alter EduBridge or its shared databases/services.
2. Configure a dedicated Google OAuth **Web client ID** whose audience exactly
   matches the Google token returned by the signed Android build.
3. The existing `compose.oracle-postgres.yaml` now defines `masari-accounts`,
   using `accounts_index.mjs` (Node.js 22) and the existing isolated Masari
   PostgreSQL volume. This adds a **loopback-only** host port 8099 by default;
   inspect port availability before deploying.
4. Configure TLS at a dedicated account API hostname. On Docker bridge
   networks, connect Caddy to the account service using its actual network;
   do not assume it can reach localhost in another container.
5. Use `MASARI_ACCOUNTS_API_URL` in a **test APK first**. Never place database
   credentials or Google secret keys in the APK.
6. Exercise sign-in, multi-account isolation, logout/revocation, account
   deletion, Android process restart, backup/restore and 401/429/503 behavior.
   Test backups on two devices; verify no cross-account reads or uploads.
7. Migrate the existing Firebase backups only with explicit per-user consent,
   after a successful Oracle backup + restore verification. Preserve the
   Firestore documents until users verify the new copy. Do not transfer raw
   calendar URLs: decrypt and re-encrypt on the device.
8. Move automatic synchronization and encrypted calendar UI to Oracle,
   remove the legacy Firebase fallback, update user disclosures and privacy
   policy, and only then consider removing Firebase dependencies.

## Authentication and deletion safeguards

- Google is only the identity provider; account IDs, sessions, backups and
  ownership rules are controlled by Oracle/PostgreSQL.
- Google `sub` is the durable identity key, **not** changeable email.
- PostgreSQL stores a SHA-256 digest of each random bearer token, never the
  bearer itself. Tokens expire in an hour and can be revoked.
- Logout while offline clears the local token, but server revocation may only
  occur upon reconnection or token expiry. Future versions should queue a
  revoke request or implement an account-wide device/session manager.
- Account deletion removes profile/backups/session hashes/Google links and
  disables the orphan UUID. Local tasks and Moodle links remain, by design.
- The personal task backup is **not end-to-end encrypted**. Access is restricted
  to the user by server authentication, PostgreSQL, TLS and operational
  security; the operator can read personal task data. The calendar backup is
  client-side encrypted separately.

## CI

Run `node --test` from `server/ai-proxy` and build the production Docker image.
The new API has isolated tests for verified Google sign-in, account ownership,
profile changes, encrypted calendar shape, logout, and explicit deletion.
Flutter must pass `dart format`, `flutter analyze`, `flutter test`, APK
smoke build and test AAB build.

**Deploy gate:** this document and PR do not mean the Oracle account system
is live. Keep the legacy account path available until every migration gate passes.
