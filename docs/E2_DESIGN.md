# E2 extraction boundary

## Caller and ownership

`finalizeEvidenceDraft` schedules one internal action per item after all uploads
are private and complete. The action claims a lease in a Convex mutation, reads
quarantined file bytes only through Convex storage, calls the private processor,
and commits a validated result only if the lease still matches. An indexed
recovery cron finds expired leases. The owner can retry a failed item, with at
most three claims per item. Retries are manual so a delayed automatic job cannot
consume another attempt after a user retry. Missing service configuration leaves
the queued item intact. Infection cancels siblings and removes their private
bytes and extractions. Nothing in E2 publishes a translation.

The mobile apps use only `evidence:getOwnEvidenceDraft` and
`evidenceProcessing:retryOwnEvidenceProcessing`. They receive coarse states and never receive
storage IDs, extracted text, scanner signatures, resolved IPs, or processor
errors. Withdrawal and account deletion remove private extraction records and
the exact source snapshots retained for fetched URLs.

## Module boundaries

| Module | Input | Output | Authority |
| --- | --- | --- | --- |
| Convex E2 mutations | owned item IDs, lease, validated processor result | private item and extraction rows | database and scheduler |
| Convex E2 action | claimed item, private file blob or URL | one processor request | storage read and private processor call |
| Processor fetcher | HTTPS URL | bounded bytes and final URL | DNS and HTTPS only; no cookies or credentials |
| Processor scanner | bytes | clean, infected, or failed | separate UID, socket denial, resource limits |
| Processor extractor | clean local file and MIME | text spans with source offsets | separate UID, socket denial, stripped environment, read-only app files |

The deployment contract is a private Cloud Run service with IAM invocation. Its runtime
identity has no project permissions. Convex uses a dedicated invoker identity;
credential creation and permission grants require action-time owner approval.
No mobile client can call the processor. Cloud Run is a private processing
dependency, not an application API or database.

## Limits and failure behavior

The fetcher accepts HTTPS on port 443 only, resolves A and AAAA records on each
hop, rejects the whole answer if any address is not globally routable, and
connects to a vetted numeric address while verifying TLS against the original
hostname. It follows at most three redirects. Raw bytes, expanded bytes,
expansion ratio, response time, PDF pages, raster dimensions, OCR time, text
length, action attempts, and worker concurrency are capped. External failures
leave evidence private and fail closed. Scanner failure is never a clean result.

The processor's response is parsed at the Convex boundary into a bounded
discriminated result. Text remains untrusted data. `start` and `end` use UTF-16
code unit offsets into the assembled extracted text; HTML spans also carry
Unicode code point offsets into the decoded source, and OCR spans carry page
and bounding box. URL snapshots stay in private Convex storage with the same
SHA-256 as the extracted record. Late results delete their unattached snapshots,
and an orphan sweep covers a crash before attachment. Review and licensing
belong to E3.

Convex serializes claims through one private worker lease, matching Cloud Run's
one processing slot. A completed job schedules the next queued item immediately.
Waiting items spend no attempt. The worker lease survives withdrawal until the
late result returns or the lease expires, so deleting an item cannot admit a
second overlapping request. The lease contains only an operation token and
deadline, with no user content.

Both ClamAV and the extractor run as UID 10002 with socket syscalls and io_uring
denied by seccomp. Their environment contains no service credentials. The
extractor cannot write the app or scanner database. The trusted HTTP parent owns
fetching and source storage. The container checks a clean control, EICAR, and
socket denial before it opens its health endpoint. It fails startup when those
checks fail. PDF pages render, OCR, and delete one at a time. Output limits apply
as text is collected, and scan-limit alerts become failed evidence.

## Synthesis decision

Two designs were considered: all processing in a Convex Node action, and a
dedicated private processor. A plain Node `fetch` could not prove DNS pinning
across redirects, and Convex actions cannot run the local scanner and OCR
binaries. The private processor keeps those capabilities behind one small
request/response interface while Convex retains all user and workflow state.
