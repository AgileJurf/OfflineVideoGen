// Explicit research probe of a public community Space; synthetic input only.
// This is not an app integration, a service guarantee, or a speed benchmark.
import { readFile, writeFile } from 'node:fs/promises';
const origin = 'https://1inkusface-rife.hf.space';
const directory = new URL('../build/HybridProbe/', import.meta.url);
const input = await readFile(new URL('synthetic-12fps.mp4', directory));
const start = performance.now();
if (process.argv.includes('--client')) {
  // Install the official client in the ignored probe directory, not the app/backend.
  const { Client, handle_file } = await import('../build/HybridProbe/node_modules/@gradio/client/dist/index.js');
  const deadline = setTimeout(() => { console.error('60-second probe deadline reached'); process.exit(2); }, 60000);
  const statuses = [];
  try {
    const client = await Client.connect(origin, { events: ['status', 'data'] });
    const file = new File([input], 'synthetic-12fps.mp4', { type: 'video/mp4' });
    const job = client.submit('/interpolate_video', [{ video: handle_file(file), subtitles: null }, '2', false, 'native', 'mp4']);
    for await (const event of job) {
      if (event.type === 'status') {
        const status = { stage: event.stage, success: event.success, message: event.message };
        statuses.push(status); console.log(JSON.stringify(status));
        if (event.stage === 'error') { process.exitCode = 1; break; }
      }
      if (event.type === 'data') await writeFile(new URL('client-result.json', directory), JSON.stringify(event.data));
    }
    await writeFile(new URL('client-status.json', directory), JSON.stringify({ provider: origin, syntheticOnly: true, statuses }, null, 2));
  } finally { clearTimeout(deadline); }
  process.exit(process.exitCode ?? 0);
}
async function request(path, options = {}) {
  const response = await fetch(origin + path, { ...options, redirect: 'error', signal: AbortSignal.timeout(180000) });
  if (!response.ok) throw new Error(`HTTP ${response.status}: ${(await response.text()).slice(0, 500)}`);
  return response;
}
const form = new FormData();
form.append('files', new Blob([input], { type: 'video/mp4' }), 'synthetic-12fps.mp4');
const uploaded = await (await request('/gradio_api/upload', { method: 'POST', body: form })).json();
if (!Array.isArray(uploaded) || uploaded.length !== 1 || typeof uploaded[0] !== 'string') throw new Error('Unexpected upload contract');
const data = [{ video: { path: uploaded[0], orig_name: 'synthetic-12fps.mp4', meta: { _type: 'gradio.FileData' } }, subtitles: null }, '2', false, 'native', 'mp4'];
const submitted = await (await request('/gradio_api/call/interpolate_video', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ data }) })).json();
if (!/^[a-f0-9]{32}$/.test(submitted.event_id)) throw new Error('Unexpected job identifier');
console.log('Synthetic interpolation submitted; no user file or prompt sent.');
const events = await (await request('/gradio_api/call/interpolate_video/' + submitted.event_id)).text();
await writeFile(new URL('events.txt', directory), events);
const complete = events.match(/event: complete\r?\ndata: (.*)/);
if (!complete) { console.log(events.slice(-3000)); process.exitCode = 1; }
else {
  const result = JSON.parse(complete[1]);
  const url = new URL(result[0].video.url);
  if (url.origin !== origin || !url.pathname.startsWith('/gradio_api/file=')) throw new Error('Unexpected output destination');
  const response = await request(url.pathname + url.search);
  const bytes = Buffer.from(await response.arrayBuffer());
  if (bytes.length > 16 * 1024 * 1024) throw new Error('Oversized output');
  await writeFile(new URL('synthetic-interpolated.mp4', directory), bytes);
  const metrics = { provider: origin, checkedAt: new Date().toISOString(), inputBytes: input.length, outputBytes: bytes.length, wallSeconds: (performance.now() - start) / 1000, syntheticOnly: true };
  await writeFile(new URL('result.json', directory), JSON.stringify(metrics, null, 2));
  console.log(JSON.stringify(metrics));
}
