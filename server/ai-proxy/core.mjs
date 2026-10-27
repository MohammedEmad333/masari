// The private pilot is deliberately fail-closed when no UIDs are configured.
export function createAllowedUserValidator(raw) {
  if (typeof raw !== 'string' || !raw.trim() || raw.length > 4096) {
    throw new Error('AI_ALLOWED_UIDS must name a trusted Firebase user');
  }
  const values = raw.split(',').map(uid => uid.trim());
  if (values.some(uid => !/^[A-Za-z0-9:_-]{1,128}$/.test(uid))) {
    throw new Error('Invalid Firebase UID allowlist');
  }
  const allowed = new Set(values);
  return user => {
    if (typeof user?.uid !== 'string' || !allowed.has(user.uid)) {
      throw new Error('Unauthorized pilot user');
    }
    return user;
  };
}

// Pure HTTP boundary; Firebase validation and TokenRouter transport are injected.
// No prompts, auth tokens or upstream responses are logged or persisted.
export function createRequestHandler({
  authenticate,
  complete,
  now = () => Date.now(),
  maxParallel = 4,
  maxPerMinute = 5,
  maxPerDay = 30,
} = {}) {
  if (typeof authenticate !== 'function' || typeof complete !== 'function') {
    throw new TypeError('authenticate and complete are required');
  }

  const limits = new Map();
  let active = 0;

  function reply(res, status, body) {
    res.writeHead(status, {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    });
    res.end(JSON.stringify(body));
  }

  return async function handle(req, res) {
    if (req.method === 'GET' && req.url === '/health') {
      return reply(res, 200, { status: 'ok' });
    }
    if (req.url !== '/v1/assistant/ask') {
      return reply(res, 404, { error: 'not_found' });
    }
    if (req.method !== 'POST') {
      return reply(res, 405, { error: 'method_not_allowed' });
    }
    if (!/^application\/json(?:\s*;|$)/i.test(req.headers['content-type'] || '')) {
      return reply(res, 415, { error: 'content_type' });
    }
    const authorization = req.headers.authorization || '';
    if (!authorization.startsWith('Bearer ') || authorization.length > 4103) {
      return reply(res, 401, { error: 'sign_in_required' });
    }

    let user;
    try {
      user = await authenticate(authorization.slice(7));
    } catch {
      return reply(res, 401, { error: 'invalid_authentication' });
    }
    if (typeof user?.uid !== 'string' || !user.uid) {
      return reply(res, 401, { error: 'invalid_authentication' });
    }

    const declaredLength = Number(req.headers['content-length'] || 0);
    if (declaredLength > 4096) {
      return reply(res, 413, { error: 'request_too_large' });
    }
    let bytes = 0;
    const parts = [];
    try {
      for await (const chunk of req) {
        bytes += chunk.length;
        if (bytes > 4096) {
          return reply(res, 413, { error: 'request_too_large' });
        }
        parts.push(chunk);
      }
    } catch {
      if (!res.writableEnded) reply(res, 400, { error: 'invalid_body' });
      return;
    }

    let payload;
    try {
      payload = JSON.parse(Buffer.concat(parts).toString('utf8'));
    } catch {
      return reply(res, 400, { error: 'invalid_json' });
    }
    if (
      payload === null || typeof payload !== 'object' ||
      Array.isArray(payload) ||
      Object.keys(payload).some(key => !['message', 'language', 'consent'].includes(key)) ||
      payload.consent !== true ||
      !['ar', 'en'].includes(payload.language) ||
      typeof payload.message !== 'string'
    ) {
      return reply(res, 400, { error: 'invalid_request' });
    }
    const message = payload.message.trim();
    if (!message || [...message].length > 500) {
      return reply(res, 400, { error: 'invalid_message_length' });
    }

    // Reject obvious credential-bearing strings. This is defense in depth,
    // not a guarantee that arbitrary prose contains no private information.
    if (/authtoken|export_execute\.php|https?:\/\/|bearer\s|password\s*[:=]|AIza[0-9A-Za-z_-]{10,}/i.test(message)) {
      return reply(res, 400, { error: 'sensitive_content' });
    }
    const timestamp = now();
    const minute = Math.floor(timestamp / 60000);
    const day = Math.floor(timestamp / 86400000);
    const stats = limits.get(user.uid) || { minute, minuteCount: 0, day, dayCount: 0 };
    if (stats.minute !== minute) {
      stats.minute = minute;
      stats.minuteCount = 0;
    }
    if (stats.day !== day) {
      stats.day = day;
      stats.dayCount = 0;
    }
    if (stats.minuteCount >= maxPerMinute || stats.dayCount >= maxPerDay) {
      return reply(res, 429, { error: 'quota_exceeded' });
    }
    if (active >= maxParallel) {
      return reply(res, 503, { error: 'busy_retry_later' });
    }
    stats.minuteCount++;
    stats.dayCount++;
    limits.set(user.uid, stats);
    active++;
    try {
      const answer = await complete({ message, language: payload.language });
      if (typeof answer !== 'string' || !answer.trim()) {
        return reply(res, 502, { error: 'empty_model_response' });
      }
      return reply(res, 200, { answer: answer.slice(0, 4000) });
    } catch {
      return reply(res, 502, { error: 'model_unavailable' });
    } finally {
      active--;
    }
  };
}
