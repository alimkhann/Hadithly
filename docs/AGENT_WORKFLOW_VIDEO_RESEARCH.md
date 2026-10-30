# Agent workflow video research

Reviewed on October 31, 2026. This is workflow research. Saved completion and the
owner's product backlog remain deferred. No product behavior or release gate is
changed by this report.

## What was actually reviewed

All five complete available English-original automatic caption tracks were read.
Ten representative frames were inspected, two per video. This is a transcript
review with sampled visuals, not a claim to have watched every frame. Automatic
captions misrender names such as poteto, unslop and Osmani. Skill names below were
checked against installed files or their owning repositories.

The requested pi route exists at
`~/.pi/agent/extensions/video-extract/index.ts`. Its `transcript: true` branch
fetches YouTube captions through the installed `yt-dlp`, without an AI call. Its
frame branch uses `yt-dlp` and `ffmpeg`. The separate Gemini analysis path was
not invoked. No credential, browser cookie, paid model or installation was used.

The first broad English-caption request returned HTTP 429 for four videos. One
narrow `en-orig` retry succeeded for each. Frame extraction initially requested
an unavailable combined format for four videos. Selecting an available video
stream succeeded. These were retrieval limitations, not missing transcripts.

Captions, metadata and sampled frames were kept in temporary storage, not
committed. A reproducible caption command using the same route is:

```sh
yt-dlp --skip-download --write-subs --write-auto-subs \
  --sub-langs en-orig --sub-format vtt/srt/best \
  -o '/tmp/hadithly-workflow-%(id)s.%(ext)s' \
  'https://www.youtube.com/watch?v=M6mYodf0dJM'
```

## The five videos

### Matt Pocock's main workflow tutorial

[mattpocock/skills: A complete AI Coding workflow, end-to-end](https://www.youtube.com/watch?v=M6mYodf0dJM),
Matt Pocock, July 16, 2026, 17:17.

- [04:00](https://www.youtube.com/watch?v=M6mYodf0dJM&t=240s): mostly explicit invocation keeps the installed pack's context cost small in his demonstrated setup. This does not measure Hadithly's actual catalog cost.
- [04:35](https://www.youtube.com/watch?v=M6mYodf0dJM&t=275s): configure a tracker and domain documentation. Local Markdown is a valid tracker.
- [07:30](https://www.youtube.com/watch?v=M6mYodf0dJM&t=450s): align first, prototype empirical uncertainties, then implement directly when the work fits one session. Use a spec and tickets when it spans sessions.
- [12:30](https://www.youtube.com/watch?v=M6mYodf0dJM&t=750s): reject unnecessary ticket fragmentation. His CLI cleanup example collapses three proposed slices into one.
- [14:00](https://www.youtube.com/watch?v=M6mYodf0dJM&t=840s): start implementation with fresh context and one ticket, then compare the result against both requirements and coding standards.

Visual samples at 06:10 and 12:50 show domain-document setup and the proposed
CLI-removal breakdown. Adopt the small-ticket method. His approximate context
threshold is personal guidance, not a universal model limit.

### Matt Pocock's full workshop

[Full Walkthrough: Workflow for AI Coding](https://www.youtube.com/watch?v=-QFHIoCo-Ko),
AI Engineer, April 24, 2026, 1:36:30. The organizer also provides an
[official transcript and slide index](https://ai.engineer/talks/-QFHIoCo-Ko-ai-coding-workflow).

- [12:15](https://www.youtube.com/watch?v=-QFHIoCo-Ko&t=735s): resolve ambiguous requirements through questions before treating a plan as agreed.
- [39:30](https://www.youtube.com/watch?v=-QFHIoCo-Ko&t=2370s): a destination document and dependency-aware tickets serve different purposes.
- [42:00](https://www.youtube.com/watch?v=-QFHIoCo-Ko&t=2520s): prefer a thin path through the system over separate database, API and UI phases. His initial generated breakdown violates this, and he corrects it.
- [65:30](https://www.youtube.com/watch?v=-QFHIoCo-Ko&t=3930s): review in fresh context. [71:30](https://www.youtube.com/watch?v=-QFHIoCo-Ko&t=4290s): manual QA encounters a missing database table after automated checks passed.
- [74:00](https://www.youtube.com/watch?v=-QFHIoCo-Ko&t=4440s): design simple module interfaces that hide enough behavior to test meaningfully.
- [83:30](https://www.youtube.com/watch?v=-QFHIoCo-Ko&t=5010s): avoid letting completed plans become misleading current instructions.

The course-platform gamification example is incompatible with Hadithly's
no-competition rule. Borrow its slicing and feedback method only. Samples at
36:05 and 43:20 mainly show the stage; projected details are not readable enough
to independently validate the displayed code. His decision not to read generated
PRDs is his preference, not a recommendation for Hadithly's approval boundaries.

### Rob Shocks on pstack

[Pstack Is Agent Overkill. Use It Anyway!](https://www.youtube.com/watch?v=lUhXa8GiXns),
Rob Shocks, September 8, 2026, 12:57.

- [01:30](https://www.youtube.com/watch?v=lUhXa8GiXns&t=90s): poteto-mode routes work to procedures; arena compares rival solutions and swarm divides coverage.
- [03:35](https://www.youtube.com/watch?v=lUhXa8GiXns&t=215s): investigate decision evidence through available sources rather than infer intent from code alone.
- [06:05](https://www.youtube.com/watch?v=lUhXa8GiXns&t=365s): build repeatable application verification and maintain it as behavior changes.
- [08:30](https://www.youtube.com/watch?v=lUhXa8GiXns&t=510s): experiments can overturn an initial design.
- [11:15](https://www.youtube.com/watch?v=lUhXa8GiXns&t=675s): compilation and passing tests do not prove the real artifact works.
- [12:00](https://www.youtube.com/watch?v=lUhXa8GiXns&t=720s): his comparison took about twice as long with pstack and consumed more tokens. This is one demonstration, not a controlled quality benchmark.

At 06:25 the sample shows his Moltenbase skill manager and source/scope metadata.
The 02:25 sample is a presenter shot. Keep the verification discipline. Treat
large multi-model runs as an explicit escalation. His description of pstack as
having no planning is an interpretation; its router contains substantial design
and multi-phase procedures. The OpenRouter advertisement supplies no Hadithly
architecture recommendation.

### Eric Tech on pstack

[Pstack: How a Cursor Engineer Ships Code With AI](https://www.youtube.com/watch?v=4wBVuj2an8E),
Eric Tech, October 15, 2026, 14:56.

- [00:45](https://www.youtube.com/watch?v=4wBVuj2an8E&t=45s): use how/why/teach to understand an existing codebase.
- [02:15](https://www.youtube.com/watch?v=4wBVuj2an8E&t=135s): sketch interfaces before implementation; compare designs when the decision merits it.
- [04:40](https://www.youtube.com/watch?v=4wBVuj2an8E&t=280s): comments that contradict behavior can mislead agents.
- [05:35](https://www.youtube.com/watch?v=4wBVuj2an8E&t=335s): verification needs a launch procedure, realistic user interaction, evidence and cleanup.
- [12:30](https://www.youtube.com/watch?v=4wBVuj2an8E&t=750s): load relevant procedures when needed instead of putting every principle in the permanent prompt.
- [13:15](https://www.youtube.com/watch?v=4wBVuj2an8E&t=795s): revisit a failing assumption after repeated unsuccessful fixes.

The 02:30 diagram visibly connects architect, arena and interrogate. The 06:00
sample describes application-level verification. These are explanatory examples,
not native mobile performance measurements. Keep meaningful reasons and required
notices in comments; the stale-comment argument does not justify blanket deletion.
The social-media automation segment is unrelated to this repository.

### Rob Shocks compares the three packs

[Pocock vs Pstack vs Osmani: Which Skill Pack Wins?](https://www.youtube.com/watch?v=sU9MW8Ycq2M),
Rob Shocks, October 7, 2026, 12:54.

- [01:15](https://www.youtube.com/watch?v=sU9MW8Ycq2M&t=75s): presents Osmani's define, plan, build, verify, review and ship lifecycle.
- [05:10](https://www.youtube.com/watch?v=sU9MW8Ycq2M&t=310s): fresh-context adversarial review tests important claims during implementation.
- [06:15](https://www.youtube.com/watch?v=sU9MW8Ycq2M&t=375s): characterizes Pocock as alignment-focused, pstack as verification-focused and Osmani as lifecycle-focused. These are useful emphases, not exclusive capabilities.
- [09:00](https://www.youtube.com/watch?v=sU9MW8Ycq2M&t=540s): prune overlapping instructions and choose effort according to stakes. A visual tweak needs observation, not every planning and review ritual.
- [10:30](https://www.youtube.com/watch?v=sU9MW8Ycq2M&t=630s): introduce procedures gradually and retain evidence from actual use.

The 01:45 sample shows Pocock's alignment rationale. The 09:40 sample frames
skills as a personal working method. Adopt selective composition. Do not install
another complete pack to solve the existing overload. The Neon advertisement
does not override Convex as Hadithly's only backend and control plane.

## Cross-check against owning sources and installed files

Upstream HEADs were read on October 31. These identify the research snapshots,
not the versions currently installed on every host.

| Source | Snapshot | What it changes in the recommendation |
| --- | --- | --- |
| [Matt Pocock README](https://github.com/mattpocock/skills/blob/a496f5513d4a4cf889bc48e189e579f4b0bdf6aa/README.md) | `a496f5513d4a4cf889bc48e189e579f4b0bdf6aa` | Small composable procedures; choose one installation route per agent to avoid duplicate copies. The README distinguishes explicit workflow invocation from reusable model-invoked discipline. |
| [pstack router](https://github.com/cursor/plugins/blob/4dd1d05818d19792e7cd6e818f1667f95f7e1dbe/pstack/skills/poteto-mode/SKILL.md) | `4dd1d05818d19792e7cd6e818f1667f95f7e1dbe` | Use investigation, runtime proof and bounded procedures selectively. The complete router brings many dependencies and model assumptions. |
| [Osmani README](https://github.com/addyosmani/agent-skills/blob/eb07f19f52c2669f2364897aaa293e2aaddd7b1c/README.md) | `eb07f19f52c2669f2364897aaa293e2aaddd7b1c` | Established codebases can adopt verification first. Per-skill installation may omit shared reviewer/checklist material, so a small install still needs dependency inspection. |

Installed source inspection found the following under `~/.agents/skills`:

- Matt's `grill-with-docs`, `to-spec`, `to-tickets`, `implement`, `implement-spec`
  and `setup-matt-pocock-skills` already exist. A missing advertised skill entry
  in one chat is not proof that its file is absent. `grill-with-docs` calls
  `grilling` and `domain-modeling`. `implement` already combines agreed work,
  focused checks, review and commit. `to-tickets` requires approved scope and
  real dependency edges.
- `code-review` distinguishes standards from requirements. Its default diff
  covers committed HEAD changes. Hadithly's staged and unstaged Saved work needs
  an explicitly scoped worktree review; a clean committed diff would miss it.
- The installed `poteto-mode` defaults include Grok/Claude, Cursor-specific
  `Task` calls and `cursor-team-kit` dependencies. `setup-pstack` writes a Cursor
  rule. Those are not portable Codex configuration instructions. Hadithly's
  GPT-only, no-Relay and action-time approval rules take precedence.
- Installed `no-comments` invokes a specialized reviewer and can remove a
  constraint comment while reporting its rule unenforced. Do not import that
  behavior into this repository. Remove redundant narration in touched code;
  retain essential rationale, licensing and security constraints.

This file does not certify all cross-host versions, plugins or MCPs. That needs
the separate local configuration inventory.

## Recommended Hadithly method

Use a small Pocock-led workflow with selected pstack verification practices.
Keep one active product unit. Write its user-visible outcome, boundary, evidence
and stop point before implementation. Ask about unresolved product choices;
discover observable facts through code, experiments and existing evidence.

For a small repair, reproduce it, change the smallest relevant path, inspect the
real result on both native apps, review the scoped diff and commit. Use the
existing native harnesses rather than generating a competing verifier. For a
fuzzy interaction, compare a few inexpensive prototypes before implementation.
For larger work, record a short destination and independently verifiable tickets.
Use a fresh chat at a completed ticket boundary with a compact handoff. Do not
turn personal 100k/140k context estimates into a model guarantee.

Escalate to an independent review or competing design only when a specific risk
justifies its cost. Live cloud changes, provider calls and account operations
remain subject to Hadithly's existing approval rules. Multi-agent review does
not authorize multiple writers to shared catalogs or simulators.

Three small project procedures would serve the reported backlog better than a
third general-purpose pack: product discovery with native interaction examples;
reader diagnosis with repeatable timing and behavior evidence; and Convex usage
analysis with measured calls, payloads and subscription lifetimes. These are
workflow candidates, not authorization to implement the deferred features or
inspect live cloud/account state.

## Retrieval fingerprints

SHA-256 of the complete retrieved `en-orig` VTT files, for distinguishing this
caption snapshot from a later corrected track:

| Video | SHA-256 |
| --- | --- |
| `M6mYodf0dJM` | `cd0eb015b9a2d470595fd35d591dd1834f32465623fda2706dd417c9a892600c` |
| `-QFHIoCo-Ko` | `a464b86a1d5ece7e07553497bc1fff0ed0b6c463e4fe3d3cbe013e58a5bedace` |
| `lUhXa8GiXns` | `13266dd0e0cae09784a2ed2fea35438b46dbf3d1f2b5e4e609efe780169d5647` |
| `4wBVuj2an8E` | `73afd2839169e886ed4811a67538b3927b7131f203c7b5f7b82ddb35919b9dbd` |
| `sU9MW8Ycq2M` | `b7bdac9e77d4b9a859baca21afaba1c107bded764ef2481a0a3034dfc0414f41` |
