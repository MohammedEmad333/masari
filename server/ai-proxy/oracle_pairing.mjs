import { createHash, randomBytes } from 'node:crypto';

// This is an internal repository module, not a public HTTP endpoint.
// Pairing codes must be created in an authenticated SSH administrator action.
// No plaintext codes or access tokens are stored in PostgreSQL.
export const PAIRING_SCHEMA = `
CREATE TABLE IF NOT EXISTS ai_pairing_codes (
  code_hash char(64) PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES ai_accounts(account_id),
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ai_pairing_expiry_idx ON ai_pairing_codes (expires_at);
`;

const digest = value => createHash('sha256').update(value).digest('hex');
const codePattern = /^pair_[0-9a-f]{64}$/;

export function createOraclePairing({ pool, now = () => new Date() } = {}) {
  if (!pool || typeof pool.connect !== 'function') throw new TypeError('PostgreSQL pool required');

  async function generateCode(accountId, { ttlSeconds = 600 } = {}) {
    if (typeof accountId !== 'string' ||
        !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(accountId) ||
        !Number.isSafeInteger(ttlSeconds) || ttlSeconds < 60 || ttlSeconds > 900) {
      throw new TypeError('Invalid pairing parameters');
    }
    const code = 'pair_' + randomBytes(32).toString('hex');
    const expiresAt = new Date(now().getTime() + ttlSeconds * 1000);
    const result = await pool.connect();
    try {
      const inserted = await result.query(
        `INSERT INTO ai_pairing_codes (code_hash, account_id, expires_at)
         SELECT $1, account_id, $3 FROM ai_accounts
         WHERE account_id = $2 AND disabled_at IS NULL
         RETURNING code_hash`,
        [digest(code), accountId, expiresAt],
      );
      if (inserted.rowCount !== 1) throw new Error('Account unavailable');
    } finally { result.release(); }
    return { code, expiresAt: expiresAt.toISOString() };
  }

  async function redeemCode(code, { sessionTtlSeconds = 3600 } = {}) {
    if (typeof code !== 'string' || !codePattern.test(code) ||
        !Number.isSafeInteger(sessionTtlSeconds) ||
        sessionTtlSeconds < 60 || sessionTtlSeconds > 86400) return null;
    const client = await pool.connect();
    let started = false;
    try {
      await client.query('BEGIN');
      started = true;
      // One serializable consumption point: competing devices cannot reuse a code.
      const selected = await client.query(
        `SELECT p.account_id FROM ai_pairing_codes p
         JOIN ai_accounts a USING (account_id)
         WHERE p.code_hash = $1 AND p.consumed_at IS NULL
           AND p.expires_at > $2 AND a.disabled_at IS NULL
         FOR UPDATE OF p`,
        [digest(code), now()],
      );
      const accountId = selected.rows[0]?.account_id;
      if (!accountId) {
        await client.query('ROLLBACK');
        started = false;
        return null;
      }
      const token = 'msr_' + randomBytes(32).toString('hex');
      const expiresAt = new Date(now().getTime() + sessionTtlSeconds * 1000);
      await client.query(
        'INSERT INTO ai_sessions (token_hash, account_id, expires_at) VALUES ($1, $2, $3)',
        [digest(token), accountId, expiresAt],
      );
      await client.query(
        'UPDATE ai_pairing_codes SET consumed_at = $2 WHERE code_hash = $1',
        [digest(code), now()],
      );
      await client.query('COMMIT');
      started = false;
      return { token, accountId, expiresAt: expiresAt.toISOString() };
    } catch (error) {
      if (started) {
        try { await client.query('ROLLBACK'); } catch { /* fail closed */ }
      }
      throw error;
    } finally { client.release(); }
  }
  return { generateCode, redeemCode };
}
