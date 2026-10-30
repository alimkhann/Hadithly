# Local agent setup audit

October 31, 2026. This audit covers local configuration, installed skill sources,
Claude plugin records, pi extensions and the tools advertised to this chat. It
does not claim remote-account, OAuth, connection-health or every-plugin-runtime
verification. No provider/model request, deployment, account change or publication
was used. Configuration changes apply to future sessions and affect other local
projects too. Repository rules remain in AGENTS.md.

## Recommendation and applied changes

Use Codex for Hadithly, 22 shared core skills, the existing native harnesses and
three small project skills. Keep other procedures installed but out of automatic
selection. Do not install a second complete pack or choose tools from video titles.

| Client | Before | Applied local change |
| --- | --- | --- |
| Codex `0.153.4` | 99 shared skill entries, 34 tracked to Matt and 44 to pstack; extra Codex/system/plugin skills also present | 77 shared entries disabled by path; 22 retained. Three extra overrides disable Relay, duplicate Nia and a broken Neon alias. This is not a claim that the total catalog contains only 22 skills. |
| Codex config | Hard-coded 1,000,000-token window and 900,000-token compaction threshold | Removed these overrides so model defaults apply. Model `gpt-6.1-sol`, effort `high`, permissions and service tier preserved. No claimed performance gain until a fresh-session measurement. |
| Codex MCPs | Eight enabled declarations, including Neon, Figma, GitHub and Vercel | Those four set disabled; Context7, Nia/apigcp, Playwright and the app-managed node runtime retained. GitHub can use existing `gh` for authorized work. No connection was opened for this audit. |
| Codex plugins | Redundant workflow and unrelated service plugins enabled | Superpowers, Canva, Vercel and Neon disabled in config. Existing native app/browser tooling, review and artifact plugins retained. No app was uninstalled or disconnected. |
| Claude Code `2.1.263` | Most shared skills aliased into its personal skill directory | 77 set to user-invocable-only through `skillOverrides`; Relay set off. Direct files were not mass-edited. The installed binary contains support for that setting. |
| Claude plugins | Superpowers, feature-dev, Caveman and marketing-skills active beside the skill copies | Those four disabled. Context7, TypeScript/Swift language tools, security-guidance, Playwright and CLAUDE.md management retained. |
| Relay | Claude global managed instructions, three autosave hook events, global MCP declaration, old Codex MCP file, OpenCode server and instruction pointer | Removed the managed block and Relay-only hooks/declarations/pointer; OpenCode Relay disabled. Claude denies Relay tool/skill use; Codex Relay was already disabled in TOML and remains so. No Relay service or memory was accessed. |
| OpenCode `1.18.35` | Context7, Relay, Vercel, mobile-mcp and XcodeBuildMCP enabled | Only Context7 remains enabled. The same 77 shared non-core procedures are denied to the skill loader. Existing agent definitions remain installed. |
| pi `0.84.4` | Separate learning-first policy, OpenCode bridge and plan-mode packages, many extensions | Preserved. Used only the existing video extension's free caption/frame implementation. Its configured default is `opencode/nemotron-3-ultra-free`, so it is not a Hadithly coding/model route under GPT-only rules. No model choice was changed. |
| Broken links | Neon aliases pointed at missing skill directories in Codex and OpenCode | Both broken symlinks removed with their targets recorded for rollback. No working Neon skill was deleted. |

The live tools in this already-running conversation were loaded before cleanup.
The current chat can still advertise a disabled service. A configured plugin name
also does not prove a working connection. Restart and inspect the next session's
catalog before claiming that loading has changed. Disabled files still occupy
disk space; the first target is less instruction overlap and fewer startup services.

Claude still has global Neon/mobile/Xcode MCP declarations for other projects.
They were inventoried but left configured. Hadithly's Claude project entry has
no additional MCP declarations. Claude remains an optional client, not a way to
evade the repo's model restriction. The Codex artifact/plugin skills are retained
for non-Hadithly document work and are not part of the 22-skill shared-core count.

## Sources and update policy

Owning repositories were fetched into temporary directories without executing
their installers. Current snapshots are Matt
`a496f5513d4a4cf889bc48e189e579f4b0bdf6aa` and pstack
`4dd1d05818d19792e7cd6e818f1667f95f7e1dbe`.

Seven reviewed SKILL.md files were refreshed:

- Matt: `diagnosing-bugs`, `code-review`, `research`.
- Pstack: `tdd`, `principle-prove-it-works`, `principle-fix-root-causes`,
  `principle-laziness-protocol`.

The Matt changes strengthen isolated review and verification of deliberate
failing-test mutations. The pstack changes simplify instructions and distinguish
legitimate-state handling from guards that conceal a fault. Reviewed updates are
small and introduce no executable installer or new provider. Existing referenced
support files remain available. The three principle leaves are dormant in the
catalog and can still be read directly as supporting reference.

This is a selective refresh, not a complete stack update. The original installer
lock is preserved; exact manual refresh hashes and source commits are recorded
in `verification/agent-workflow/upstream-review.json`. The full change manifest
stays in the private backup. A future bulk updater may
overwrite local invocation policy or bring back framework defaults. Inspect its
diff and dependencies before applying it. Use one installation route per agent,
as [Matt's README](https://github.com/mattpocock/skills/blob/a496f5513d4a4cf889bc48e189e579f4b0bdf6aa/README.md)
recommends. Do not add the same pack as a plugin beside editable copies.

Pstack's installed and current routers contain Cursor Task APIs, unavailable
plugin dependencies and non-GPT defaults. `setup-pstack` writes Cursor rules,
which are not Codex/Claude/OpenCode settings. Those routers remain dormant;
Hadithly's repo rule makes approved delegates inherit the current GPT model.
Osmani is reviewed as source material and not installed. The
[Osmani repository](https://github.com/addyosmani/agent-skills) also documents
shared-reference limitations with per-skill copies. Another full lifecycle stack
would duplicate the selected workflow.

## What stays available

Keep the native guidelines, diagnosis, relevant writing/type guidance, targeted
review and existing Clerk skills. The shared core is listed exhaustively in
`verification/agent-workflow/setup-summary.json`. Every installed skill and plugin
has a decision in the private backup's `skill-decisions.md`.
Other installed engineering skills remain recoverable. In Codex remove or enable
the relevant `[[skills.config]]` override before using a dormant skill. In Claude
use its slash command or change visibility through `/skills`. In OpenCode change
that skill's permission when it is deliberately selected.

Keep one Android guidelines skill as the default. `mobile-android-design` is
dormant because `android-design-guidelines` covers the current role. Keep
`better-interface` and its focused leaves available because the review uses them
by area. Retain useful files rather than uninstalling dependencies that a selected
procedure may read. Web/shadcn, writing-shape and exercise scaffolding remain
dormant until there is a matching task. Relay remains off.

## Commands and rollback

No installation command is required. Restart Codex, Claude and OpenCode to load
the profile. For an inventory without credentials, URLs or hook command bodies:

```sh
python3 scripts/audit-agent-setup.py --output /tmp/hadithly-agent-setup.json
```

Claude's `/skills` shows visibility, `/plugin` shows enabled plugins, and
`/skill-doctor` provides skill context/use information on supported sessions.
Those are user-facing inspection commands, not a request to run a second agent
against the product. No new package is needed.

Original local files and broken symlinks are backed up privately at
`~/.config/agent-workflow-backups/20261030T205435Z/`. The directory uses mode 0700;
regular backup files use 0600. It contains config data and must not be committed.
The directory name uses UTC; the review date is October 31 in Asia/Almaty.

To undo all local profile changes, after stopping clients:

```sh
python3 ~/.config/agent-workflow-backups/20261030T205435Z/restore.py
```

The restore refuses if any changed file has since drifted or a removed link path
has been reused. Resolve those files individually instead of overwriting newer
configuration. Reverting the repo commit alone does not revert the global profile.

## Evidence and practical limits

`setup-summary.json`, `upstream-review.json` and `checks.json` live under
`verification/agent-workflow/`. Full before/after inventories and the local
change manifest stay in the private backup, avoiding machine-specific catalog
dump files in the open-source repo. The read-only audit
script emits selected metadata, never whole configs, arguments, URLs, env values,
hook command bodies or OAuth/account records. Its synthetic credential-canary
check and actual configuration parsing are recorded in the verification artifact.

The settings mechanisms were checked against current
[Codex configuration documentation](https://developers.openai.com/codex/config-reference/),
[Claude skill visibility documentation](https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings)
and [OpenCode skill permissions](https://opencode.ai/docs/skills/#configure-permissions).
The [OpenAI guidance on skills](https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra)
also describes how overlapping descriptions consume context. These sources support
the configuration method, not a measured speed or quality improvement for Hadithly.

New project skills passed structural validation and their Claude aliases resolve.
Their first real pilot and new-session loading remain unverified. No native app
was built or tested because this unit changes workflow and tools only. All
incoming product bytes and the prior staged tree are checked separately before
the workflow-only commit. Saved, A4 and every existing external gate remain open.
