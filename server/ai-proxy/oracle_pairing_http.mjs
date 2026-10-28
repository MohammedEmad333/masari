// Disabled-by-default pairing HTTP boundary. Deployment must additionally
// enforce rate limits at the reverse proxy / shared store before enabling.
// No credentials, IPs, or tokens are logged.
export function createPairingHandler({
  redeemCode,
  enabled = false,
  now = () => Date.now(),
  perWindow = 5,
  windowMs = 60000,
} = {}) {
  if (typeof redeemCode !== 'function') throw new TypeError('redeemCode required');
  if (!Number.isSafeInteger(perWindow) || perWindow < 1 ||
      !Number.isSafeInteger(windowMs) || windowMs < 1000) {
    throw new TypeError('Invalid pairing limits');
  }
  const attempts = new Map();
  function reply(res, status, body) {
    res.writeHead(status, {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    });
    res.end(JSON.stringify(body));
  }
  return async (req, res) => {
    if (req.url !== '/v1/assistant/pair') return false;
    if (!enabled) {
      reply(res, 404, { error: 'not_found' });
      return true;
    }
    if (req.method !== 'POST') {
      reply(res, 405, { error: 'method_not_allowed' });
      return true;
    }
    const identity = req.socket.remoteAddress || 'unknown';
    const slot = Math.floor(now() / windowMs);
    const existing = attempts.get(identity);
    const count = existing?.slot === slot ? existing.count : 0;
    // A single-process hard ceiling protects memory against spoofed XFF data.
    // This deliberately ignores caller-controlled forwarded headers.
    if (attempts.size > 2048) attempts.clear();
    attempts.set(identity, { slot, count: count + 1 });
    if (count >= perWindow) {
      reply(res, 429, { error: 'too_many_attempts' });
      return true;
    }
    if (!/^application\/json(?:\s*;|$)/i.test(req.headers['content-type'] || '')) {
      reply(res, 415, { error: 'content_type' });
      return true;
    }
    const length = Number(req.headers['content-length'] || 0);
    if (!Number.isFinite(length) || length < 0 || length > 256) {
      reply(res, 413, { error: 'request_too_large' });
      return true;
    }
    let bytes = 0;
    const chunks = [];
    try {
      for await (const chunk of req) {
        bytes += chunk.length;
        if (bytes > 256) {
          reply(res, 413, { error: 'request_too_large' });
          return true;
        }
        chunks.push(chunk);
      }
    } catch {
      if (!res.writableEnded) reply(res, 400, { error: 'invalid_request' });
      return true;
    }
    let body;
    try { body = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
    catch {
      reply(res, 400, { error: 'invalid_request' });
      return true;
    }
    if (!body || typeof body !== 'object' || Array.isArray(body) ||
        Object.keys(body).length !== 1 ||
        typeof body.code !== 'string' ||
        !/^pair_[0-9a-f]{64}$/.test(body.code)) {
      reply(res, 400, { error: 'invalid_request' });
      return true;
    }
    try {
      const result = await redeemCode(body.code);
      if (!result) {
        reply(res, 401, { error: 'invalid_or_expired_pairing_code' });
        return true;
      }
      reply(res, 200, { token: result.token, expiresAt: result.expiresAt });
    } catch {
      reply(res, 503, { error: 'pairing_unavailable' });
    }
    return true;
  };
}
