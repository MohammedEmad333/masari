import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createOraclePairing, PAIRING_SCHEMA } from '../oracle_pairing.mjs';

const id = 'b60cfadd-a659-48d3-a238-8b8ccf796632';
const date = new Date('2026-10-28T12:00:00Z');
function fixture({ found = true, failInsert = false } = {}) {
  const calls = [];
  const client = {
    async query(sql, params = []) {
      calls.push({ sql, params });
      if (sql.includes('INSERT INTO ai_pairing_codes')) return { rowCount: 1 };
      if (sql.includes('SELECT p.account_id')) return { rows: found ? [{ account_id: id }] : [] };
      if (sql.includes('INSERT INTO ai_sessions') && failInsert) throw Error('database failure');
      return { rowCount: 1, rows: [] };
    },
    release() { calls.push({ sql: 'RELEASE' }); },
  };
  return { calls, pool: { connect: async () => client } };
}
test('pairing stores only a hashed code and has expiry/consumption constraints', () => {
  assert.match(PAIRING_SCHEMA, /code_hash char\(64\) PRIMARY KEY/);
  assert.match(PAIRING_SCHEMA, /consumed_at/);
});
test('creates a one-time high entropy code, stored only as a digest', async () => {
  const fx = fixture();
  const store = createOraclePairing({ pool: fx.pool, now: () => date });
  const result = await store.generateCode(id);
  assert.match(result.code, /^pair_[0-9a-f]{64}$/);
  assert.equal(result.expiresAt, '2026-10-28T12:10:00.000Z');
  const call = fx.calls.find(x => x.sql.includes('INSERT INTO ai_pairing_codes'));
  assert.equal(call.params[0].length, 64);
  assert(!call.params.includes(result.code));
});
test('consumes a pairing code and issues hashed session within the same transaction', async () => {
  const fx = fixture();
  const store = createOraclePairing({ pool: fx.pool, now: () => date });
  const { code } = await store.generateCode(id);
  const session = await store.redeemCode(code);
  assert.match(session.token, /^msr_[0-9a-f]{64}$/);
  assert.equal(session.accountId, id);
  const selected = fx.calls.find(x => x.sql.includes('SELECT p.account_id'));
  assert.match(selected.sql, /FOR UPDATE OF p/);
  assert.match(selected.sql, /consumed_at IS NULL/);
  assert.match(selected.sql, /expires_at > \$2/);
  const insert = fx.calls.find(x => x.sql.includes('INSERT INTO ai_sessions'));
  assert.equal(insert.params[0].length, 64);
  assert(!insert.params.includes(session.token));
  const sql = fx.calls.map(x => x.sql);
  assert(sql.indexOf('BEGIN') < sql.indexOf('COMMIT'));
  assert(sql.indexOf('UPDATE ai_pairing_codes SET consumed_at = $2 WHERE code_hash = $1') < sql.indexOf('COMMIT'));
});
test('rejects reused, expired or nonexistent codes without granting a session', async () => {
  const fx = fixture({ found: false });
  const store = createOraclePairing({ pool: fx.pool, now: () => date });
  const result = await store.redeemCode('pair_' + 'a'.repeat(64));
  assert.equal(result, null);
  assert.equal(fx.calls.some(x => x.sql.includes('INSERT INTO ai_sessions')), false);
  assert(fx.calls.some(x => x.sql === 'ROLLBACK'));
  assert.equal(await store.redeemCode('invalid'), null);
});
test('rolls back failed session issuance, so the pairing code remains available', async () => {
  const fx = fixture({ failInsert: true });
  const store = createOraclePairing({ pool: fx.pool, now: () => date });
  await assert.rejects(store.redeemCode('pair_' + 'a'.repeat(64)), /database failure/);
  assert(fx.calls.some(x => x.sql === 'ROLLBACK'));
  assert(!fx.calls.some(x => x.sql === 'COMMIT'));
});
