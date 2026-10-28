# One-time Oracle pairing — storage foundation

This change adds internal PostgreSQL storage logic only. It is not yet reachable
over HTTP, and does not disable Firebase authentication or App Check.

- Codes are generated from 32 bytes of cryptographically secure randomness.
- Database stores SHA-256 code hashes, never plaintext codes.
- Codes expire after 10 minutes by default (maximum 15 minutes).
- Redemption uses a row lock and transaction. A code can issue at most one
  session even when multiple devices race to redeem it.
- Sessions are generated from separate secure random bytes and persisted only
  as SHA-256 hashes. Database failures roll back both writes.

To complete enrollment in a future change:
1. Provide an **SSH-only** provisioning command that creates an account and
   prints a one-time pairing code, without writing it to logs.
2. Add a narrowly scoped HTTPS redemption route with request size limits,
   global/IP rate limits and denial responses that do not leak account details.
3. Store the returned session in Android secure storage, ensure account
   recovery and token revocation, and test forged/replayed/expired tokens.
4. Keep the old Firebase-protected endpoint intact until the new official
   APK works end-to-end.

Do not run this database migration on live Oracle yet. It is inert code only.
