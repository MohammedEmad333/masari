# Google-only Oracle AI account enrolment

POST /v1/auth/google with Authorization: Bearer <Firebase ID token>,
X-Firebase-AppCheck: <valid App Check token>, Content-Type: application/json
and body {}. Server verifies Firebase token revocation and requires
firebase.sign_in_provider === 'google.com'. No email, user ID, or profile
field supplied by the client is trusted. Firebase UID is mapped to one
Oracle account in PostgreSQL and an hour-long Oracle session is returned.

This endpoint is only mounted when MASARI_ORACLE_AUTH_ENABLED=true.
Existing Oracle pairing and Firebase assistant routes remain for backward
compatibility. **Do not remove legacy pairing until a tested Google-only
Android client is released.** App Check / Play Integrity configuration
must work on production-signed APKs. This foundation does not add an
Android login UI or silent session renewal.

Existing manually paired Oracle accounts are not automatically associated
with Google identities; migration requires explicit verified ownership.
Do not map by email or silently merge their quotas.
