# Working on Hadithly with coding agents

Agreed direction proposed October 31, 2026: a small Matt Pocock workflow with
selected pstack verification practices. Use Codex as the primary Hadithly agent.
Keep one writer and one active product unit. The owner can revise this method
before the first pilot. Saved completion and the reported product fixes remain
deferred during that discussion.

The five-video review, timestamps and source limitations are in
[AGENT_WORKFLOW_VIDEO_RESEARCH.md](AGENT_WORKFLOW_VIDEO_RESEARCH.md). The local
inventory, changes and rollback are in [AGENT_SETUP_AUDIT.md](AGENT_SETUP_AUDIT.md).

## The smallest useful loop

1. Describe the reader's problem. Separate what was observed from an explanation
   of its cause. Name the journey, platform and language.
2. Define one result, its boundaries, acceptance evidence and stop point. Use
   the product-slice skill for a broad request. A small defect needs a short
   contract, not a PRD and a ticket hierarchy.
3. Reproduce the symptom or measure the journey. Read only the code and older
   evidence needed to decide the next experiment. If the question is a product
   preference, ask the owner. If it is observable, investigate it.
4. Make the smallest repair, if implementation is authorized. Use a focused
   regression test when there is a cheap useful target. Inspect the actual native
   result. Performance and cost changes need the same before/after workload.
5. Review the intended requirements and repo standards against the exact changed
   files, including staged and unstaged portions. Use an independent reviewer
   for a named consequential risk, rather than a standing panel on every edit.
6. Commit the finished unit and update the checkpoint. Hand off the result,
   evidence, remaining uncertainty, next allowed task and open gates. Keep other
   incoming work intact. Start the next unit in a fresh chat when context is stale.

Use 30–45 minutes as a planning target for an implementation unit. Research may
need a different explicit boundary, such as reviewing the five supplied videos.
When repeated attempts stop producing evidence, checkpoint the observations and
reframe the diagnostic. Do not spend the rest of a long chat chasing adjacent
issues. Never stop a check halfway merely to meet an arbitrary clock limit.

## Our responsibilities

The owner supplies the desired experience, priorities, examples and decisions
that depend on taste or business policy. A concise screen recording, exact
locale, device and trigger sequence help when reporting a native problem. The
owner reviews visible UX and gives action-time approvals for external changes.
There is no need to dictate the internal implementation or write exhaustive specs.

The agent checks the current record, challenges unsupported assumptions, selects
the smallest useful experiment, implements within the agreed scope, and reports
actual evidence. It asks focused questions early when a decision blocks progress.
It continues authorized local work while optional questions are pending. It
checks its own and delegated changes before claiming completion.

Use names, types and tests to explain normal code. Keep a comment when it records
a reason the code cannot express, a vendor constraint or a required notice.
Remove stale narration in touched code. A comment-removal campaign can damage
unrelated reasoning and is not part of an ordinary bug fix.

External actions retain AGENTS.md's approval boundaries. A local setup cleanup
does not authorize provider calls, deployments, entitlement changes, remote
issues, publication or device work. GPT-only and no-Relay remain repo rules.

## Which procedures earn a place

| Situation | Default | Escalate when |
| --- | --- | --- |
| Small bug | Reproduce, diagnose, focused repair, real check | Root cause spans multiple owners or remains uncertain |
| Broad product request | `hadithly-product-slice` | Multiple independent units need a short destination/spec |
| Native design problem | `hadithly-native-review`, platform guidelines | A novel interaction merits a few cheap prototypes |
| Reader lag or paging | Existing diagnosis skill and native traces | One isolated question benefits from a separate investigator |
| Convex usage | `hadithly-convex-cost` | Measured evidence identifies a justified architecture change |
| Substantial change review | Requirements plus standards | Independent fresh-context review can disprove a specific risk |

The three project skills live in `.agents/skills`. Claude has relative aliases
under `.claude/skills`, and `CLAUDE.md` imports `AGENTS.md`. Their descriptions
permit normal automatic discovery. A skill's existence does not authorize its
backlog item. The existing native test harness remains the verification system.

Matt's diagnosis, module design, prototypes and review are useful small tools.
Pstack's real-artifact proof, root-cause discipline and small diffs are useful
habits. Its full poteto router, model panels and Cursor-specific dependencies
remain optional source material. Superpowers and Osmani overlap this workflow;
adding either full stack would create another coordinator rather than solve a gap.

For product discovery, [phuryn/pm-skills](https://github.com/phuryn/pm-skills)
offers interview, assumptions and prioritization procedures. It is a credible
candidate to inspect for a specific need, not a reason to install another entire
catalog. The three project skills cover the immediate gaps without bringing
generic growth/gamification or external-account workflows into Hadithly.

## Deferred backlog and proposed order

These are owner reports and proposals, not reproduced findings or authorization
to implement. The broader A1–A7/B/C/D/E program and every existing gate remain.

| Order proposal | Reported need | First bounded unit after authorization |
| --- | --- | --- |
| 1 | Convex usage is too high for one reader | Read-only baseline for cold launch, first reading and ten page moves; separate calls, reads, bytes and actions |
| 2 | Reader translation font size has no effect | Reproduce a size change and identify the actual text-style path on each app |
| 2 | Arabic → English leaves Settings RTL/upside down | Same-process reproduction through back navigation; distinguish direction, transition and persisted locale |
| 3 | iOS reader scrolling lags | Trace a repeatable collection, translation, text size and scroll sequence on the owner's device when authorized |
| 3 | Page swipes jerk and load too often | Measure page transition, cache behavior and visible position under the same workload |
| 4 | Free translation success is low | Classify failures by quota, attestation/auth, provider, exact-locale content and cache; no paid probes without approval |
| 4 | Need easy free/pro testing | Design an explicit development-only entitlement/test-account workflow that preserves production quota enforcement |
| 5 | Android UI feels poor and iOS-like | Audit one reading journey against Android conventions; preserve capability and meaning rather than matching layouts |
| 5 | Android localization is too verbose | Compare selected exact messages and wrapping with iOS; native review remains separate |
| 6 | Onboarding translation demo is too fast and poorly structured | Review a reader-in-daily-card prototype, pacing and reduced motion; distinguish demonstration from live AI generation |
| 6 | Auth spacing, sections and provider handoffs feel awkward | Map current native/hosted flows, then propose a simpler screen; verify vendor/platform requirements before removing browser handoffs |
| Later | Lightweight web reader | Revisit LA4's existing rights, demand, privacy, accessibility and cost gate; no implementation is authorized |
| Separate maintenance | Open-source repository quality | Audit README, contribution/security guidance, CI, licenses, content rights and artifact hygiene without publishing or changing license terms |

Saved is the already-started bounded unit and remains available to resume before
those proposals if the owner prefers. Its staged catalog patch, pending reruns
and stale aggregate evidence are preserved in NEXT_SESSION_PROMPT.md.

Logical additions to the backlog are a repeatable reader performance baseline,
a small language-switch regression matrix, a read-only cost budget per journey,
and an explicit development entitlement contract. These help verify the reported
problems. Do not add another observability vendor, task database or broad rewrite
before finding a measured gap in the existing tools.

## Starting the next chat

No install command is needed. Restart the agent clients so they load changed
settings, then use a prompt like this after choosing the pilot:

> Read the current Hadithly checkpoint and NEXT_SESSION_PROMPT. Diagnose only
> [one symptom] using [one journey]. First produce reproduction and the smallest
> evidence-backed repair proposal. Keep Saved and other backlog work deferred.
> Stop before implementation or any external action unless I authorize it.

When implementation is desired, replace the final sentence with the concrete
scope, acceptance check and commit requirement. Keep the next chat bounded by
that outcome, rather than asking it to continue the whole backlog indefinitely.
