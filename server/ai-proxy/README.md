# Masari AI proxy (optional, NOT deployed)

A small HTTPS-reverse-proxied **read-only** backend to connect Masari's opt-in
study chat to `openai/gpt-oss-120b` on TokenRouter without exposing the
provider key in the Android APK.

## Security model

- Flutter sends **only** a user-typed question, chosen language and explicit
  per-request consent, never task objects, ICS URLs, tokens, descriptions or
  Google cloud-backup content.
- The proxy verifies Firebase ID tokens using Firebase Admin and checks UID.
- Pilot access requires an explicit `AI_ALLOWED_UIDS` comma-separated
  list. An absent or invalid allowlist prevents server startup; valid Firebase
  logins not in the allowlist cannot call TokenRouter.
- No changes to local tasks, calendars, reminders or Google synchronization.
- System prompt disallows claims of calendar access. This is not a substitute
  for validating any future structured commands.
- The server rejects obvious URLs and credential-like content in text; this
  **cannot guarantee** detection of every sensitive detail.
- 4 requests in flight, 5 per user per minute, 30 per user per UTC day are
  **in-memory pilot limits**, reset by restart and not shared across replicas.
  This is NOT a cost or abuse-control guarantee for a public production
  deployment. Introduce durable per-user quotas and billing/usage monitoring,
  App Check, account abuse controls and privacy review before public launch.
- The service does not log message bodies or ID tokens. Transport must use
  HTTPS. TokenRouter and its upstream model providers are third parties;
  verify their data retention, billing and residency policies.

## First-time setup on a trusted server

Prerequisites: Node.js >= 20, Firebase project `masari-bb658`, an Admin SDK
credential configured through Application Default Credentials (ADC), a
TokenRouter key and a TLS-terminating reverse proxy. Never commit a Firebase
service account private key or `TOKENROUTER_API_KEY` to GitHub.

From `server/ai-proxy`:

```bash
npm install --omit=dev
export FIREBASE_PROJECT_ID=masari-bb658
export AI_ALLOWED_UIDS='(your Firebase Authentication UID from the Firebase Console)'
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

## Before enabling in production

1. Explicitly confirm permission to use the teammate's API key on a server
   and assign billing limits / ownership; test with a limited-privilege key.
2. Deploy on infrastructure with protected runtime secrets and valid HTTPS;
   validate Firebase project ID and official Android Google sign-in.
3. Add **persistent** quotas (e.g., Firestore transactional counters or Redis),
   App Check where practical, global budget alerts and operational metrics.
4. Test large responses, timeouts, 429, 401, malformed responses, network
   disruptions, app foreground/background and account sign-out.
5. Document data retention, purpose, deletion/disconnect and third-party
   sharing to users; obtain consent before external transmission.
6. Do not advertise AI-generated task scheduling: no write endpoints exist.

Keep `npm install` dependencies locked before a repeatable production
deployment; an exact package-lock is not part of this initial scaffold.

For the **private pilot**, find the account UID under Firebase Console →
Authentication → Users after signing in with Google on a physical device.
Set `AI_ALLOWED_UIDS` in server-only configuration. Do not use a Google email
address or a Google OAuth client ID here. Do not expose a public service without
budget restrictions and durable quotas; a UID allowlist reduces, but does not
eliminate, resource-abuse risks.
