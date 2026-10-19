# A2 architecture and verification workflow

- [x] Ground: source trace and red-capable actual-storage diagnostic.
- [x] Ground: independent native lifecycle and server acknowledgement traces.
- [x] Sketch / arena frame: compare complete state and receipt ownership.
- [x] Fan out: two structurally distinct sketches, isolated output files.
- [x] Cross-judge: independent scoring against data preservation, identity,
  eventual sync, bounded operation, interface depth and actual proof.
- [x] Pick and graft: record one coherent design and rejected alternatives.
- [x] Implement and verify the local server/native sync core as a bounded
  checkpoint. See `../../LIBRARY_SYNC_CORE_VERIFICATION.md`.
- [x] Implement: route production sign-in and account library writes through the
  chosen boundary on both apps. Actual-facade local evidence is recorded in
  `../../LIBRARY_SYNC_INTEGRATION_VERIFICATION.md`.
- [x] Include current-owner local pending/recovery in portable export; local
  scope/content proof is in `../../LIBRARY_SYNC_EXPORT_VERIFICATION.md`.
- [ ] Finish account deletion/retry before A2 acceptance.
- [ ] Verify: failure, newer edits, retries, missing/invalid targets, duplicate
  sign-in, account change, restart, folders, all facets and semantic positions.
- [ ] Scrap/redesign if repeated workarounds contradict the chosen ownership.
- [ ] Actual iOS-to-Android and Android-to-iOS private sync evidence.
- [ ] Review trail, retain unresolved gates, commit completed units, no push.
