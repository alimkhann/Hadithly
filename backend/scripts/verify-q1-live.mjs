import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile, writeFile, access } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';
const execute = promisify(execFile), deployment = 'festive-cobra-664';
const metadataPath = process.argv[3] ?? '/tmp/hadithly-q1-live.json';
async function raw(args) {
  try { return (await execute('npx', ['convex', ...args, '--deployment', deployment], { timeout: 120000, maxBuffer: 1000000 })).stdout.trim(); }
  catch(error) {
    console.error('CLI failed at', args[0], args[1]);
    if (typeof error.stderr === 'string') console.error(error.stderr.split('\n').filter(line => /Uncaught|ValidationError|Error:/.test(line)).slice(0,3).join('\n'));
    throw error;
  }
}
async function run(name, args, identity) { return JSON.parse(await raw(['run', name, JSON.stringify(args ?? {}), ...(identity ? ['--identity', JSON.stringify(identity)] : [])])); }
async function rows(table) { return JSON.parse(await raw(['run', '--inline-query', `return (await ctx.db.query(${JSON.stringify(table)}).take(500)).map(row => ({id:row._id}));`])); }
const tables = ['users','savedItems','savedFolders','readingProgress','translations','licenseRecords'];
async function prepare() {
  let existing = false;
  try { await access(metadataPath); existing = true; } catch {}
  if (existing) {
    const saved = JSON.parse(await readFile(metadataPath, 'utf8'));
    const active = await run('hadiths:getById', { hadithId: saved.targets[0]._id });
    assert.ok(active, 'This record was cleaned; choose a fresh metadata path for a new run.');
    console.log('Existing isolated run adopted; no duplicate fixtures created.');
    return;
  }
  const before = Object.fromEntries(await Promise.all(tables.map(async table => [table, await rows(table)])));
  const providerIds = Array.from({length:10}, () => String(9_000_000_000 + Math.floor(Math.random()*999_999_999)));
  const fixture = await run('q1LiveVerification:seed', { runId: randomUUID(), providerIds });
  const identity = { subject: `q1_fixture_${fixture.runId}`, issuer: 'https://q1-verification.invalid' };
  await run('users:ensureCurrentUser', {}, identity);
  const names = (await raw(['env','list','--names-only'])).split(/\s+/);
  const previousAllow = names.includes('AI_ALLOW_UNATTESTED_DEV') ? await raw(['env','get','AI_ALLOW_UNATTESTED_DEV']) : null;
  const metadata = { ...fixture, providerIds, identity, before, previousAllow };
  await writeFile(metadataPath, JSON.stringify(metadata), {mode:0o600});
  await raw(['env','set','AI_ALLOW_UNATTESTED_DEV','true']);
  await raw(['env','set','APP_ATTEST_BUNDLE_ID','com.hadithly.app']);
  await raw(['env','set','APP_ATTEST_TEAM_ID','6378AFQPXV']);
  console.log('Development fixture and temporary simulator lane prepared; native App Attest identifiers configured.');
}
async function verify() {
  const data = JSON.parse(await readFile(metadataPath,'utf8')), {identity, targets}=data;
  if (data.backendVerified) {
    console.log('Completed isolated backend run adopted; no additional provider calls.');
    return;
  }
  const request = target => ({hadithInternalId:target.canonicalId,targetLanguage:'ru'});
  const invoke = async target => {
    const input=request(target), challenge=await run('generationIntegrity:beginChallenge',input,identity);
    assert.equal(challenge.allowUnavailable,true);
    return run('actions/ai:translateHadith',{...input,challengeId:challenge.challengeId,proof:{kind:'unavailable'}},identity);
  };
  if (!data.freeBoundaryVerified) {
  await assert.rejects(run('actions/ai:translateHadith',request(targets[7]),identity),error=>String(error.stderr).includes('AI_INTEGRITY_REQUIRED'));
  const startingAllowance = await run('quotas:getTranslationAllowance',{},identity);
  assert.ok(startingAllowance.used <= 5);
  assert.equal(startingAllowance.remaining,5-startingAllowance.used);
  for(let i=0;i<5;i++) { const result=await invoke(targets[i]);assert.equal(result.groundingUsed,false);assert.ok(result.translation.trim()); }
  const exhausted=await run('quotas:getTranslationAllowance',{},identity);assert.equal(exhausted.used,5);assert.equal(exhausted.remaining,0);assert.ok(exhausted.retryAt>Date.now());
  assert.equal((await run('actions/ai:translateHadith',request(targets[0]),identity)).cached,true);
  assert.equal((await run('quotas:getTranslationAllowance',{},identity)).used,5);
  await assert.rejects(invoke(targets[5]),error=>String(error.stderr).includes('AI_GENERATION_QUOTA_EXCEEDED'));
    data.freeBoundaryVerified = true;
    await writeFile(metadataPath, JSON.stringify(data), {mode:0o600});
  }
  await run('users:syncRevenueCatEntitlement',{clerkId:identity.subject,revenueCatAppUserId:identity.subject,eventTimestampMs:Date.now(),subscriptionTier:'pro',entitlementExpiresAt:Date.now()+3600000});
  assert.ok([94,95].includes((await run('quotas:getTranslationAllowance',{},identity)).remaining));
  assert.ok((await invoke(targets[5])).translation.trim());
  await run('actions/ai:generateServiceTranslation',{hadithId:targets[6]._id,language:'ru'});
  assert.equal((await run('quotas:getTranslationAllowance',{},identity)).used,6);
  assert.equal((await run('actions/ai:translateHadith',request(targets[6]),identity)).cached,true);
  const keys=JSON.parse(await raw(['run','--inline-query', `const jobs=await ctx.db.query("aiGenerationJobs").collect(); const selected=jobs.filter(row=>${JSON.stringify(targets.slice(0,7).map(x=>x._id))}.includes(row.hadithId)); const events=await ctx.db.query("aiUsageEvents").collect(); const costs=await ctx.db.query("aiCostEvents").collect();return {jobs:selected.map(row=>({key:row.generationKey,status:row.status})),events:events.filter(row=>selected.some(job=>job.generationKey===row.generationKey)).map(row=>({key:row.generationKey})),costs:costs.filter(row=>selected.some(job=>job._id===row.jobId)).map(row=>({grounding:row.groundingUsed,known:row.tokenUsageKnown,cost:row.estimatedMicroUsd,outcome:row.outcome}))};`]));
  assert.equal(keys.events.length,7);assert.equal(new Set(keys.events.map(x=>x.key)).size,7);assert.equal(keys.costs.length,7);assert.ok(keys.costs.every(x=>x.known&&!x.grounding&&x.outcome==='published'));
  data.backendVerified = true;
  await writeFile(metadataPath, JSON.stringify(data), {mode:0o600});
  console.log(JSON.stringify({newGlobalGenerations:7,userCharges:6,serviceUserCharges:0,cachedAndRejectedNewEvents:0,providerCostUsd:keys.costs.reduce((sum,row)=>sum+row.cost,0)/1e6,quotaRetry:true,entitlementRetry:true}));
}
async function cleanup() {
  const data=JSON.parse(await readFile(metadataPath,'utf8'));
  await run('users:deleteCurrentUser',{},data.identity);
  const removed=await run('q1LiveVerification:cleanup',{runId:data.runId,providerIds:data.providerIds});
  if(data.previousAllow===null) await raw(['env','remove','AI_ALLOW_UNATTESTED_DEV']);
  else await raw(['env','set','AI_ALLOW_UNATTESTED_DEV',data.previousAllow]);
  for(const table of tables) assert.deepEqual(await rows(table),data.before[table]);
  console.log(JSON.stringify({removedFixtureHadiths:removed.removed,existingRowsPreserved:true,unattestedLaneRestored:true}));
}
const modes={prepare,verify,cleanup};
const mode=modes[process.argv[2]];
if(!mode) throw new Error('Choose prepare, verify, or cleanup');
mode().catch(error=>{console.error(error?.name==='AssertionError'?error.message:'Q1 live step failed; private details suppressed.');process.exitCode=1;});
