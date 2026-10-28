import { createHash } from 'node:crypto';

// Shared PostgreSQL counter for future pairing redemption requests.
// This module is not wired to public HTTP until trusted client identity
// extraction and abuse protections are reviewed.
export const PAIRING_RATE_SCHEMA = `
CREATE TABLE IF NOT EXISTS ai_pairing_rate_limits (
  identity_hash char(64) NOT NULL,
  window_id bigint NOT NULL,
  attempts integer NOT NULL CHECK (attempts >= 0),
  expires_at timestamptz NOT NULL,
  PRIMARY KEY (identity_hash, window_id)
);
CREATE INDEX IF NOT EXISTS ai_pairing_rate_expiry_idx
  ON ai_pairing_rate_limits (expires_at);
`;

export class PairingRateExceeded extends Error {
  constructor() {
    super('Pairing attempt limit exceeded');
    this.code = 'pairing_rate_exceeded';
  }
}

export function createPairingRateLimiter({
  pool, maxAttempts = 5, windowSeconds = 60,
  now = () => Date.now(),
} = {}) {
  if (!pool || typeof pool.connect !== 'function') {
    throw new TypeError('PostgreSQL connection pool required');
  }
  if (!Number.isSafeInteger(maxAttempts) || maxAttempts < 1 || maxAttempts > 100 ||
      !Number.isSafeInteger(windowSeconds) || windowSeconds < 10 || windowSeconds > 3600) {
    throw new TypeError('Invalid rate limit configuration');
  }
  return async function reserveAttempt(identity) {
    if (typeof identity !== 'string' || identity.length < 1 || identity.length > 256) {
      throw new TypeError('Invalid pairing identity');
    }
    const time = now();
    if (!Number.isFinite(time) || time < 0) throw new TypeError('Invalid time');
    const hash = createHash('sha256').update(identity).digest('hex');
    const windowId = Math.floor(time / (windowSeconds * 1000));
    const expiry = new Date((windowId + 2) * windowSeconds * 1000);
    const client = await pool.connect();
    let begun = false;
    try {
      await client.query('BEGIN');
      begun = true;
      // One key lock across all Node workers avoids concurrent first-write races.
      await client.query('SELECT pg_advisory_xact_lock(hashtext($1), 1402)', [hash]);
      const result = await client.query(
        `INSERT INTO ai_pairing_rate_limits
           (identity_hash, window_id, attempts, expires_at)
         VALUES ($1, $2, 1, $3)
         ON CONFLICT (identity_hash, window_id)
         DO UPDATE SET attempts = ai_pairing_rate_limits.attempts + 1
         RETURNING attempts`,
        [hash, windowId, expiry],
      );
      const count = Number(result.rows[0]?.attempts);
      if (!Number.isSafeInteger(count) || count < 1) throw new Error('Corrupt rate counter');
      await client.query('COMMIT');
      begun = false;
      // Count denied attempts too: prohibit endless guesses.
      if (count > maxAttempts) throw new PairingRateExceeded();
      return count;
    } catch (error) {
      if (begun) {
        try { await client.query('ROLLBACK'); } catch { /* deny by default */ }
      }
      throw error;
    } finally {
      client.release();
    }
  };
}
