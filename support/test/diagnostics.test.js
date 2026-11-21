import test from 'node:test';
import assert from 'node:assert/strict';
import { acceptReport, validateReport, slotAt, MAX_BYTES } from '../lib/diagnostics.js';
import handler from '../api/v1/diagnostics.js';

export const fixture = () => ({ schemaVersion: 1, appVersion: '0.1.0', appBuild: 1, osVersion: '18.4.0', modelVersion: 'movd-v1', kind: 'generation', outcome: 'failed', resumed: false, elapsedSeconds: 12.345, peakSampledMemoryBytes: 1000000, memoryWarnings: 1, thermalState: 'fair', partitions: [{ name: 'stdit3_ST_0', loads: 1, predictions: 0, loadSeconds: 2.2, predictionSeconds: 0, failures: 1 }], lastOperation: { partition: 'stdit3_ST_0', phase: 'load' }, errorCategory: 'model-load', errorDomain: 'CoreML', errorCode: 1 });
const now = new Date('2026-11-21T10:15:00Z');

test('accepts the typed payload, including a null error/operation', () => {
  assert.equal(validateReport(fixture()), true);
  const report = fixture(); report.errorCode = null; report.lastOperation = null;
  assert.equal(validateReport(report), true);
});
test('rejects every extra field and unconstrained string channel', () => {
  for (const key of ['prompt', 'seed', 'video', 'file', 'deviceID', 'email', 'errorMessage']) {
    assert.equal(validateReport({ ...fixture(), [key]: 'PRIVATE_SENTINEL' }), false);
  }
  for (const key of ['appVersion', 'osVersion', 'kind', 'outcome', 'modelVersion', 'errorDomain', 'errorCategory', 'thermalState']) {
    assert.equal(validateReport({ ...fixture(), [key]: 'PRIVATE_SENTINEL' }), false);
  }
  const bad = fixture(); bad.partitions[0].prompt = 'PRIVATE_SENTINEL'; assert.equal(validateReport(bad), false);
  const unknown = fixture(); unknown.partitions[0].name = '/private/file.mov'; assert.equal(validateReport(unknown), false);
});
test('rejects malformed, duplicate and out-of-bounds numeric fields', () => {
  for (const value of [NaN, Infinity, -1, 604801, '12']) assert.equal(validateReport({ ...fixture(), elapsedSeconds: value }), false);
  for (const value of [null, [], true, 'text']) assert.equal(validateReport(value), false);
  const duplicate = fixture(); duplicate.partitions.push(duplicate.partitions[0]); assert.equal(validateReport(duplicate), false);
  const nested = fixture(); nested.lastOperation.path = 'secret'; assert.equal(validateReport(nested), false);
});
test('no consent, oversized and invalid reports never reach storage', async () => {
  let calls = 0;
  const store = async () => { calls++; throw new Error('must not store'); };
  for (const [body, consent, status] of [[JSON.stringify(fixture()), '', 403], [' '.repeat(MAX_BYTES + 1), 'report-v1', 413], ['null', 'report-v1', 400], ['{', 'report-v1', 400]]) {
    assert.equal((await acceptReport({ body, consent, store, now })).status, status);
  }
  assert.equal(calls, 0);
});
test('stores privately with provider TTL and verifies expiry through head', async () => {
  let options, path, stored;
  const result = await acceptReport({ body: JSON.stringify(fixture()), consent: 'report-v1', now,
    store: async (p, body, o) => { path = p; stored = JSON.parse(body); options = o; return { url: 'https://private.example/report' }; },
    inspect: async url => { assert.equal(url, 'https://private.example/report'); return { expiresAt: new Date(now.getTime() + 31 * 86400000) }; }
  });
  assert.equal(result.status, 201); assert.deepEqual(stored, fixture());
  assert.equal(path, 'reports/2026-11-21/10.json');
  assert.equal(options.access, 'private'); assert.equal(options.allowOverwrite, false); assert.equal(options.addRandomSuffix, false); assert.equal(options.ttlDays, 30);
  assert.equal('url' in result.body, false);
});
test('one create-only slot wins concurrent reports; overflow is recoverable', async () => {
  let used = false;
  const store = async () => { if (used) throw Object.assign(new Error(), { name: 'BlobAlreadyExistsError' }); used = true; return { url: 'private' }; };
  const args = { body: JSON.stringify(fixture()), consent: 'report-v1', store, now, inspect: async () => ({ expiresAt: new Date(now.getTime() + 31 * 86400000) }) };
  const results = await Promise.all([acceptReport(args), acceptReport(args)]);
  assert.deepEqual(results.map(r => r.status).sort(), [201, 429]);
  assert.equal(slotAt(new Date('2026-11-21T11:59:59Z')), slotAt(now));
  assert.notEqual(slotAt(new Date('2026-11-21T12:00:00Z')), slotAt(now));
});
test('missing TTL confirmation and storage failures never report success or leak errors', async () => {
  const args = { body: JSON.stringify(fixture()), consent: 'report-v1', now, store: async () => ({ url: 'private' }), inspect: async () => ({}) };
  assert.equal((await acceptReport(args)).status, 503);
  const result = await acceptReport({ ...args, store: async () => { throw new Error('PRIVATE_CREDENTIAL'); } });
  assert.equal(result.status, 503); assert.equal(JSON.stringify(result).includes('PRIVATE_CREDENTIAL'), false);
});
test('HTTP handler refuses non-POST, absent consent and unavailable configuration', async () => {
  const old = process.env.DIAGNOSTICS_ENABLED; process.env.DIAGNOSTICS_ENABLED = 'false';
  try {
    for (const [method, headers, expected] of [['GET', {}, 405], ['POST', {}, 415], ['POST', { 'content-type': 'application/json' }, 403], ['POST', { 'content-type': 'application/json', 'x-localframes-consent': 'report-v1' }, 503]]) {
      const response = { headers: {}, setHeader(k, v) { this.headers[k] = v; }, status(s) { this.code = s; return this; }, json(body) { this.body = body; } };
      await handler({ method, headers }, response); assert.equal(response.code, expected);
      assert.equal(response.headers['Cache-Control'], 'no-store');
    }
  } finally { if (old === undefined) delete process.env.DIAGNOSTICS_ENABLED; else process.env.DIAGNOSTICS_ENABLED = old; }
});
