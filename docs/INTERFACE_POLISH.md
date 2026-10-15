# Native interface polish

Owner scope, 2026-10-15. This is product polish, not L1 or release work.

## Acceptance checklist

- [x] Light has visibly distinct canvas, surface and elevated surface colors in both apps and reader sheets.
- [x] Skeletons cover initial content loads across Reader, Today, Library progress, Saved and remote Settings content, preserving existing data on refresh.
- [x] Actual AI requests show an animated, labeled waiting state and gently reveal completed text without inventing streamed tokens or backend stages.
- [x] Onboarding includes a prepared-example placeholder and polished reveal/step transitions without network generation or artificial waiting.
- [x] Collection numbers sit alongside names in Library grid/list and Today's shelf on both platforms.
- [x] Useful press, selection, expansion and content transitions share native motion conventions across the app.
- [x] Reduce Motion / animator scale zero disables repeating motion and keeps static status feedback.
- [x] Rendered Light, Dark and Paper, RTL, large text and loading-to-success/error paths are verified on both platforms.
- [x] Transitions Motion Agent hosted polish is run on a UI-only motion prototype, its changes reviewed and useful findings reflected in native components.
- [x] Implementation, verification, evidence and remaining gates are committed.

## Approach

Use existing SwiftUI and Compose components and semantic colors. Transitions.dev's
skeleton reveal and thinking-state references inform native timing and movement;
no web runtime or copied CSS library is added. Persistent labels carry state when
motion is disabled. Prepared onboarding examples remain clearly labeled and free.

Evidence and decisions are tracked in `verification/interface-polish-decisions.tsv`.
Existing device, sync, external-service, localization and release gates remain in
`OPEN_GATES.md`; this work does not close them.

Verification: [native results and screenshots](verification/NATIVE_INTERFACE_POLISH.md).
Runtime coverage is simulator/emulator scope; physical-device, full accessibility
traversal, live-service and native-speaker release gates remain open.
