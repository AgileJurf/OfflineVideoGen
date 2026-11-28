import { readFile, mkdir, writeFile, rm } from 'node:fs/promises';
const config = JSON.parse(await readFile(new URL('../data/config.json', import.meta.url)));
const manifest = JSON.parse(await readFile(new URL('../data/neodragon-coreml-9s-v1.json', import.meta.url)));
if (manifest.modelVersion !== config.supportedModelVersions[0]) throw new Error('Catalog mismatch');
await rm(new URL('../public/api/', import.meta.url), { recursive: true, force: true });
await mkdir(new URL('../public/api/v1/models/', import.meta.url), { recursive: true });
await writeFile(new URL('../public/api/v1/config.json', import.meta.url), JSON.stringify(config));
await writeFile(new URL('../public/api/v1/models/neodragon-coreml-9s-v1.json', import.meta.url), JSON.stringify(manifest));
console.log('Built static model catalog. No inference, upload endpoint, credentials or model weights.');
