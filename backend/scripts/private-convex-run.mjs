import { readFile } from 'node:fs/promises';
const request = JSON.parse(await readFile(process.argv[2], 'utf8'));
if (!['actions/ai:translateHadith','generationIntegrity:beginChallenge'].includes(request.functionName)) throw new Error('Unsupported private verification request');
const cli = new URL('../node_modules/convex/bin/main.js', import.meta.url).pathname;
// Raw device proof stays in memory, not operating-system process arguments.
process.argv = [process.execPath, cli, 'run', request.functionName, JSON.stringify(request.args),
  '--identity', JSON.stringify(request.identity), '--deployment', 'festive-cobra-664'];
await import(cli);
