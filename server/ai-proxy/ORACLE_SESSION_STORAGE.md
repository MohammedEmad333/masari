# Oracle session storage — preparation only

This stage introduces `oracle_sessions.mjs` and unit tests. It does **not**
change the current Firebase authentication or App Check enforcement, and
does **not** open public enrolment/session HTTP endpoints.

The proposed PostgreSQL schema defines:
- `ai_accounts`: Oracle-owned user identifiers and account disable timestamps.
- `ai_sessions`: SHA-256 hashes of randomly generated 256-bit bearer tokens,
  expiry, revocation timestamps and the owning account.

Use `SESSION_SCHEMA` only as part of a versioned, reviewed deployment.
A short-lived bearer must be distributed over HTTPS after a secure account
enrolment flow. The secrets must never be stored in source control or app assets.
At minimum, production issuance also requires authenticated enrolment,
rate limiting, audit controls, secure Android storage and session recovery.

## Next PR

Add safe enrolment and refresh/revocation HTTP endpoints with server-side
abuse controls, then wire the Flutter AI client to these endpoints in a
separate opt-in change. Keep Firebase protections enabled until the entire
new flow passes a real-device test.

Current running PostgreSQL quota configuration remains unchanged.
