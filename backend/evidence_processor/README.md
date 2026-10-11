# E2 private evidence processor

Convex is the only mobile API. This service accepts evidence from a Convex
internal action. It keeps no user records and has no model client. The fetcher
reads one HTTPS document without cookies, credentials, scripts, or linked
resources. ClamAV scans the bytes before the extractor opens an image or PDF.
OCR loads English, Arabic, and the submission's Wave 1 language model.
ClamAV and extraction run under a separate UID with network syscalls denied.
They receive a stripped environment and cannot modify the application files or
scanner database. Startup checks EICAR, a clean control, and socket denial.

## Local check

From this directory, run:

```sh
docker build -t hadithly-evidence-e2:local .
docker run --rm --memory=1g --cpus=1 \
  -v "$PWD/test_processor.py:/app/test_processor.py:ro" \
  hadithly-evidence-e2:local python -m unittest -v test_processor.py
```

The test uses EICAR and an EICAR ZIP as safe malware test files. It also checks
real image and PDF OCR, a clean scanner control, private IP rejection, pinned
DNS, redirect validation, decompression limits, malformed PDF handling, and
untrusted text offsets.

## Development deployment

Build the container from this directory in the `hadithlyapp` Google Cloud
project. Deploy one authenticated Cloud Run service in `europe-west1` with
1 CPU, 1 GiB memory, concurrency 1, minimum instances 0, maximum instances 1,
and a 110-second request timeout. Use the second generation execution environment
so the Linux seccomp boundary can be verified. Use a dedicated runtime service account with
no project roles. Allow network ingress from Convex, but require Cloud Run IAM
authentication. Grant `roles/run.invoker` on this service to one dedicated
invoker service account. Do not grant that account project-wide access.

Store the invoker's credential JSON in the development Convex environment as
`EVIDENCE_PROCESSOR_GOOGLE_CREDENTIALS`. Store the canonical `status.url`
origin from `gcloud run services describe`, without a path, as
`EVIDENCE_PROCESSOR_URL`. The deterministic URL printed by deployment did not
accept that URL as the ID-token audience during the E2 live check. Send credentials through stdin or a private
file; never put them in a shell argument, logs, screenshots, or the repository.
Do not configure production until the development request and readback pass.

The configured limit is a USD 10 monthly Cloud Run spend cap for `hadithlyapp`.
The cap sends alerts at 50%, 80%, and 100% of its target.
The service limit of one instance
also bounds concurrent scan cost. A spend cap pauses new Cloud Run use when it
triggers; in-flight requests and reporting delay can exceed the target.
Builds and image/source storage are outside this Cloud Run cap.

The rerunnable private-cloud check uses generated PNG/PDF fixtures and the
invoker credential from a private temporary file:

```sh
node verify_cloud.mjs "$E2_SERVICE_ORIGIN" "$E2_CREDENTIAL_FILE" "$E2_FIXTURE_DIRECTORY"
```

The check prints only assertion summaries. It verifies IAM rejection without
authentication, real OCR offsets, EICAR detection, malformed PDF rejection,
private destinations, and a checksummed public source snapshot.

From `backend/`, `node evidence_processor/verify_convex.mjs` exercises the
deployed development workflow with a disposable administrative test identity.
It verifies private extraction, coarse owner state, SSRF rejection, three manual
attempts, withdrawal, and preservation of existing rows. This CLI fixture does
not verify Clerk JWT sign-in. The opt-in native live tests verify that separately
using the actual authenticated clients and generated image/PDF uploads.

Check the deployed service with a synthetic PNG and EICAR request. Then submit
one disposable signed-in evidence item through Convex and read its owned state.
The expected sequence is `quarantined_unscanned`, `processing`, `ready` or
`infected`. The owner query must contain no scan signature, storage URL, or
extracted text. Withdraw the disposable item after the readback.

URL evidence retains the exact fetched bytes in private Convex storage. The
extraction record keeps the matching hash and offsets. Withdrawal, expiry, and
account deletion remove both. A late result deletes its unattached snapshot.
An item has at most three attempts. Failed attempts expose a manual Retry
action. Infection cancels sibling processing and removes the submission's bytes
and extracted text.

Convex holds one global worker lease and starts the next queued item as soon as
the current request finishes. Withdrawal keeps that lease until the discarded
result returns or its deadline expires. This prevents a three-item submission
from overrunning the one-slot service.
