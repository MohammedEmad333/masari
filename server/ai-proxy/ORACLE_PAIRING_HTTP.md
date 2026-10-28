# Oracle pairing HTTP boundary (not enabled in production)

This PR introduces a pure, injectable HTTP handler for
`POST /v1/assistant/pair`. The handler defaults to **disabled**, and is not
mounted in the running HTTP server. There is no change to Firebase, Flutter,
TokenRouter, or the deployed API.

The handler rejects oversized/malformed bodies, does not trust user-supplied
forwarded IP headers, returns generic errors, and supports per-process
request throttling for development/testing only.

**Security gate before exposure:** implement cross-replica/IP and
account-level durable rate limiting, reverse-proxy forwarding provenance,
owner-only code provisioning via SSH, abuse logging without secrets, and
revocation/recovery UX. Do not assume in-memory throttling is sufficient for
production. In particular, reverse proxies can make remoteAddress the
same for every request.

Next: integrate the handler with the existing Oracle pairing store behind
an explicit feature flag only after these controls and integration tests
are implemented. Then introduce Android secure storage and a normal signed
release. Do not expose this route yet.
