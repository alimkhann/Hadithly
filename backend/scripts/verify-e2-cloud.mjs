import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, writeFile, chmod, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const execute = promisify(execFile);
let privateDirectory;
async function verify() {
  const get = async name => (await execute('npx', ['convex', 'env', 'get', name, '--deployment', 'festive-cobra-664'], { timeout: 30000 })).stdout.trim();
  const origin = await get('EVIDENCE_PROCESSOR_URL');
  const credential = await get('EVIDENCE_PROCESSOR_GOOGLE_CREDENTIALS');
  JSON.parse(credential);
  privateDirectory = await mkdtemp(join(tmpdir(), 'hadithly-e2-private-'));
  await chmod(privateDirectory, 0o700);
  const credentialPath = join(privateDirectory, 'invoker.json');
  await writeFile(credentialPath, credential, { mode: 0o600 });
  const { stdout } = await execute(process.execPath, ['evidence_processor/verify_cloud.mjs', origin, credentialPath,
    process.argv[2] ?? '/tmp/hadithly-e2-cloud-fixtures'], { timeout: 480000, maxBuffer: 1000000 });
  process.stdout.write(stdout);
}
verify().catch(error => {
  if (typeof error.stdout === 'string') process.stdout.write(error.stdout);
  const summary = typeof error.stderr === 'string' ? error.stderr.split('\n').filter(line => line.startsWith('Cloud verification failed:')).join('\n') : '';
  console.error(summary || 'E2 cloud verification failed; credential and response details suppressed.'); process.exitCode = 1;
})
  .finally(async () => { if (privateDirectory) await rm(privateDirectory, { recursive: true, force: true }); });
