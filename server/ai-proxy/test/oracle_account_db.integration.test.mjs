import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
// Database driver is intentionally loaded only in the dedicated PG CI job.
import { randomUUID } from 'node:crypto';
import { createOracleSessions, SESSION_SCHEMA } from '../oracle_sessions.mjs';
import { PAIRING_SCHEMA } from '../oracle_pairing.mjs';
import { GOOGLE_ACCOUNT_SCHEMA } from '../oracle_google_accounts.mjs';
import { GOOGLE_OIDC_ACCOUNT_SCHEMA } from '../oracle_google_oidc_accounts.mjs';
import {
  ACCOUNT_DATA_SCHEMA, BackupConflictError, createOracleAccountStore,
} from '../oracle_account_store.mjs';

const databaseUrl = process.env.MASARI_TEST_PG_URL;
if (!databaseUrl) {
  test('PostgreSQL integration suite requires MASARI_TEST_PG_URL', { skip: true }, () => {});
} else {
  const { default: pg } = await import('pg');
  let pool;
  let sessions;
  let store;
  let alice;
  let bob;

  before(async () => {
    pool = new pg.Pool({ connectionString: databaseUrl, max: 3 });
    await pool.query(SESSION_SCHEMA);
    await pool.query(PAIRING_SCHEMA);
    await pool.query(GOOGLE_ACCOUNT_SCHEMA);
    await pool.query(GOOGLE_OIDC_ACCOUNT_SCHEMA);
    await pool.query(ACCOUNT_DATA_SCHEMA);
    sessions = createOracleSessions({ pool });
    store = createOracleAccountStore({ pool });
    alice = await sessions.createAccount();
    bob = await sessions.createAccount();
  });

  after(async () => {
    if (pool) await pool.end();
  });

  test('real PostgreSQL isolates account documents and profiles', async () => {
    await store.updateProfile(alice, 'Alice');
    await store.updateProfile(bob, 'Bob');
    assert.equal((await store.getProfile(alice)).displayName, 'Alice');
    assert.equal((await store.getProfile(bob)).displayName, 'Bob');
    assert.equal(await store.getDocument(bob, 'personal'), null);
  });

  test('first writer and optimistic compare-and-swap prevent lost updates', async () => {
    const initial = { schema: 1, manualTasks: [], plans: [] };
    const revision = await store.putDocument(alice, 'personal', initial, 0);
    assert.equal(revision, 1);
    await assert.rejects(
      store.putDocument(alice, 'personal', initial, 0), BackupConflictError,
    );
    const race = await Promise.allSettled([
      store.putDocument(alice, 'personal', { ...initial, manualTasks: [{ uid: 'a' }] }, 1),
      store.putDocument(alice, 'personal', { ...initial, manualTasks: [{ uid: 'b' }] }, 1),
    ]);
    assert.equal(race.filter(item => item.status === 'fulfilled').length, 1);
    assert.equal(race.filter(item => item.status === 'rejected').length, 1);
    assert.equal(race.find(item => item.status === 'fulfilled').value, 2);
    assert.equal((await store.getDocumentWithRevision(alice, 'personal')).revision, 2);
    assert.equal(await store.getDocument(bob, 'personal'), null);
  });

  test('real sessions revoke and account deletion removes linked records', async () => {
    const issued = await sessions.issueSession(alice);
    assert.deepEqual(await sessions.authenticate(issued.token), { uid: alice });
    await store.putDocument(alice, 'calendar', {
      version: 1, salt: 'YWJj', nonce: 'YWJj', ciphertext: 'YWJj', mac: 'YWJj',
    });
    await store.putDocument(bob, 'calendar', {
      version: 1, salt: 'YWJj', nonce: 'YWJj', ciphertext: 'YWJj', mac: 'YWJj',
    });
    await store.deleteAccount(alice);
    assert.equal(await sessions.authenticate(issued.token), null);
    assert.equal(await store.getDocument(alice, 'calendar'), null);
    assert.notEqual(await store.getDocument(bob, 'calendar'), null);
    await assert.rejects(sessions.issueSession(alice), /Account unavailable/);
    const session = await sessions.issueSession(bob);
    assert.deepEqual(await sessions.authenticate(session.token), { uid: bob });
  });

  test('revoking a session prevents reuse while preserving the account', async () => {
    const session = await sessions.issueSession(bob);
    assert.deepEqual(await sessions.authenticate(session.token), { uid: bob });
    assert.equal(await sessions.revoke(session.token), true);
    assert.equal(await sessions.authenticate(session.token), null);
  });
}
