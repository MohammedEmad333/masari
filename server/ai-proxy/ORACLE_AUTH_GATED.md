# Gated Oracle authentication integration

This change is **disabled by default**. Do not switch on production merely by
merging it. The existing official APK continues to use Firebase Auth + App Check,
with PostgreSQL for quota counters.

When `MASARI_ORACLE_AUTH_ENABLED=true`, the Node proxy:
- Requires `MASARI_QUOTA_BACKEND=postgres` and creates Oracle account, session,
  pairing and rate-limit schemas.
- Accepts securely validated `msr_` bearer tokens from PostgreSQL and checks
  revocation and expiry before bypassing Firebase App Check.
- Retains Firebase Auth+App Check for existing users.
- Adds `POST /v1/assistant/pair` with one-time database-backed codes.
- Applies an atomic global 10-attempts/minute PostgreSQL limit before pairing,
  in addition to process-local throttling. The client IP is deliberately not
  accepted from caller-controlled HTTP headers.

**Security and rollout limitations**: This is a server-side foundation,
not a finished Android login flow. Session TTL is currently 1 hour; no
refresh/recovery UX or Android secure-storage integration exists yet.
Before enabling, add authenticated session lifecycle management, device
recovery, abuse telemetry and edge rate limiting, with real-device testing.
Keep the flag absent/off until all are verified. Do not send pairing secrets
in chat or commit them.

No production host or Caddy config is changed by this PR.
