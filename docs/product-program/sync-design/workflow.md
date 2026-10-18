# A2 architecture and verification workflow

- [x] Ground: source trace and red-capable actual-storage diagnostic.
- [x] Ground: independent native lifecycle and server acknowledgement traces.
- [x] Sketch / arena frame: compare complete state and receipt ownership.
- [x] Fan out: two structurally distinct sketches, isolated output files.
- [x] Cross-judge: independent scoring against data preservation, identity,
  eventual sync, bounded operation, interface depth and actual proof.
- [x] Pick and graft: record one coherent design and rejected alternatives.
- [x] Implement and verify the local server/native sync core as a bounded
  checkpoint. See `../../LIBRARY_SYNC_CORE_VERIFICATION.md`; it is not connected
  to production sign-in or signed-in writes yet.
- [ ] Implement: route both callers through the chosen production boundary;
  repair the red diagnostic through that boundary, not a lookalike helper.
- [ ] Verify: failure, newer edits, retries, missing/invalid targets, duplicate
  sign-in, account change, restart, folders, all facets and semantic positions.
- [ ] Scrap/redesign if repeated workarounds contradict the chosen ownership.
- [ ] Actual iOS-to-Android and Android-to-iOS private sync evidence.
- [ ] Review trail, retain unresolved gates, commit completed units, no push.
