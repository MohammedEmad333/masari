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

## Oracle-only deployment checklist

The Google endpoint is rate-limited in PostgreSQL: 100 exchange attempts
per minute globally and 5 per verified UID per minute. Exceeding either
returns HTTP 429; database failure returns HTTP 503 (fail closed). Edge
rate limiting should additionally protect unauthenticated traffic.

On the existing Oracle host, after CI passes and merge is confirmed:

```bash
cd ~/masari-ai-source/server/ai-proxy
git pull --ff-only origin main
docker compose -f compose.oracle.yaml -f compose.oracle-postgres.yaml config --quiet
# Before the first rollout, back up Masari's own PostgreSQL database.
docker compose -f compose.oracle.yaml -f compose.oracle-postgres.yaml up -d --build --no-deps masari-ai
curl -fsS http://127.0.0.1:8097/health
curl -fsS https://ai.edubridge.win/health
curl -i -X POST https://ai.edubridge.win/v1/auth/google \
  -H 'Content-Type: application/json' -d '{}'
```

Expect HTTP 401 on the unauthenticated exchange check (not HTTP 200).
The Google-only Flutter mode requires the production-signed Android build
flag `--dart-define=MASARI_GOOGLE_ORACLE_AUTH_ENABLED=true` in addition
to `MASARI_AI_PROXY_URL`, **only after** production App Check works.

Never paste Firebase tokens, App Check tokens, session tokens, secret files
or pairing codes in logs or chat. Keep older APKs on the current backend
path until the Google-only client is tested and published.
