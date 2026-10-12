# E2 verification

Refreshed 2026-10-12. E2 passed in development. E1's remaining device matrix stays
open under the owner's explicit exception. E3 and E4 subsequently passed their
separate development gates. The original session evidence below is retained.

| Check | Evidence | State |
| --- | --- | --- |
| Backend contracts and privacy | Typechecking and 190 tests across 19 files | Passed |
| Development schema and functions | `npx convex dev --once`, `festive-cobra-664`, including worker lease index | Deployed |
| SSRF and DNS rebinding | All A/AAAA answers checked, private/special prefixes rejected, numeric socket pinning with original TLS hostname | Passed |
| Redirect and fetch timeout | Three-hop cap, each-hop HTTPS/DNS revalidation, actual slow socket with wall deadline | Passed |
| Bytes and decompression | Streamed size, expanded size and ratio, unsupported encodings | Passed |
| Malware controls | Actual ClamAV: standard EICAR, EICAR ZIP, clean control, stale/error fail-closed, scan-limit classification | Passed |
| Image and PDF OCR | Actual Tesseract/Poppler read instruction-like text as data and return page boxes | Passed |
| Extraction authority | Separate UID, stripped environment, seccomp socket/io_uring denial, read-only application files | Passed |
| Source offsets | UTF-16 assembled-text offsets, HTML source offsets, matching private source snapshot hash | Passed |
| State and retry | Three manual attempts, duplicate retry rejection, absent-config preservation, expired-lease recovery | Passed |
| One-slot queue | Waiting items spend no attempt; global lease survives withdrawal; next job starts immediately | Passed |
| Deletion and infection | Withdrawal/account deletion, late-result rejection, infected sibling cancellation | Passed |
| Linux processor suite | All 12 tests at 1 CPU and 1 GiB | Passed |
| Android status UI | Production processing/failed/infected/ready content and Retry, AVD `hadithly`, `emulator-5554` | Passed |
| iOS status UI | Four states, Retry, no scanner details, 44-point controls; iPhone 18 Pro `40FDE642-C9F1-46C4-83E3-4D2469BDE3A6` | Passed |
| iOS local drafts | Two focused unit tests and current simulator test build | Passed |
| Private cloud worker | Unauthenticated HTTP 403; authenticated health, PNG/PDF OCR, EICAR, malformed PDF, private destinations and HTTPS snapshot | Passed |
| Deployed Convex workflow | Actual private Cloud Run action, untrusted extraction, coarse owner status, SSRF failure, three attempts, cleanup | Passed |
| Native signed-in end-to-end | Each native client uploaded generated PNG/PDF plus HTTPS source, observed three ready items, then withdrew its submission | Passed |

## Current development refresh (2026-10-12)

The owner requested completion of the remaining Q1 and E2 work. E2 already had no
open development implementation gate. These checks refresh its deployed proof:

| Check | Result |
| --- | --- |
| Private worker | Unauthenticated health HTTP 403; authenticated health HTTP 200 and `e3-v1`. Actual PNG/PDF OCR, EICAR, malformed PDF, metadata/loopback, denied source policy, and exact HTTPS snapshot checks pass. `/tmp/hadithly-e2-refresh-cloud2.log`. |
| Deployed processing | Private Cloud Run processing produces private untrusted extraction and coarse owned status. Private destinations fail closed; three manual attempts exhaust correctly. Withdrawal cleans the disposable rows and preserves existing users, submissions, and translations. `/tmp/hadithly-e2-refresh-convex2.log`. |
| Native iOS | Existing Clerk session, actual PNG/PDF/HTTPS uploads, three ready items, and withdrawal pass without skips on iPhone 18 Pro iOS 27. `/tmp/hadithly-e2-refresh-ios2.xcresult`. |
| Native Android | Same actual three-item flow passes on `hadithly`, Android 16, `emulator-5554`. Instrumentation XML reports one test, zero failures, zero skips. `/tmp/hadithly-e2-refresh-android.log`. |

The first cloud/workflow attempts ran alongside other worker verification and
failed. Isolated reruns and both authenticated native flows pass. No processor
implementation, IAM, worker credential, billing setting, or production service
changed. The canonical URL and worker access policy are verified live. Resource
and IAM configuration were last read back in E3 on October 11; that readback is
not relabeled as a new audit.

`backend/scripts/verify-e2-cloud.mjs` captures the existing development invoker
credential without printing it, stages it in a mode-0600 private temporary file,
runs the existing synthetic verifier, and removes it in `finally`. It prints
only the verifier's assertion summaries. No temporary credential file remains.
No Docker resource was created by this refresh.

## Original cloud readback (2026-10-10)

The owner approved billing, the $10 monthly Cloud Run cap, private source upload,
service deployment, and the dedicated invocation credential at their action
boundaries. The cap is configured for `hadithlyapp`, with 50%, 80%, and 100%
alerts. Reporting delay can exceed the cap, and builds/image/source storage are
outside it.

- Service: `hadithly-evidence-processor-dev`, `europe-west1`.
- Canonical origin: `https://hadithly-evidence-processor-dev-d5r7bxbvdq-ew.a.run.app`.
- Revision: `hadithly-evidence-processor-dev-00001-cg5`, ready and serving 100%.
- Image digest: `sha256:9cadcd48b04dbea6bf882a9c03ea8ac704de1f1ee9e6207567877c5966b0bb1e`.
- Successful Cloud Build: `4c38ea7e-d550-4cb3-bb0d-f129bac8fef6`.
- Runtime: second generation, 1 CPU, 1 GiB, concurrency 1, minimum 0,
  maximum 1, 110-second timeout. Default startup CPU boost remains enabled.
- Runtime identity: dedicated worker, no project roles.
- Invocation: only the dedicated invoker has service-level `roles/run.invoker`;
  it has no project roles. No unauthenticated binding exists.
- Convex configuration is development only. Temporary credential copies were
  removed from Cloud Shell and the host after installation and real verification.

The Dockerfile needed a trailing slash for Google's Docker builder. The first
private request also exposed an audience mismatch: the deterministic URL printed
by deployment rejected its ID token, while the canonical `status.url` accepted
it. Convex now uses the canonical origin.

## Native and workflow evidence

The status UI test passed on iOS in `/tmp/hadithly-e2-20261010-ui4.xcresult`.
The signed-in iOS integration passed with no skipped tests in
`/tmp/hadithly-e2-live-cloud4.xcresult`. Android's production status component and
its signed-in integration both passed; the latter reports `OK (1 test)` in
`/tmp/hadithly-e2-android-live-final.log`.

Both old device sessions were absent. The owner separately approved single-use,
10-minute Clerk tickets for the existing development test account. The native
SDKs consumed them from private device files. Temporary key, ticket, and account
metadata files were removed; no credential was printed or committed.

The first signed-in three-item run found parallel scheduler requests overrunning
the one-slot worker. The final Convex global lease serializes jobs across
submissions and survives deletion of the current evidence item. Both native
three-item tests then passed while running concurrently.

`backend/evidence_processor/verify_cloud.mjs` reruns the private worker controls.
`verify_convex.mjs` reruns the deployed workflow with a disposable administrative
test identity, verifies the existing table IDs are preserved, and removes the
fixture user and evidence. That CLI test does not stand in for native Clerk JWT
verification; the signed-in native tests above cover that path.

Final development readback shows zero evidence items, extractions, retained URL
source snapshots, and worker leases after all disposable checks.

## Scope and cleanup

E2 stores extracted text as untrusted private evidence. It does not perform AI
review, licensing decisions, or publication. The original E2 session left E3 untouched; later E3/E4 evidence is recorded in
their own verification files. E1's iOS
progress/cancellation, account-switch, RTL, and assistive-technology device
matrix remains open.

At the owner's request, all local Docker containers, images, volumes, custom
networks, and build cache were removed. Docker readback shows zero containers,
images, volumes, and cache; only built-in `bridge`, `host`, and `none` networks
remain. Docker Desktop itself and unrelated workspace files were preserved.
