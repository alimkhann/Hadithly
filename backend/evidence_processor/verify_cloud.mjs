import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
import { JWT } from 'google-auth-library';

async function verify() {
const [origin, credentialPath, fixtureDirectory] = process.argv.slice(2);
const url = new URL(origin);
assert.equal(url.protocol, 'https:');
assert.ok(url.hostname.endsWith('.run.app'));
assert.equal(url.origin, origin);
const credentials = JSON.parse(await readFile(credentialPath, 'utf8'));
const client = new JWT({ email: credentials.client_email, key: credentials.private_key });
client.transporter.defaults.timeout = 5000;
client.transporter.defaults.retry = false;
const token = await client.fetchIdToken(origin);
const headers = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
const unauthenticated = await fetch(`${origin}/health`, { signal: AbortSignal.timeout(15000), redirect: 'error' });
assert.equal(unauthenticated.status, 403);
const health = await fetch(`${origin}/health`, { headers, signal: AbortSignal.timeout(110000), redirect: 'error' });
assert.equal(health.status, 200);
assert.equal((await health.json()).accessPolicyVersion, 'e3-v1');
console.log('Private IAM boundary and startup scanner/sandbox controls passed');

async function processPayload(payload) {
  const response = await fetch(`${origin}/process`, { method: 'POST', headers, body: JSON.stringify(payload), redirect: 'error', signal: AbortSignal.timeout(115000) });
  assert.equal(response.status, 200);
  return response.json();
}
function filePayload(bytes, mime) {
  return { kind: 'file', mime, language: 'en', sha256: createHash('sha256').update(bytes).digest('hex'), bytesBase64: bytes.toString('base64') };
}
for (const [name, mime] of [['source.png', 'image/png'], ['source.pdf', 'application/pdf']]) {
  const bytes = await readFile(`${fixtureDirectory}/${name}`);
  const result = await processPayload(filePayload(bytes, mime));
  assert.equal(result.kind, 'ready');
  assert.equal(result.sha256, createHash('sha256').update(bytes).digest('hex'));
  assert.match(result.text, /instructions/i);
  assert.match(result.text, /credentials/i);
  assert.ok(result.spans.length > 0);
  assert.ok(result.spans.every(span => span.source.kind === 'page_box' && span.source.page === 1 && span.start >= 0 && span.end <= result.text.length));
  console.log(`${mime} OCR and untrusted source offsets passed`);
}
const eicar = Buffer.from('X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*');
assert.deepEqual(await processPayload(filePayload(eicar, 'image/png')), { kind: 'infected' });
console.log('EICAR scanner control passed');
assert.deepEqual(await processPayload(filePayload(Buffer.from('%PDF-1.4 malformed fixture'), 'application/pdf')), { kind: 'failed', retryable: false });
for (const destination of ['https://127.0.0.1/', 'https://metadata.google.internal/latest', 'https://[::1]/']) {
  assert.deepEqual(await processPayload({ kind: 'url', url: destination, language: 'en' }), { kind: 'failed', retryable: false });
}
console.log('Malformed PDF, loopback and metadata rejection passed');
for (const destination of ['https://sunnah.com/bukhari:1', 'https://SUNNAH.COM:443/bukhari:1', 'https://sunnah.com/allowed/../other']) {
  assert.deepEqual(await processPayload({ kind: 'url', url: destination, language: 'en' }), { kind: 'failed', retryable: false });
}
assert.deepEqual(await processPayload({ kind: 'url', url: 'https://example.org/', language: 'en', deniedOrigins: ['https://example.org'] }), { kind: 'failed', retryable: false });
console.log('Sunnah.com access permission and cached avoid-policy rejection passed');
const page = await processPayload({ kind: 'url', url: 'https://example.org/', language: 'en' });
assert.equal(page.kind, 'ready');
assert.equal(page.finalUrl, 'https://example.org/');
assert.deepEqual(page.accessChain, ['https://example.org/']);
assert.equal(page.sha256, createHash('sha256').update(Buffer.from(page.sourceBytesBase64, 'base64')).digest('hex'));
assert.ok(page.spans.every(span => span.source.kind === 'html_chars'));
console.log('Public HTTPS fetch and exact source snapshot passed');

}
verify().catch(error => { console.error("Cloud verification failed:", error?.name === "AssertionError" ? error.message : "authentication or transport failure"); process.exitCode = 1; });
