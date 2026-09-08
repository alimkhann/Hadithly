# Post-launch planning handoff

The planning audit described by the former prompt was completed on 2026-09-02.
Do not run another broad rewrite before executing the dashboard gate.

Start here:

1. Read `AGENTS.md` and `docs/PLAN.md`.
2. Run D0 from `docs/SESSION_PROMPTS.md`.
3. Keep live dashboard evidence in `docs/LAUNCH_DASHBOARD_CHECKLIST.md`.
4. If D0 is blocked only by missing task-tool injection, follow its recovery
   steps; G0 and M0 may document recovery state but D1 must not begin.
5. Use `docs/REPOSITORY_AND_DISK_PLAYBOOK.md` for checkpoint and storage work.
6. Use `docs/LAUNCH_STACK_RESEARCH.md` for cost, observability, analytics,
   email, landing, status, and deferred web-reader choices.
7. Consult `docs/REFERENCE_AUDIT.md` when a session changes product behavior.

GLM-5.3-Flash through OpenCode Go is the default author for the bounded
sessions assigned to it in the plan. Do not silently move those sessions back
to Sol. Use the named Terra or Sol review gate only for the listed risks.

If the user requests a later plan audit, preserve completed session evidence and
rewrite only the unstarted portion. Reinspect changed code and reference images
before changing a locked product decision.
