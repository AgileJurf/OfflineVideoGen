import { acceptReport, MAX_BYTES } from '../../lib/diagnostics.js';
export const config = { api: { bodyParser: false } };
export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  if (req.method !== 'POST') { res.setHeader('Allow', 'POST'); return res.status(405).json({ error: 'method-not-allowed' }); }
  if (!req.headers['content-type']?.startsWith('application/json')) return res.status(415).json({ error: 'json-required' });
  if (req.headers['x-localframes-consent'] !== 'report-v1') return res.status(403).json({ error: 'explicit-consent-required' });
  // Off unless explicitly enabled on the verified Hobby project with private storage.
  if (process.env.DIAGNOSTICS_ENABLED !== 'true' || !process.env.BLOB_READ_WRITE_TOKEN) return res.status(503).json({ error: 'diagnostics-unavailable' });
  if (Number(req.headers['content-length'] || 0) > MAX_BYTES) return res.status(413).json({ error: 'report-too-large' });
  let length = 0; const chunks = [];
  try {
    for await (const chunk of req) {
      const b = Buffer.from(chunk); length += b.length;
      if (length > MAX_BYTES) return res.status(413).json({ error: 'report-too-large' });
      chunks.push(b);
    }
    const { put, head } = await import('@vercel/blob');
    const result = await acceptReport({ body: Buffer.concat(chunks).toString('utf8'), consent: req.headers['x-localframes-consent'], store: put, inspect: head });
    if (result.status === 429) res.setHeader('Retry-After', '7200');
    return res.status(result.status).json(result.body);
  } catch { return res.status(503).json({ error: 'diagnostics-unavailable' }); }
}
