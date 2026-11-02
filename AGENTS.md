# Hadithly

Native mobile apps for reading the hadith collections in your language.

**Start every session by reading `docs/PLAN.md`.** It holds the current gate,
the ordered session list, and the mistakes list. Start with its current checkpoint
and mistakes; open historical evidence when the task needs it. Read
`docs/NEXT_SESSION_PROMPT.md` and the linked prompt in `docs/SESSION_PROMPTS.md`
before changing files. The owner's current instruction overrides an older next task.

- `backend/`: Convex-only backend for data, providers, webhooks, and crons
- `ios/`: SwiftUI app for iOS 17+, built with xcodegen from `ios/project.yml`
- `android/`: Compose app for Android 8.0+ with minSdk 26
- `legacy/`: archived Expo and Next.js monorepo, for reference only
- `docs/`: master plan, dashboard checklist, reference audit, session prompts,
  repository/disk recovery, and launch-stack research

## Commands

```sh
# backend
cd backend && npm install
npx convex dev        # push to dev deployment + watch
npm run typecheck     # tsc --noEmit

# ios (regenerate project after adding files or changing project.yml)
cd ios && xcodegen generate
xcodebuild -project Hadithly.xcodeproj -scheme Hadithly \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build

# android (JDK 21; secrets in android/secrets.properties, see .example)
cd android
./gradlew assembleDebug        # build
./gradlew testDebugUnitTest    # unit tests
```

Run connected Android UI checks from the repository root with
`python3 scripts/run-android-ui-tests.py --serial emulator-5554 --class package.Class#method`.
The runner rejects physical targets and pins Gradle's serial. For physical-device
work, follow that session's device gate and select the device explicitly. Never
use an implicit all-devices run.

Reuse the installed iOS runtime and existing **iPhone 18 Pro** simulator, selected
explicitly. Do not download another runtime or create another simulator when the
existing one can run the check. The owner's one-time consolidation of duplicate
devices is recorded in `docs/POST_GOAL_BACKLOG.md`; preserve the retained device's
data and finish active tests before that cleanup.

## Non-negotiable rules

1. **No competition features.** No leaderboards, public votes or ratings,
   reputation, streaks, or badges. Translation quality comes from evidence,
   deterministic checks, AI review, and optional operator intervention for
   exceptions. Routine content decisions run automatically; the sole operator
   must not maintain a required approval queue. Reading progress stays private.
2. **Convex is the only mobile API and control plane.** Sunnah.now and Gemini
   are called exclusively from Convex actions; API keys live in Convex env
   vars. An immutable, checksummed offline artifact may be downloaded from a
   CDN URL and manifest authorized by Convex. No second app backend is allowed.
3. **Users never pass their own identity.** All user-scoped functions
   resolve the user from the verified Clerk JWT (`requireIdentity`).
4. **Secrets never enter git.** `backend/.env.local`, `ios/Secrets.xcconfig`,
   `android/secrets.properties` are gitignored; `.example` files document
   their shape.
5. **Rotate the Sunnah.now key before production.** It leaked historically.
   See `legacy/docs/implementation-notes.md`.

## Conventions

- Backend: TypeScript strict; user-facing mutations/queries in `convex/*.ts`,
  third-party calls in `convex/actions/*.ts` (files with `"use node"`).
  Return-type-annotate action handlers to avoid circular api inference.
- iOS: SwiftUI, `@Observable` state, feature folders under
  `ios/Hadithly/Features/`, design tokens in `Core/Theme/Theme.swift`.
  Regenerate the Xcode project with xcodegen. Never edit `project.pbxproj`.
- Android (Compose) mirrors the iOS feature folders under
  `android/app/src/main/kotlin/com/hadithly/app/`; design tokens in
  `core/theme/Theme.kt` must stay in sync with the iOS Theme.swift.
- Keep backend payloads platform-neutral. Implement and verify every new
  product behavior on both native apps unless the active session says that one
  platform is a no-change parity check.
- Use separate Codex tasks for delegated sessions. Do not use Relay for this
  repository.

## Session completion and commits

- Commit the finished session's implementation, verification, and documentation
  before the final handoff. Open device, external-service, or release gates do
  not prevent committing completed work; record those gates accurately in
  `docs/PLAN.md` and the verification record.
- Separate outstanding work from previous sessions into logical commits. Preserve
  unrelated changes, exclude secrets and build artifacts, and report commit hashes
  and remaining gates in the handoff. Push only when the user requests it.

## Working method

- Agree on one observable outcome, scope boundary, verification and stop point.
  Target a 30–45 minute unit. If it grows, checkpoint at the next safe boundary
  and split the remaining work. A timebox is a planning target, not a reason to
  abandon a running check or claim completion. Preserve the larger program.
- Use one primary agent by default. Delegate a named question or independent
  review when requested or required by an applicable skill. Keep writers and
  native device runs isolated. Review the resulting artifacts yourself.
- Use GPT-family models only for this repo. Keep the current approved model;
  delegates inherit it unless an available GPT alternative is justified. Skill
  defaults never authorize another provider or a paid-model action.
- Reproduce defects before changing behavior. For performance or cost work,
  measure the same journey before and after. A build, fixture or passing test
  cannot close a live-service, device or native-language approval gate.
- Prefer expressive names, types and assertions to narrating code comments.
  Keep comments for non-obvious reasons, external constraints and required
  notices. Review touched comments for accuracy; broad deletion is separate work.
- Ask at the action boundary for cloud, account, credential, paid-model,
  deployment, migration or publication changes. Local analysis and reversible
  edits proceed within the requested scope. Send no external messages by default.
- Use one relevant procedure at a time. Full poteto/pstack, Superpowers or Osmani
  pipelines are optional escalations, not automatic dependencies of ordinary work.

For broad product requests use `.agents/skills/hadithly-product-slice/SKILL.md`.
For one native UX journey use `.agents/skills/hadithly-native-review/SKILL.md`.
For Convex usage diagnosis use `.agents/skills/hadithly-convex-cost/SKILL.md`.
The human/agent agreement and current tool decisions are in `docs/AGENT_WORKFLOW.md`;
read it when choosing or changing the workflow, not at every implementation turn.
