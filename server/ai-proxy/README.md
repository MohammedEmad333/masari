# Masari AI proxy (optional, NOT deployed)

A small HTTPS-reverse-proxied **read-only** backend to connect Masari's opt-in
study chat to `openai/gpt-oss-120b` on TokenRouter without exposing the
provider key in the Android APK.

## Security model

- Flutter sends **only** a user-typed question, chosen language and explicit
  per-request consent, never task objects, ICS URLs, tokens, descriptions or
  Google cloud-backup content.
- The proxy verifies Firebase ID tokens using Firebase Admin and checks UID.
- No changes to local tasks, calendars, reminders or Google synchronization.
- System prompt disallows claims of calendar access. This is not a substitute
  for validating any future structured commands.
- The server rejects obvious URLs and credential-like content in text; this
  **cannot guarantee** detection of every sensitive detail.
- All Firebase-verified accounts may use the online assistant after explicitly
  consenting to transmission of their question. Google sign-in is only
  required for the optional online assistant, not calendar and offline tasks.
- Firestore transactions reserve 3 requests/user/minute, 10 requests/user/UTC
  day and a shared 300 requests/UTC day **across proxy instances**. Existing
  in-process limits (5/user/minute and 30/user/day) add a local safeguard.
- Request-count caps are **not billing caps**. Limits will stop new requests,
  but cannot guarantee a fixed dollar ceiling, and account abuse remains possible.
  Configure spending limits and alerts with TokenRouter, plus Firebase App Check
  and anti-abuse controls, before exposing this service to all users.
- If quota Firestore is down, the service fails closed (HTTP 503). Firestore
  must be enabled in the Firebase project, and the server identity requires
  read/write access to the `masari_ai_usage` collection.
- The service does not log message bodies or ID tokens. Transport must use
  HTTPS. TokenRouter and its upstream model providers are third parties;
  verify their data retention, billing and residency policies.

## First-time setup on a trusted server

Prerequisites: Node.js >= 20, Firebase project `masari-bb658`, an Admin SDK
credential configured through Application Default Credentials (ADC), a
TokenRouter key, an enabled Cloud Firestore database, and a TLS-terminating reverse proxy. Never commit a Firebase
service account private key or `TOKENROUTER_API_KEY` to GitHub.

From `server/ai-proxy`:

```bash
npm install --omit=dev
export FIREBASE_PROJECT_ID=masari-bb658
export TOKENROUTER_API_KEY='(set as a protected environment secret)'
export GOOGLE_APPLICATION_CREDENTIALS='/secure/path/to/service-account.json'
export HOST=127.0.0.1
export PORT=8096
npm start
```

The example above documents the necessary environment variables. Prefer
a process manager, protected secret injection and workload identity instead
of placing credentials in shell history. **Do not paste a real API key into
committed files or a client build.** Configure key rotation and remove any
temporary terminal history with secrets.

Use Caddy/Nginx HTTPS reverse proxy at a hostname **you control**, forwarding
to `127.0.0.1:8096` (not a publicly open backend port). A sample Caddy
virtual host (replace the hostname only after DNS/TLS is ready):

```caddyfile
ai.your-domain.example {
    reverse_proxy 127.0.0.1:8096
}
```

Android Flutter builds enable the optional button only when the PUBLIC proxy
URL is configured:

```bash
flutter build apk --release \
  --dart-define=MASARI_AI_PROXY_URL=https://ai.your-domain.example/v1/assistant/ask
```

It must be exactly an HTTPS URL ending `/v1/assistant/ask`, without query
params. The URL is not a secret. The endpoint rejects unauthenticated
requests. Standard release workflows do not configure this yet, so the online
assistant stays disabled by default.

## Run tests

```bash
cd server/ai-proxy
node --check core.mjs
node --check index.mjs
node --test
```

No real Firebase or TokenRouter API key is required for the isolated tests.

Firestore quota records include an `expiresAt` timestamp. Configure a TTL policy
for `masari_ai_usage.expiresAt` in the Firestore console to delete old records;
Firestore may charge for document reads/writes and TTL deletions. The single
shared daily record is intended for controlled early traffic, not very high
throughput without additional quota sharding and load testing.

## Before enabling in production

1. Explicitly confirm permission to use the teammate's API key on a server
   and assign billing limits / ownership; test with a limited-privilege key.
2. Deploy on infrastructure with protected runtime secrets and valid HTTPS;
   validate Firebase project ID and official Android Google sign-in.
3. Verify Firestore transactional quotas and configure Firebase App Check
   (Play Integrity for production Android) with backend verification before
   public release. Add provider-side spend limits, global budget alerts and
   operational metrics.
4. Test large responses, timeouts, 429, 401, malformed responses, network
   disruptions, app foreground/background and account sign-out.
5. Document data retention, purpose, deletion/disconnect and third-party
   sharing to users; obtain consent before external transmission.
6. Do not advertise AI-generated task scheduling: no write endpoints exist.

Keep `npm install` dependencies locked before a repeatable production
deployment; an exact package-lock is not part of this initial scaffold.

**Rollout status:** This PR prepares a multi-user quota backend; it does not
publish a domain, configure Firebase App Check, activate Play Integrity,
provision secrets or deploy to Oracle/Firebase. Do not enable the online AI
button for the public until these release gates are completed and reviewed.
