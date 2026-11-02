# Owner-requested reader checkpoint

November 2, 2026. The owner reports that the installed reader has gotten much
better and requests preserving this exact version before further experiments.
This feedback confirms improvement; it does not close the stricter performance
or full behavior gates.

The local tag is `reader-smooth-owner-20261102`. The exact signed development app,
dSYMs, build manifest, full tracked iOS source snapshot and matched workload/frame
result are preserved outside temporary storage at:

`/Users/alim/Developer/Artifacts/Hadithly/reader-smooth-owner-20261102-1fb14968`

The signed app's SHA-256 is
`1fb14968656c962988b2203ed700037bb706df736b539df4371e671376be465d`.
The built iOS source digest is
`768003a403931e35ebd4ad0411a8e9ce483d254d3e61bd8a4ddc5c3e3ec1ad6f`.
The copied app passes strict signature verification and both digests match.
The snapshot contains the incoming project/scheme/catalog bytes used by the
build. Those unrelated changes remain uncommitted in the checkout. Ignored
secrets, signing keys and app account data are not part of the source snapshot.

This build includes quiet-period progress persistence, exact post-commit decoded
reuse and the bounded viewport tracking variant that was installed when the
owner reported improvement. The variant passes both reader UI checks. Its first
matched large-type slow run is 8.94 ms/s with 14 hitches, versus the initial
32.89–52.94 ms/s range. The target remains below 1 ms/s in every retained warm run.
The isolated geometry comparisons do not demonstrate an additional hitch benefit;
it is preserved here because the owner requested this exact installed version.

To return to the checkpoint, install its existing `Hadithly.app` bundle onto the
explicitly selected, authorized iPhone. Keep the existing app data. The archived
signed bundle allows returning without rebuilding or changing this worktree.
Development provisioning must remain valid; the archived source inputs and
existing local development configuration support rebuilding when necessary.
Do not reset the repository or overwrite unrelated changes to restore the app.

Continue the full goal from this checkpoint. Compare later experiments against
it, preserve appearance and semantic restoration, and retain it if an experiment
feels worse. Final acceptance still requires the complete performance matrix,
behavior checks and fresh owner confirmation on the final installed build.
