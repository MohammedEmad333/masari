# Masari assistant

The online study assistant is an Oracle-authenticated service, not a local
calendar agent. It does not read the user's Moodle calendar, local tasks,
notes, tokens or backup contents. It receives only the text the student
explicitly submits, its selected language and a consent flag.

The Android app sends requests to the public HTTPS endpoint configured by
MASARI_AI_PROXY_URL. The request uses an Oracle-issued short-lived bearer
session. No Firebase ID token, App Check token or provider API key is embedded
in the APK.

## Security and limits

- The client rejects obvious URLs and credential-like strings before sending.
- The server verifies Oracle sessions against PostgreSQL and enforces durable
  per-user and global request quotas in PostgreSQL.
- The proxy does not log prompts, bearer tokens or provider response bodies.
- TokenRouter remains a third-party model provider. Configure provider-side
  spending limits and review its retention and privacy terms.
- The assistant cannot create, edit, complete or reschedule Masari tasks.

Run Flutter tests and the Node/PostgreSQL CI suite before publishing.
