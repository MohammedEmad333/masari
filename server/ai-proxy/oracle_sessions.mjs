import { createHash, randomBytes, randomUUID } from 'node:crypto';

// Oracle-backed session storage. No bearer token or raw pairing secret is persisted.
// This module is deliberately not wired into HTTP routes until safe enrolment and
// abuse controls ship together; existing Firebase authentication stays intact.
export const SESSION_SCHEMA = `
CREATE TABLE IF NOT EXISTS ai_accounts (
  account_id uuid PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now(),
  disabled_at timestamptz
);
CREATE TABLE IF NOT EXISTS ai_sessions (
  token_hash char(64) PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES ai_accounts(account_id),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ai_sessions_account_idx
  ON ai_sessions (account_id);
CREATE INDEX IF NOT EXISTS ai_sessions_expiry_idx
  ON ai_sessions (expires_at);
`;

const digest = token => createHash('sha256').update(token).digest('hex');
const tokenPattern = /^msr_[0-9a-f]{64}$/;

export function createOracleSessions({ pool, now = () => new Date() } = {}) {
  if (!pool || typeof pool.query !== 'function') {
    throw new TypeError('PostgreSQL pool required');
  }
  async function createAccount() {
    const accountId = randomUUID();
    await pool.query('INSERT INTO ai_accounts (account_id) VALUES ($1)', [accountId]);
    return accountId;
  }
  async function issueSession(accountId, { ttlSeconds = 3600 } = {}) {
    if (typeof accountId !== 'string' ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(accountId) ||
        !Number.isSafeInteger(ttlSeconds) || ttlSeconds < 60 || ttlSeconds > 86400) {
      throw new TypeError('Invalid session parameters');
    }
    const token = 'msr_' + randomBytes(32).toString('hex');
    const expiry = new Date(now().getTime() + ttlSeconds * 1000);
    const result = await pool.query(
      `INSERT INTO ai_sessions (token_hash, account_id, expires_at)
       SELECT $1, account_id, $3 FROM ai_accounts
       WHERE account_id = $2 AND disabled_at IS NULL
       RETURNING account_id`,
      [digest(token), accountId, expiry],
    );
    if (result.rowCount !== 1) throw new Error('Account unavailable');
    return { token, expiresAt: expiry.toISOString() };
  }
  async function authenticate(token) {
    if (typeof token !== 'string' || !tokenPattern.test(token)) return null;
    const result = await pool.query(
      `SELECT s.account_id FROM ai_sessions s
       JOIN ai_accounts a USING (account_id)
       WHERE s.token_hash = $1 AND s.revoked_at IS NULL
         AND s.expires_at > $2 AND a.disabled_at IS NULL`,
      [digest(token), now()],
    );
    const accountId = result.rows[0]?.account_id;
    return typeof accountId === 'string' ? { uid: accountId } : null;
  }
  async function revoke(token) {
    if (typeof token !== 'string' || !tokenPattern.test(token)) return false;
    const result = await pool.query(
      'UPDATE ai_sessions SET revoked_at = $2 WHERE token_hash = $1 AND revoked_at IS NULL',
      [digest(token), now()],
    );
    return result.rowCount > 0;
  }
  async function revokeAll(accountId) {
    if (typeof accountId !== 'string' ||
        !/^[0-9a-f-]{36}$/i.test(accountId)) throw new TypeError('Invalid account');
    const result = await pool.query(
      'UPDATE ai_sessions SET revoked_at = $2 WHERE account_id = $1 AND revoked_at IS NULL',
      [accountId, now()],
    );
    return result.rowCount;
  }
  return { createAccount, issueSession, authenticate, revoke, revokeAll };
}
