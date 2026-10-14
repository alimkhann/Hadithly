# LA3 separate delivery-security and cost review

October 14, 2026. The user-requested independent GPT 6.1 Sol High review ran
after local implementation. Its final local scope passed with no remaining
blocking findings. The reviewer made no repository or external changes.

| Finding | Repair and evidence |
| --- | --- |
| P1 ordinary AI warning used ISO month while real spend uses UTC epoch-month key | Reservation and warning now share `monthlyGenerationSpendPolicy`. A real `quotas.admit` reservation crosses $7.98 to $8.00 and emits the correct warning, including malformed-config defaults. |
| P2 support inbox exposed only the oldest fifty requests | Bounded Convex pagination and a sixty-record identity/expiry check cover both pages without omissions. |
| P2 oversized multibyte packets could stay ready and block later reviews | UTF-8 byte limit is deterministic preflight before spend. A seventy-thousand-character Arabic fixture becomes privately held with no budget or provider-attempt record. |
| P2 reusable local restore could reuse a legacy anonymous-agent deployment | Script refuses the legacy directory before starting and verifies the new temporary project-local state/config before any synthetic writes or destructive import. The actual drill reran successfully. |
| Monthly warning dedup could expire on day thirty-one | Coarse budget notices retain thirty-two days. A day-thirty-one retention/recheck regression preserves one notice. |
| Contact limiter described as rolling although it is fixed-window | Operations text now describes the anchored twenty-four-hour contact window. Support/test notice retention is thirty days, budget notice retention thirty-two. |

The reviewer independently ran eighty focused support, quota, and evidence review
tests, backend typecheck, and diff whitespace checks. All passed. The root's full
suite and actual restore results are in `LA3_VERIFICATION.md` and
`LA3_RECOVERY_EVIDENCE.json`. The reviewer inspected the restore code/evidence but
did not repeat its destructive localhost drill.

Reviewed boundaries include fixed recipient and body, no visitor-controlled mail
headers or attachments, server challenge hostname/action, raw HMAC webhook bytes
and timestamp tolerance, permanent bounce/complaint suppression, at-most-once
claims and consumed unknown sends, atomic cost admission, and explicit external
gates. Provider documentation was refreshed independently for Resend limits,
Clerk MRU, and Convex backup exclusions and retention.

The review does not prove live support forwarding, inbox receipt, aligned domain
headers, published status, production backup operation, whole-provider spend
alarms, or physical accessibility. Marketing templates remain unsent designs.
L1 remains stopped.
