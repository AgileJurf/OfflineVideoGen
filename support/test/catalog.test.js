import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

const read = path => JSON.parse(readFileSync(new URL(path, import.meta.url)));
test('published catalog retains the shipped hashes, URLs and all partition names', () => {
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: new URL('../', import.meta.url) });
  const manifest = read('../public/api/v1/models/movd-v1.json');
  const original = read('../../LocalFrames/Resources/model-manifest.json');
  assert.deepEqual(manifest.archives, original.archives); assert.equal(manifest.revision, original.revision);
  assert.equal(manifest.archives.reduce((n, a) => n + a.bytes, 0), 14133836614);
  assert.equal(manifest.archives.flatMap(a => a.models).length, 103);
  assert.equal(manifest.minimumAppVersion, '0.1.0'); assert.equal(manifest.modelVersion, 'movd-v1');
});
test('bundled and published configuration agree; no experimental inference preset is enabled', () => {
  const config = read('../data/config.json');
  assert.deepEqual(config, read('../../LocalFrames/Resources/support-config.json'));
  assert.deepEqual(config.inferenceProfiles.map(p => p.id), ['movd-fp32-rflow21-spatial-cpu-v2']);
  assert.equal(config.inferenceProfiles[0].diffusionEvaluations, 21);
  assert.deepEqual(config.inferenceProfiles[0].validatedDurations, [2]);
  assert.equal(config.diagnostics.maximumBytes, 32768);
});
