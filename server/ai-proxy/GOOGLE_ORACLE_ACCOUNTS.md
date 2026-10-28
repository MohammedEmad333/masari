# Google-only AI account exchange (staged)

This feature creates one Oracle AI account for each **verified Firebase UID**
that signed in through Google. A verified email address alone is never accepted.

- `POST /v1/assistant/google-session` is available only when **both**
  `MASARI_ORACLE_AUTH_ENABLED=true` and
  `MASARI_GOOGLE_ACCOUNT_EXCHANGE_ENABLED=true`.
- Send Firebase ID token as `Authorization: Bearer ...` and genuine
  Firebase App Check token as `X-Firebase-AppCheck`. No request body.
- The server verifies Firebase token revocation, requires
  `firebase.sign_in_provider == google.com`, checks App Check, maps the UID to
  the same PostgreSQL UUID on every login and issues a one-hour Oracle session.
- The client must store only the issued short-lived Oracle token in secure
  storage; never store Firebase credentials on the server.
- Fail closed on PostgreSQL errors. The old pairing route remains available
  for existing installations until the Google-only client rollout completes.

**Deployment hold:** The new flag is OFF by default. Do not enable it before
Android tests (including valid Google Play Integrity), rate limiting at the
edge and recovery/sign-out flows are verified. This PR does not modify running
Oracle containers or existing calendar/Drive authentication.
