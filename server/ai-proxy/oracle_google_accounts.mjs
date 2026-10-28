import { randomUUID } from 'node:crypto';

// A Google identity is bound to a stable Oracle account. Never use emails as
// account keys: they can change, and client-provided addresses are untrusted.
export const GOOGLE_IDENTITY_SCHEMA = `
CREATE TABLE IF NOT EXISTS ai_google_identities (
  firebase_uid text PRIMARY KEY,
  account_id uuid NOT NULL UNIQUE REFERENCES ai_accounts(account_id),
  created_at timestamptz NOT NULL DEFAULT now()
);
`;

export function createGoogleAccounts({ pool } = {}) {
  if (!pool || typeof pool.connect !== 'function') {
    throw new TypeError('PostgreSQL pool required');
  }
  return async function findOrCreate(firebaseUid) {
    if (typeof firebaseUid !== 'string' || !firebaseUid ||
        firebaseUid.length > 128 || /[^a-zA-Z0-9:_-]/.test(firebaseUid)) {
      throw new TypeError('Invalid verified Firebase UID');
    }
    const client = await pool.connect();
    let inTransaction = false;
    try {
      await client.query('BEGIN');
      inTransaction = true;
      await client.query('SELECT pg_advisory_xact_lock(hashtext($1), 1403)', [firebaseUid]);
      const existing = await client.query(
        `SELECT a.account_id, a.disabled_at FROM ai_google_identities g
         JOIN ai_accounts a USING (account_id) WHERE g.firebase_uid = $1`,
        [firebaseUid],
      );
      let accountId;
      if (existing.rows.length) {
        if (existing.rows[0].disabled_at !== null) {
          throw new Error('Account unavailable');
        }
        accountId = existing.rows[0].account_id;
      } else {
        accountId = randomUUID();
        await client.query('INSERT INTO ai_accounts (account_id) VALUES ($1)', [accountId]);
        await client.query(
          'INSERT INTO ai_google_identities (firebase_uid, account_id) VALUES ($1, $2)',
          [firebaseUid, accountId],
        );
      }
      await client.query('COMMIT');
      inTransaction = false;
      return accountId;
    } catch (error) {
      if (inTransaction) {
        try { await client.query('ROLLBACK'); } catch { /* fail closed */ }
      }
      throw error;
    } finally {
      client.release();
    }
  };
}
