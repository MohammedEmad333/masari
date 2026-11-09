// Account-owned Oracle/PostgreSQL data; never accept an account ID from a request body.
export const ACCOUNT_DATA_SCHEMA = `
CREATE TABLE IF NOT EXISTS masari_account_profiles (
  account_id uuid PRIMARY KEY REFERENCES ai_accounts(account_id),
  display_name text CHECK (display_name IS NULL OR char_length(display_name) BETWEEN 1 AND 80),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS masari_account_documents (
  account_id uuid NOT NULL REFERENCES ai_accounts(account_id),
  document_kind text NOT NULL CHECK (document_kind IN ('personal', 'calendar')),
  document_json jsonb NOT NULL,
  revision bigint NOT NULL DEFAULT 1 CHECK (revision >= 1),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, document_kind)
);
ALTER TABLE masari_account_documents
  ADD COLUMN IF NOT EXISTS revision bigint NOT NULL DEFAULT 1;
`;

const validAccount = id => typeof id === 'string' &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id);
const validKind = kind => kind === 'personal' || kind === 'calendar';

export class BackupConflictError extends Error {
  constructor() {
    super('Backup was updated by another device');
    this.code = 'backup_conflict';
  }
}

export function createOracleAccountStore({ pool } = {}) {
  if (!pool || typeof pool.query !== 'function' || typeof pool.connect !== 'function') {
    throw new TypeError('PostgreSQL pool required');
  }
  function ensureAccount(id) {
    if (!validAccount(id)) throw new TypeError('Invalid account');
  }
  function ensureKind(kind) {
    if (!validKind(kind)) throw new TypeError('Invalid document kind');
  }
  async function getProfile(accountId) {
    ensureAccount(accountId);
    const found = await pool.query(
      'SELECT display_name FROM masari_account_profiles WHERE account_id=$1',
      [accountId],
    );
    return { accountId, displayName: found.rows[0]?.display_name ?? null };
  }
  async function updateProfile(accountId, displayName) {
    ensureAccount(accountId);
    if (typeof displayName !== 'string' || displayName.trim().length < 1 ||
        [...displayName.trim()].length > 80) throw new TypeError('Invalid display name');
    const result = await pool.query(
      `INSERT INTO masari_account_profiles(account_id, display_name)
       VALUES ($1, $2) ON CONFLICT (account_id)
       DO UPDATE SET display_name=EXCLUDED.display_name, updated_at=now()
       RETURNING display_name`,
      [accountId, displayName.trim()],
    );
    return { accountId, displayName: result.rows[0].display_name };
  }
  async function getDocumentWithRevision(accountId, kind) {
    ensureAccount(accountId);
    ensureKind(kind);
    const result = await pool.query(
      'SELECT document_json, revision FROM masari_account_documents WHERE account_id=$1 AND document_kind=$2',
      [accountId, kind],
    );
    const row = result.rows[0];
    if (!row) return null;
    const revision = Number(row.revision);
    if (!Number.isSafeInteger(revision) || revision < 1) {
      throw new Error('Invalid document revision');
    }
    return { data: row.document_json, revision };
  }
  async function getDocument(accountId, kind) {
    const found = await getDocumentWithRevision(accountId, kind);
    return found?.data ?? null;
  }
  async function putDocument(accountId, kind, payload, expectedRevision = null) {
    ensureAccount(accountId);
    ensureKind(kind);
    if (expectedRevision !== null &&
        (!Number.isSafeInteger(expectedRevision) || expectedRevision < 0)) {
      throw new TypeError('Invalid expected revision');
    }
    const json = JSON.stringify(payload);
    let result;
    if (expectedRevision === 0) {
      // First writer wins. A racing second insert must fail rather than overwrite.
      result = await pool.query(
        `INSERT INTO masari_account_documents
           (account_id,document_kind,document_json,revision)
         VALUES ($1,$2,$3::jsonb,1)
         ON CONFLICT (account_id,document_kind) DO NOTHING
         RETURNING revision`,
        [accountId, kind, json],
      );
    } else if (expectedRevision !== null) {
      // Atomic compare-and-swap; stale device snapshots cannot overwrite new data.
      result = await pool.query(
        `UPDATE masari_account_documents
         SET document_json=$3::jsonb, revision=revision+1, updated_at=now()
         WHERE account_id=$1 AND document_kind=$2 AND revision=$4
         RETURNING revision`,
        [accountId, kind, json, expectedRevision],
      );
    } else {
      // Explicit manual backup retains replace semantics.
      result = await pool.query(
        `INSERT INTO masari_account_documents
           (account_id,document_kind,document_json,revision)
         VALUES ($1,$2,$3::jsonb,1)
         ON CONFLICT (account_id,document_kind)
         DO UPDATE SET document_json=EXCLUDED.document_json,
           revision=masari_account_documents.revision+1, updated_at=now()
         RETURNING revision`,
        [accountId, kind, json],
      );
    }
    if (result.rowCount !== 1) throw new BackupConflictError();
    return Number(result.rows[0].revision);
  }
  async function deleteDocument(accountId, kind) {
    ensureAccount(accountId);
    ensureKind(kind);
    await pool.query(
      'DELETE FROM masari_account_documents WHERE account_id=$1 AND document_kind=$2',
      [accountId, kind],
    );
  }
  async function deleteAccount(accountId) {
    ensureAccount(accountId);
    const client = await pool.connect();
    let begun = false;
    try {
      await client.query('BEGIN');
      begun = true;
      const locked = await client.query(
        'SELECT account_id FROM ai_accounts WHERE account_id=$1 AND disabled_at IS NULL FOR UPDATE',
        [accountId],
      );
      if (locked.rowCount !== 1) throw new Error('Account unavailable');
      // Keep a non-identifying disabled UUID record to prevent FK races.
      await client.query('UPDATE ai_accounts SET disabled_at=now() WHERE account_id=$1', [accountId]);
      await client.query('DELETE FROM masari_account_documents WHERE account_id=$1', [accountId]);
      await client.query('DELETE FROM masari_account_profiles WHERE account_id=$1', [accountId]);
      await client.query('DELETE FROM ai_sessions WHERE account_id=$1', [accountId]);
      await client.query('DELETE FROM ai_pairing_codes WHERE account_id=$1', [accountId]);
      await client.query('DELETE FROM ai_google_oidc_accounts WHERE account_id=$1', [accountId]);
      await client.query('DELETE FROM ai_google_accounts WHERE account_id=$1', [accountId]);
      await client.query('COMMIT');
      begun = false;
    } catch (error) {
      if (begun) {
        try { await client.query('ROLLBACK'); } catch {}
      }
      throw error;
    } finally {
      client.release();
    }
  }
  return { getProfile, updateProfile, getDocument, getDocumentWithRevision, putDocument, deleteDocument, deleteAccount };
}
