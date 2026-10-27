import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createPostgresQuota, QUOTA_SCHEMA } from '../postgres_quota.mjs';

function mockPool() {
  const rows = new Map();
  const events = [];
  return {
    rows,
    events,
    async connect() {
      let writes;
      return {
        async query(sql, args = []) {
          events.push(sql.trim().split(/\\s+/)[0]);
          if (sql === 'BEGIN') { writes = new Map(rows); return {}; }
          if (sql === 'COMMIT') { rows.clear(); for (const [k,v] of writes) rows.set(k,v); return {}; }
          if (sql === 'ROLLBACK') { writes = null; return {}; }
          if (sql.startsWith('SELECT pg_advisory')) return { rows: [] };
          if (sql.startsWith('SELECT counter_key')) return {
            rows: args[0].filter(k => writes.has(k)).map(k => ({ counter_key: k, count: writes.get(k) })),
          };
          if (sql.startsWith('INSERT INTO')) {
            const k = args[0];
            writes.set(k, (writes.get(k) || 0) + 1);
            return {};
          }
          throw new Error('unexpected SQL: ' + sql);
        },
        release() { events.push('release'); },
      };
    },
  };
}

test('schema persists quota counters in dedicated PostgreSQL table', () => {
  assert.match(QUOTA_SCHEMA, /PRIMARY KEY/);
  assert.match(QUOTA_SCHEMA, /expires_at/);
});

test('minute, day and global reservations are atomic and durable', async () => {
  const pool = mockPool();
  const reserve = createPostgresQuota({ pool, perMinute: 2, perDay: 3, globalDay: 4 });
  const t = Date.UTC(2030, 0, 1);
  await reserve({ uid: 'a', at: t });
  await reserve({ uid: 'a', at: t });
  await assert.rejects(reserve({ uid: 'a', at: t }), e => e.code === 'ai_quota_exceeded');
  await reserve({ uid: 'a', at: t + 60000 });
  await reserve({ uid: 'b', at: t });
  await assert.rejects(reserve({ uid: 'b', at: t }), e => e.code === 'ai_quota_exceeded');
  assert.equal(pool.events.filter(e => e === 'COMMIT').length, 4);
  assert.equal(pool.events.filter(e => e === 'ROLLBACK').length, 2);
  await reserve({ uid: 'a', at: t + 86400000 });
});

test('denies malformed identities and missing database', async () => {
  assert.throws(() => createPostgresQuota({ pool: null }));
  assert.throws(() => createPostgresQuota({ pool: mockPool(), perDay: 0 }));
  const reserve = createPostgresQuota({ pool: mockPool() });
  await assert.rejects(reserve({ uid: '', at: Date.now() }));
});
