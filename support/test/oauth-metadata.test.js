import { readFile } from 'node:fs/promises';
import test from 'node:test';
import assert from 'node:assert/strict';

test('native helper sign-in is a public device client with no write, repository or paid inference scopes', async () => {
  const metadata = JSON.parse(await readFile(new URL('../public/.well-known/oauth-cimd.json', import.meta.url)));
  assert.equal(metadata.client_id, 'https://localframes-support.vercel.app/.well-known/oauth-cimd.json');
  assert.equal(metadata.token_endpoint_auth_method, 'none');
  assert.equal(metadata.client_secret, undefined);
  assert.deepEqual(metadata.grant_types, ['urn:ietf:params:oauth:grant-type:device_code']);
  assert.deepEqual(metadata.scope.split(' ').sort(), ['openid', 'profile', 'read-billing', 'read-memberships']);
  assert.deepEqual(metadata.redirect_uris, ['localframes://huggingface/callback']);
});
