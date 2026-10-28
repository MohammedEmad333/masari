// Google-only account enrolment. Caller MUST verify the Firebase ID token
// with Firebase Admin and require firebase.sign_in_provider === 'google.com'.
// The immutable Firebase UID is the identity key; email is not an identity.
export const GOOGLE_ACCOUNT_SCHEMA = `
CREATE TABLE IF NOT EXISTS ai_google_accounts (
  firebase_uid text PRIMARY KEY CHECK (length(firebase_uid) BETWEEN 1 AND 128),
  account_id uuid NOT NULL UNIQUE REFERENCES ai_accounts(account_id),
  created_at timestamptz NOT NULL DEFAULT now()
);
`;

export function createGoogleAccounts({ pool, createAccount, issueSession } = {}) {
  if (!pool || typeof pool.connect !== 'function' ||
      typeof createAccount !== 'function' ||
      typeof issueSession !== 'function') {
    throw new TypeError('Google account dependencies required');
  }
  return async function exchangeVerifiedGoogleUser(user) {
    if (typeof user?.uid !== 'string' ||
        !/^[a-zA-Z0-9_-]{1,128}$/.test(user.uid) ||
        user.firebase?.sign_in_provider !== 'google.com') {
      throw new Error('Google sign-in required');
    }
    // Serialize first-time registration for the same Firebase UID.
    const client = await pool.connect();
    let accountId;
    try {
      await client.query('BEGIN');
      await client.query(
        'SELECT pg_advisory_xact_lock(hashtext($1), 712040)',
        [user.uid],
      );
      const found = await client.query(
        'SELECT account_id FROM ai_google_accounts WHERE firebase_uid = $1',
        [user.uid],
      );
      accountId = found.rows[0]?.account_id;
      if (!accountId) {
        const { randomUUID } = await import('node:crypto');
        accountId = randomUUID();
        await client.query('INSERT INTO ai_accounts(account_id) VALUES ($1)', [accountId]);
        await client.query(
          'INSERT INTO ai_google_accounts(firebase_uid, account_id) VALUES ($1, $2)',
          [user.uid, accountId],
        );
      }
      await client.query('COMMIT');
    } catch (error) {
      try { await client.query('ROLLBACK'); } catch {}
      throw error;
    } finally {
      client.release();
    }
    return issueSession(accountId, { ttlSeconds: 3600 });
  };
}
