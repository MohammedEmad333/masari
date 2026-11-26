# Masari AI: Oracle-only authentication and quota migration

Masari's AI endpoint accepts only Oracle-issued opaque sessions. Firebase ID
tokens and App Check headers are not accepted. PostgreSQL is the only durable
quota backend.

## Request flow

1. The student signs into Masari using Google OIDC through the Oracle account
   API. Google is the identity provider; Oracle owns the account and session.
2. Oracle verifies the Google ID token, maps the stable Google subject to an
   account ID, and issues a random short-lived bearer token.
3. The app stores that token in Android secure storage.
4. The AI proxy hashes and verifies the bearer against PostgreSQL, checks
   expiry and revocation, then atomically reserves PostgreSQL quota.
5. Only the explicitly submitted question, language and consent flag are
   forwarded to TokenRouter.

## Deployment

The AI and account services must share the same Masari PostgreSQL database.
Set protected PostgreSQL and TokenRouter secret files in the server
environment. There is no Firestore fallback and no Firebase configuration.

## Legacy data

This migration does not delete Firestore backups. The new app cannot access
them. Users who need legacy backup data should restore/export it with an older
build before upgrading, then back it up to Oracle. Verify the new backup
before removing any old data manually.

## Verification

Run Node tests and PostgreSQL integration tests. On Android, verify Google
OIDC sign-in, session expiry and renewal, logout/revocation, account deletion,
AI authentication, quotas, encrypted calendar backup, and local/offline
Moodle functionality. A successful CI build does not prove the live Oracle
deployment is updated.
