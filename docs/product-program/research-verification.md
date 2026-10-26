# B research verification

October 27, 2026. B's available-source review is complete. Continue C, then D,
before A4–A7. This record does not close a content, device or release gate.

## Checked evidence

- 34 distinct manifest video IDs and 26 original resource URLs are retained.
- All 34 complete available English caption tracks were read. Two are manual,
  32 automatic. Track coverage reaches the end or near the end of each video;
  uncaptained trailing speech is not assumed reviewed. Metadata duration totals
  about 16.3 hours. This is caption/frame review, not continuous playback.
- 110 selected actual frames are linked in the manifest and were visually
  inspected. Some podcast frames show only speakers or a waveform. They do not
  substantiate the described interface, revenue figures or causal effects.
- All 34 transcript SHA-256 values match their local evidence and review notes.
  Every manifest frame path resolves. Caption events and physical text lines
  are labeled separately because manual events can contain embedded line breaks.
- Resource statuses remain 7 reviewed, 12 partial and 7 blocked. Exact links,
  accessible alternatives and limitations appear in `research-resources.md`.
- Raw captions, transcripts and images are archived at
  `/Users/alim/Documents/Codex/2026-10-27/hadithly-product-research/`.
  Full captions and signed stream/caption metadata are excluded from git.
  The local archive is not public media hosting.

## Collector verification

`scripts/collect-product-research.py` was run against all 34 public videos.
The final rerun reused caption files and preserved all transcript fingerprints.
It never labels a collected video reviewed. Reading and visual inspection are
recorded separately in the review documents and manifest.

Independent review found three collector risks. A focused local failure/retry
probe verified their repairs against the actual imported collector:

1. A failed download leaves no accepted partial caption file. A subsequent
   successful call produces the complete timestamped transcript.
2. A previously damaged caption cache is discarded and retrieved again.
3. Frame extraction creates its folder in a fresh output directory.
4. Subprocess error output is reduced to type and exit code. Injected stderr
   containing a simulated signature is absent from emitted evidence.

The collector refreshes expired metadata, uses verified TLS, and keeps raw
evidence outside the checkout. An initial Python certificate-store failure was
resolved with macOS curl's system trust store. No TLS bypass or authenticated
cookie extraction was used. Temporary 429 responses were retried through the
ordinary public caption path. No Pi session, Gemini fallback or paid inference
was started. No external message, account change, tracking or publication occurred.

## Independent review and attention

Reviewed by GPT-6.1 Terra. It checked the exact hashes, source distinctions and
selected findings, and accepted the synthesis as hypotheses for bounded C.
Collector findings were repaired; the manifest and decision trail were then
completed. Caption-count labels were corrected.

The review used a different GPT model. The owner's GPT-only rule takes precedence
over the decision-log skill's request for a different model family, so this is
not a cross-family review. Partial and inaccessible resources, automatic-caption
accuracy, the small/uncontrolled source experiments and absent Hadithly cohort
data remain the material limits. The synthesis makes no uplift promise.
