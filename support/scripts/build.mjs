import { readFile, mkdir, writeFile } from 'node:fs/promises';
const config = JSON.parse(await readFile(new URL('../data/config.json', import.meta.url)));
const manifest = JSON.parse(await readFile(new URL('../data/movd-v1.json', import.meta.url)));
if (manifest.modelVersion !== config.supportedModelVersions[0]) throw new Error('Catalog mismatch');
if (manifest.archives.length !== 3 || manifest.archives.reduce((n, a) => n + a.bytes, 0) !== 14133836614) throw new Error('Unexpected original model inventory');
for (const archive of manifest.archives) {
  if (!/^[a-f0-9]{64}$/.test(archive.sha256) || !archive.url.startsWith('https://')) throw new Error('Invalid pinned archive');
}
await mkdir(new URL('../public/api/v1/models/', import.meta.url), { recursive: true });
await writeFile(new URL('../public/api/v1/config.json', import.meta.url), JSON.stringify(config));
await writeFile(new URL('../public/api/v1/models/movd-v1.json', import.meta.url), JSON.stringify(manifest));
console.log('Generated versioned configuration and pinned model manifest. No model weights bundled.');
