import { createHash } from 'node:crypto';

// Firestore transactions atomically enforce quotas across all proxy workers.
// This limits requests, NOT actual TokenRouter charges (set a provider-side
// spending cap too). A quota reservation is never rolled back on API failure.
export class AiQuotaExceeded extends Error {
  constructor() {
    super('Quota exceeded');
    this.code = 'ai_quota_exceeded';
  }
}

function positiveInt(value, label, max = 1000000) {
  if (!Number.isSafeInteger(value) || value < 1 || value > max) {
    throw new Error('Invalid ' + label);
  }
  return value;
}

export function createFirestoreQuota({
  db,
  perMinute = 3,
  perDay = 10,
  globalDay = 300,
} = {}) {
  if (!db || typeof db.runTransaction !== 'function' ||
      typeof db.collection !== 'function') {
    throw new Error('Firestore is required for public usage');
  }
  positiveInt(perMinute, 'AI_LIMIT_PER_MINUTE');
  positiveInt(perDay, 'AI_LIMIT_PER_DAY');
  positiveInt(globalDay, 'AI_GLOBAL_LIMIT_PER_DAY');

  return async function reserveQuota({ uid, at }) {
    if (typeof uid !== 'string' || uid.length < 1 || uid.length > 256 ||
        typeof at !== 'number' || !Number.isFinite(at) || at < 0) {
      throw new Error('Invalid quota identity or timestamp');
    }
    const hash = createHash('sha256').update(uid).digest('hex');
    const minute = Math.floor(at / 60000);
    const day = Math.floor(at / 86400000);
    const collection = db.collection('masari_ai_usage');
    const refs = [
      collection.doc('u_' + hash + '_minute_' + minute),
      collection.doc('u_' + hash + '_day_' + day),
      collection.doc('global_day_' + day),
    ];
    const caps = [perMinute, perDay, globalDay];
    const expiry = new Date((day + 10) * 86400000);

    return db.runTransaction(async transaction => {
      // Read every counter before the first write, as required by Firestore.
      const snapshots = [];
      for (const ref of refs) snapshots.push(await transaction.get(ref));
      const counts = snapshots.map(snapshot => {
        const count = snapshot.exists ? snapshot.get('count') : 0;
        if (!Number.isSafeInteger(count) || count < 0) {
          throw new Error('Corrupt quota record');
        }
        return count;
      });
      if (counts.some((count, i) => count >= caps[i])) {
        throw new AiQuotaExceeded();
      }
      for (let i = 0; i < refs.length; i++) {
        transaction.set(refs[i], {
          count: counts[i] + 1,
          expiresAt: expiry,
        });
      }
      return true;
    }, { maxAttempts: 5 });
  };
}
