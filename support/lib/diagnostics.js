// This allowlist is independent of the iOS serializer. No arbitrary strings or files are accepted.
import { readFileSync } from 'node:fs';
const manifest = JSON.parse(readFileSync(new URL('../data/movd-v1.json', import.meta.url)));
const names = new Set(manifest.archives.flatMap(a => a.models));
export const MAX_BYTES = 32768;
const object = x => x !== null && typeof x === 'object' && !Array.isArray(x);
const exact = (x, keys) => object(x) && Object.keys(x).sort().join(',') === [...keys].sort().join(',');
const bounded = (x, max) => typeof x === 'number' && Number.isFinite(x) && x >= 0 && x <= max;
const integer = (x, max) => Number.isInteger(x) && bounded(x, max);
const version = x => typeof x === 'string' && /^\d{1,3}\.\d{1,3}(\.\d{1,3})?$/.test(x);
export function validateReport(r) {
  const keys = ['schemaVersion','appVersion','appBuild','osVersion','modelVersion','kind','outcome','resumed','elapsedSeconds','peakSampledMemoryBytes','memoryWarnings','thermalState','partitions','lastOperation','errorCategory','errorDomain','errorCode'];
  if (!exact(r, keys) || r.schemaVersion !== 1 || !version(r.appVersion) || !version(r.osVersion) || !integer(r.appBuild, 1000000)) return false;
  if (r.modelVersion !== manifest.modelVersion || !['generation','installation','compute-plans'].includes(r.kind) || !['succeeded','failed','cancelled','interrupted','completed_with_possible_unsupported_plans'].includes(r.outcome)) return false;
  if (typeof r.resumed !== 'boolean' || !bounded(r.elapsedSeconds, 604800) || !integer(r.peakSampledMemoryBytes, 2 ** 40) || !integer(r.memoryWarnings, 100000)) return false;
  if (!['unknown','nominal','fair','serious','critical'].includes(r.thermalState) || !['none','memory-pressure','model-load','inference','invalid-tensor','installation','encoding','other','interrupted'].includes(r.errorCategory)) return false;
  if (!['none','CoreML','Foundation','POSIX','AVFoundation','LocalFrames','other'].includes(r.errorDomain) || !(r.errorCode === null || (Number.isInteger(r.errorCode) && Math.abs(r.errorCode) <= 2147483647))) return false;
  if (!Array.isArray(r.partitions) || r.partitions.length > 103) return false;
  const seen = new Set();
  for (const p of r.partitions) {
    if (!exact(p, ['name','loads','predictions','loadSeconds','predictionSeconds','failures']) || !names.has(p.name) || seen.has(p.name)) return false;
    seen.add(p.name);
    if (![p.loads,p.predictions,p.failures].every(n => integer(n, 100000)) || ![p.loadSeconds,p.predictionSeconds].every(n => bounded(n, 604800))) return false;
  }
  if (r.lastOperation !== null && (!exact(r.lastOperation, ['partition','phase']) || !names.has(r.lastOperation.partition) || !['load','predict','compile'].includes(r.lastOperation.phase))) return false;
  return true;
}
export function slotAt(date) {
  const hour = Math.floor(date.getUTCHours() / 2) * 2;
  return `reports/${date.toISOString().slice(0, 10)}/${String(hour).padStart(2, '0')}.json`;
}
export async function acceptReport({ body, consent, store, inspect, now = new Date() }) {
  if (consent !== 'report-v1') return { status: 403, body: { error: 'explicit-consent-required' } };
  if (typeof body !== 'string' || Buffer.byteLength(body) > MAX_BYTES) return { status: 413, body: { error: 'report-too-large' } };
  let report;
  try { report = JSON.parse(body); } catch { return { status: 400, body: { error: 'invalid-report' } }; }
  if (!validateReport(report)) return { status: 400, body: { error: 'invalid-report' } };
  // One global slot per two hours: <=372 reports / 31 days. Create-only storage is
  // the concurrency boundary. There are no per-device identifiers or client secrets.
  try {
    const saved = await store(slotAt(now), JSON.stringify(report), { access: 'private', addRandomSuffix: false, allowOverwrite: false, contentType: 'application/json', ttlDays: 30 });
    // put() does not return expiresAt. Confirm the provider's TTL using head().
    const metadata = await inspect(saved.url);
    const expiry = new Date(metadata.expiresAt).getTime();
    if (!Number.isFinite(expiry) || expiry <= now.getTime() || expiry > now.getTime() + 32 * 86400000) return { status: 503, body: { error: 'retention-not-confirmed' } };
    return { status: 201, body: { status: 'stored', retentionDays: 30 } };
  } catch (error) {
    if (error?.name === 'BlobAlreadyExistsError') return { status: 429, body: { error: 'report-slot-used', retryAfterSeconds: 7200 } };
    return { status: 503, body: { error: 'diagnostics-unavailable' } };
  }
}
