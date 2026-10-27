import { createHash } from 'node:crypto';
import { AiQuotaExceeded } from './firestore_quota.mjs';

// Oracle-local durable quota backend. No Firebase or Firestore interaction.
// A dedicated PostgreSQL role/database must be provisioned for Masari.
// All counters are reserved inside one transaction and one advisory lock,
// serializing writers across API processes for a consistent global cap.
export const QUOTA_SCHEMA = `
CREATE TABLE IF NOT EXISTS ai_usage_counters (
  counter_key text PRIMARY KEY,
  count integer NOT NULL CHECK (count >= 0),
  expires_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ai_usage_counters_expiry_idx
  ON ai_usage_counters (expires_at);
`;

function validLimit(value) {
  if (!Number.isSafeInteger(value) || value < 1 || value > 1000000) {
    throw new Error('Invalid quota limit');
  }
}

export function createPostgresQuota({
  pool, perMinute = 3, perDay = 10, globalDay = 300,
} = {}) {
  if (!pool || typeof pool.connect !== 'function') {
    throw new Error('PostgreSQL pool required');
  }
  for (const limit of [perMinute, perDay, globalDay]) validLimit(limit);

  return async function reserveQuota({ uid, at }) {
    if (typeof uid !== 'string' || !uid || uid.length > 256 ||
        !Number.isFinite(at) || at < 0) {
      throw new Error('Invalid quota identity');
    }
    const digest = createHash('sha256').update(uid).digest('hex');
    const minute = Math.floor(at / 60000);
    const day = Math.floor(at / 86400000);
    const keys = [
      `u_${digest}_minute_${minute}`,
      `u_${digest}_day_${day}`,
      `global_day_${day}`,
    ];
    const caps = [perMinute, perDay, globalDay];
    const expiresAt = new Date((day + 10) * 86400000);
    const client = await pool.connect();
    let begun = false;
    try {
      await client.query('BEGIN');
      begun = true;
      // Fixed namespace advisory lock keeps all cap checks and increments
      // atomic across concurrent connections and Node.js instances.
      await client.query('SELECT pg_advisory_xact_lock(712039, 99)');
      const result = await client.query(
        'SELECT counter_key, count FROM ai_usage_counters WHERE counter_key = ANY($1::text[])',
        [keys],
      );
      const counts = new Map(result.rows.map(row => [row.counter_key, Number(row.count)]));
      if (keys.some((key, i) => {
        const current = counts.get(key) ?? 0;
        if (!Number.isSafeInteger(current) || current < 0) {
          throw new Error('Corrupt quota record');
        }
        return current >= caps[i];
      })) {
        throw new AiQuotaExceeded();
      }
      for (const key of keys) {
        await client.query(
          `INSERT INTO ai_usage_counters (counter_key, count, expires_at)
           VALUES ($1, 1, $2)
           ON CONFLICT (counter_key)
           DO UPDATE SET count = ai_usage_counters.count + 1,
                         expires_at = EXCLUDED.expires_at`,
          [key, expiresAt],
        );
      }
      await client.query('COMMIT');
      begun = false;
      return true;
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
