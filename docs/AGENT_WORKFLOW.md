# Working on Hadithly with coding agents

Agreed direction proposed October 31, 2026: a small Matt Pocock workflow with
selected pstack verification practices. Use Codex as the primary Hadithly agent.
Keep one writer and one active product unit. The owner has chosen Saved as the
first pilot. Finish the original product objective before the newer goals in
[POST_GOAL_BACKLOG.md](POST_GOAL_BACKLOG.md).

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

## Product order and later backlog

The owner's October 31 follow-up resumes Saved first. Complete that bounded unit,
then continue the original PRODUCT_PROGRAM.md objective and its final audit.
The newer goals and suggested preparation are recorded once in
[POST_GOAL_BACKLOG.md](POST_GOAL_BACKLOG.md). They come after the original objective.
An unavailable external gate remains open; finish other authorized original work
instead of treating a wait as permission to start the later backlog.

## Starting the next chat

Restart the clients so changed settings can load. No installation command is
needed. Paste the continuation prompt below. NEXT_SESSION_PROMPT.md contains
its exact Saved verification/staging checklist and the current owner order.

> Continue Hadithly using docs/NEXT_SESSION_PROMPT.md. Read the current checkpoint
> first. Resume the deferred Saved localization unit, verify both native apps,
> refresh evidence and commit. Preserve the incoming staged/unstaged work and all
> open gates. Use the bounded workflow; finish this unit and hand off the next
> original-program task. The continuing objective is to finish PRODUCT_PROGRAM.md,
> including unfinished A1/A3 acceptance, A4–A7/readiness, E and the final audit,
> before starting POST_GOAL_BACKLOG.md. Do not repeat completed B/C/D work or the
> workflow research. Keep GPT-only, no-Relay and action-time approval boundaries.
