# Hosted Transitions Motion Agent review

2026-10-15. User authorized the free-plan license and hosted polish command.

- Official CLI: `transitions-agent@0.11.1`, from the author's npm package.
- Input: the two-file loading/reveal motion study in `motion-study/`. No backend,
  account data, private app content, environment files or credentials were input.
- Command: `npx --yes --package=transitions-agent@0.11.1 transitions-agent fix --yes --mode polish --dir <isolated study> --json`.
- Authentication: process environment only. The license is not in this repository.
- Service result: one CSS file changed; six duration findings fixed; study score
  94 to 100; the service reported **1/10 hosted fixes used this month**.
- A thinking-state recipe suggestion was outside free polish mode. No upgrade,
  revamp call, CI change, push or pull request was made.

The scanner accepts web source, not Swift/Kotlin. The score describes the study;
it is not a native-app verification result. The shipped native controls use the
same semantic timing roles and are tested separately.

## Applied and reviewed

The hosted fix moved press, reveal, shimmer and pulse durations onto named tokens.
Native `InterfaceMotion` constants now name quick interaction, page-step, content
reveal, repeating shimmer and thinking-pulse durations on both platforms. Logical
travel is converted to density-aware pixels on Android.

The generated CSS reused `--duration-slow` with both 400 ms and 2000 ms fallbacks.
That would change loop speed if the variable were later defined. The final study
keeps separate `--duration-loading-loop` and `--duration-thinking-pulse` tokens.
The native implementation likewise keeps 400 ms reveal, 2000 ms shimmer and
1500 ms pulse separate. We retained all reduced-motion guards.

Source guidance: [Transitions.dev skill](https://transitions.dev/skill.html),
[Motion Agent](https://transitions.dev/agent.html). No library CSS bundle is shipped
in either mobile app. This study is a review artifact, not an app backend or site.

## Missing native motion review

The skill was also used to match interaction gaps, beyond the scanner result.
Skeleton/reveal and thinking-state patterns informed pending content; accordion
and card-resize patterns informed Today and Saved expansion; page-step patterns
informed onboarding. Native system controls keep their platform transitions.
The review found and corrected a missing Android Today expansion. See the
[interaction mapping and native evidence](NATIVE_INTERFACE_POLISH.md).
