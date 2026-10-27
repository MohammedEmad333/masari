import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createFirestoreQuota, AiQuotaExceeded } from '../firestore_quota.mjs';

function fakeFirestore() {
  const records = new Map();
  return {
    collection(name) {
      assert.equal(name, 'masari_ai_usage');
      return { doc: id => ({ id }) };
    },
    async runTransaction(work) {
      const writes = new Map();
      const tx = {
        async get(ref) {
          const value = records.get(ref.id);
          return {
            exists: value !== undefined,
            get: key => value?.[key],
          };
        },
        set(ref, value) { writes.set(ref.id, value); },
      };
      const outcome = await work(tx);
      for (const [id, value] of writes) records.set(id, value);
      return outcome;
    },
    records,
  };
}

test('all authenticated users have independent minute and daily quotas', async () => {
  const db = fakeFirestore();
  const reserve = createFirestoreQuota({
    db, perMinute: 2, perDay: 3, globalDay: 10,
  });
  const at = Date.UTC(2030, 0, 1, 12, 0, 0);
  await reserve({ uid: 'a', at });
  await reserve({ uid: 'a', at });
  await assert.rejects(reserve({ uid: 'a', at }), AiQuotaExceeded);
  await reserve({ uid: 'b', at });
  await reserve({ uid: 'a', at: at + 60000 });
  await assert.rejects(reserve({ uid: 'a', at: at + 120000 }), AiQuotaExceeded);
});

test('global limit applies across accounts and new process instances', async () => {
  const db = fakeFirestore();
  const first = createFirestoreQuota({ db, perMinute: 10, perDay: 10, globalDay: 2 });
  const second = createFirestoreQuota({ db, perMinute: 10, perDay: 10, globalDay: 2 });
  const at = Date.UTC(2030, 0, 1);
  await first({ uid: 'a', at });
  await second({ uid: 'b', at });
  await assert.rejects(first({ uid: 'c', at }), AiQuotaExceeded);
  await first({ uid: 'a', at: at + 86400000 });
  assert.equal(db.records.size > 0, true);
  assert.equal([...db.records.values()].every(v => v.expiresAt instanceof Date), true);
});

test('fails closed on corrupt counter or broken database', async () => {
  const db = fakeFirestore();
  const reserve = createFirestoreQuota({ db });
  const at = Date.UTC(2030, 0, 1);
  await reserve({ uid: 'a', at });
  const item = [...db.records.entries()].find(([id]) => id.startsWith('global_day_'));
  db.records.set(item[0], { count: -1 });
  await assert.rejects(reserve({ uid: 'b', at }), /Corrupt quota record/);
  const broken = createFirestoreQuota({
    db: {
      collection: db.collection,
      runTransaction: async () => { throw new Error('transaction_failed'); },
    },
  });
  await assert.rejects(broken({ uid: 'b', at }), /transaction_failed/);
});

test('rejects invalid quotas and identities before database access', async () => {
  const db = fakeFirestore();
  assert.throws(() => createFirestoreQuota({ db, perDay: 0 }));
  assert.throws(() => createFirestoreQuota({ db: null }));
  const reserve = createFirestoreQuota({ db });
  await assert.rejects(reserve({ uid: '', at: Date.now() }));
});
