import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {readFile,writeFile,mkdtemp,rm,chmod} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
const execute=promisify(execFile), root=fileURLToPath(new URL('../../', import.meta.url));
const device=process.env.Q1_IOS_DEVICE_ID;
const packages=process.env.Q1_SWIFT_PACKAGES;
if (!device || !packages) throw new Error('Set Q1_IOS_DEVICE_ID and Q1_SWIFT_PACKAGES to the connected phone and verified package directory.');
const metadata=JSON.parse(await readFile(process.argv[2]??'/tmp/hadithly-q1-live.json','utf8'));
let directory;
async function call(functionName,args) {
 const path=join(directory,'request.json');
 await writeFile(path,JSON.stringify({functionName,args,identity:metadata.identity}),{mode:0o600});
 const {stdout}=await execute(process.execPath,['scripts/private-convex-run.mjs',path],{cwd:root+'/backend',timeout:120000,maxBuffer:1000000});
 return JSON.parse(stdout);
}
async function copyTo(path,destination) { await execute('xcrun',['devicectl','device','copy','to','--device',device,'--source',path,'--destination',destination,'--domain-type','appDataContainer','--domain-identifier','com.hadithly.app'],{timeout:30000}); }
async function hardware(input,index) {
 const path=join(directory,'input.json');await writeFile(path,JSON.stringify(input),{mode:0o600});
 await copyTo(path,'Documents/q1-attest-input.json');
 const stamp=Date.now();
 await execute('xcodebuild',['-project','Hadithly.xcodeproj','-scheme','Hadithly','-destination','platform=iOS,id='+device,
  '-derivedDataPath','/tmp/hadithly-q1-device','-clonedSourcePackagesDirPath',packages,
  '-disableAutomaticPackageResolution','-skipPackageUpdates','DEVELOPMENT_TEAM=6378AFQPXV','test-without-building',
  '-only-testing:HadithlyTests/AppAttestQ1LiveTests','-collect-test-diagnostics','never','-resultBundlePath',`/tmp/hadithly-q1-hardware-${index}-${stamp}.xcresult`],
  {cwd:root+'/ios',env:{...process.env,TEST_RUNNER_Q1_HARDWARE_PROOF:'1'},timeout:180000,maxBuffer:8000000});
 const output=join(directory,'output.json');
 await execute('xcrun',['devicectl','device','copy','from','--device',device,'--source','Documents/q1-attest-output.json','--destination',output,'--domain-type','appDataContainer','--domain-identifier','com.hadithly.app'],{timeout:30000});
 await chmod(output,0o600);return JSON.parse(await readFile(output,'utf8'));
}
async function verify() {
 directory=await mkdtemp(join(tmpdir(),'hadithly-q1-device-private-'));await chmod(directory,0o700);
 let keyId;
 for(const [index,language] of ['de','fr'].entries()) {
  const args={hadithInternalId:metadata.targets[9].canonicalId,targetLanguage:language,...(keyId?{keyId}:{})};
  const challenge=await call('generationIntegrity:beginChallenge',args);
  const proof=await hardware({payload:challenge.payload,kind:keyId?'assertion':'attestation',...(keyId?{keyId}:{})},index);
  keyId=proof.keyId;
  const result=await call('actions/ai:translateHadith',{hadithInternalId:args.hadithInternalId,targetLanguage:language,challengeId:challenge.challengeId,proof:{kind:'app_attest',...proof}});
  assert.equal(result.cached,false);assert.equal(result.groundingUsed,false);
  console.log(index===0?'Physical iPhone → Apple attestation → deployed Node certificate/nonce/app validation → global generation passed.':'Physical iPhone assertion → deployed signature/counter validation → global generation passed.');
  await assert.rejects(call('actions/ai:translateHadith',{hadithInternalId:args.hadithInternalId,targetLanguage:'it',challengeId:challenge.challengeId,proof:{kind:'app_attest',...proof}}));
  console.log('Consumed hardware challenge replay rejected.');
 }
}
verify().catch(error=>{console.error(error?.name==='AssertionError'?error.message:'Q1 physical proof step failed; raw proof and response details suppressed.');process.exitCode=1;})
 .finally(async()=>{
  if(!directory)return;
  try {const empty=join(directory,'empty.json');await writeFile(empty,'{}',{mode:0o600});await copyTo(empty,'Documents/q1-attest-input.json');await copyTo(empty,'Documents/q1-attest-output.json');} catch {}
  await rm(directory,{recursive:true,force:true});
 });
