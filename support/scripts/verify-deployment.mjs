// Live acceptance uses fabricated data only, never device journals or user media.
// --store-synthetic writes one report with a 30-day TTL and consumes the global slot.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const origin = 'https://localframes-support.vercel.app';
const upload = process.argv.includes('--store-synthetic');
const report = { schemaVersion: 1, appVersion: '0.1.0', appBuild: 1, osVersion: '18.4.0', modelVersion: 'movd-v1', kind: 'generation', outcome: 'failed', resumed: false, elapsedSeconds: 12.345, peakSampledMemoryBytes: 1000000, memoryWarnings: 1, thermalState: 'fair', partitions: [{ name: 'stdit3_ST_0', loads: 1, predictions: 0, loadSeconds: 2.2, predictionSeconds: 0, failures: 1 }], lastOperation: { partition: 'stdit3_ST_0', phase: 'load' }, errorCategory: 'model-load', errorDomain: 'CoreML', errorCode: 1 };
const results = [];
async function check(name, path, expected, options = {}) {
  const response = await fetch(origin + path, { ...options, redirect: 'error', signal: AbortSignal.timeout(30000) });
  const body = await response.json();
  results.push({ name, status: response.status });
  console.log(name, response.status);
  assert.equal(response.status, expected, JSON.stringify(body));
  return { response, body };
}
const config = await check('configuration', '/api/v1/config.json', 200);
assert.deepEqual(config.body, JSON.parse(await readFile(new URL('../data/config.json', import.meta.url))));
const manifest = await check('manifest', '/api/v1/models/movd-v1.json', 200);
assert.deepEqual(manifest.body, JSON.parse(await readFile(new URL('../data/movd-v1.json', import.meta.url))));
await check('method restriction', '/api/v1/diagnostics', 405);
const headers = { 'Content-Type': 'application/json', 'X-LocalFrames-Consent': 'report-v1' };
await check('explicit consent required', '/api/v1/diagnostics', 403, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' });
await check('JSON required', '/api/v1/diagnostics', 415, { method: 'POST', headers: { 'Content-Type': 'text/plain' }, body: '{}' });
await check('unknown field rejected', '/api/v1/diagnostics', 400, { method: 'POST', headers, body: JSON.stringify({ ...report, unknownField: true }) });
await check('size bounded', '/api/v1/diagnostics', 413, { method: 'POST', headers, body: ' '.repeat(32769) });
if (upload) {
  const stored = await check('synthetic report stored with verified expiration', '/api/v1/diagnostics', 201, { method: 'POST', headers, body: JSON.stringify(report) });
  assert.deepEqual(stored.body, { status: 'stored', retentionDays: 30 });
  const limited = await check('same-slot report refused', '/api/v1/diagnostics', 429, { method: 'POST', headers, body: JSON.stringify(report) });
  assert.equal(limited.response.headers.get('Retry-After'), '7200');
}
console.log(JSON.stringify({ origin, checkedAt: new Date().toISOString(), syntheticUpload: upload, results }, null, 2));
