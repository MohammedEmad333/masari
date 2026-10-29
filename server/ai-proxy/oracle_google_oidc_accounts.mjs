import { randomUUID } from 'node:crypto';

export const GOOGLE_OIDC_ACCOUNT_SCHEMA = `
CREATE TABLE IF NOT EXISTS ai_google_oidc_accounts (
  google_sub text PRIMARY KEY CHECK (google_sub ~ '^[0-9]{1,128}$'),
  account_id uuid NOT NULL UNIQUE REFERENCES ai_accounts(account_id),
  created_at timestamptz NOT NULL DEFAULT now()
);
`;

export function createGoogleOidcAccounts({ pool, issueSession } = {}) {
  if (!pool || typeof pool.connect !== 'function' || typeof issueSession !== 'function') {
    throw new TypeError('OIDC account dependencies required');
  }
  return async function exchangeGoogleSubject(sub) {
    if (typeof sub !== 'string' || !/^[0-9]{1,128}$/.test(sub)) throw new Error('invalid_google_subject');
    const client = await pool.connect();
    let accountId;
    try {
      await client.query('BEGIN');
      await client.query('SELECT pg_advisory_xact_lock(hashtext($1), 712041)', [sub]);
      const found = await client.query('SELECT account_id FROM ai_google_oidc_accounts WHERE google_sub=$1', [sub]);
      accountId = found.rows[0]?.account_id;
      if (!accountId) {
        accountId = randomUUID();
        await client.query('INSERT INTO ai_accounts(account_id) VALUES ($1)', [accountId]);
        await client.query('INSERT INTO ai_google_oidc_accounts(google_sub,account_id) VALUES ($1,$2)', [sub, accountId]);
      }
      await client.query('COMMIT');
    } catch (error) {
      try { await client.query('ROLLBACK'); } catch {}
      throw error;
    } finally { client.release(); }
    return issueSession(accountId, { ttlSeconds: 3600 });
  };
}
