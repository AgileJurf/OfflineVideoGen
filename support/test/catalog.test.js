import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const read = async path => JSON.parse(await readFile(new URL(path, import.meta.url)));
test('catalog pins the exact app manifest and has no remote inference or diagnostic upload', async () => {
  const [catalog, manifest, bundled] = await Promise.all(['../data/config.json','../data/neodragon-coreml-9s-v1.json','../../LocalFrames/Resources/neodragon-manifest.json'].map(read));
  assert.deepEqual(manifest, bundled);
  assert.deepEqual(catalog.supportedModelVersions, [manifest.modelVersion]);
  assert.equal(catalog.remoteInference, false); assert.equal(catalog.diagnostics.enabled, false);
  assert.equal(manifest.archives.flatMap(a => a.models).length, 168);
  assert.equal(manifest.archives.reduce((n, a) => n + a.bytes, 0), 7881071452);
  for (const archive of manifest.archives) {
    assert.match(archive.sha256, /^[a-f0-9]{64}$/);
    assert.ok(archive.url.startsWith('https://github.com/AgileJurf/OfflineVideoGen/releases/download/' + manifest.modelVersion + '/'));
    assert.ok(archive.bytes > 0 && archive.expandedBytes > 0);
  }
});
