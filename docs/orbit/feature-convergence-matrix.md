# Orbit Feature Convergence Matrix

## Purpose

Orbit is the private, local-first macOS control surface that converges the useful product capabilities previously explored across Open Island, Vibe Island, Headroom, and Codex-oriented work dashboards. It is not a literal merge of four codebases and it must not claim unsupported live evidence.

This matrix is the acceptance inventory for the current private development goal.

## Status vocabulary

- **Implemented**: present in production code and covered by tests or deterministic fixtures.
- **Partial**: a real implementation exists, but a required interaction, evidence source, or verification gate remains.
- **Missing**: requested capability has not been implemented.
- **Externally constrained**: Orbit cannot truthfully complete the capability without an authoritative upstream API or provider behavior.
- **Source unresolved**: the named prior source cannot be located; no feature claims may be invented for it.

## Converged capability inventory

| Capability | Source lineage | Status | Current Orbit evidence | Remaining acceptance gate |
| --- | --- | --- | --- | --- |
| Native notch/island shell | Open Island, Vibe Island | Implemented | `OpenIslandApp`, overlay coordinators, deterministic `closed` and `sessionList` scenarios | Final installed-bundle dogfood |
| Multi-agent session presence | Open Island, Vibe Island | Implemented | `AgentSession`, `SessionState`, session-list fixture | Final live provider sampling |
| Attention hierarchy | Orbit plan, Vibe Island | Implemented | approval/question before error, activity, completion, usage, idle | Add explicit error fixture |
| Permission approval cards | Open Island, Vibe Island | Implemented | UUID-correlated bridge commands, approval fixture, tests | Provider-by-provider final matrix |
| Question cards and answers | Open Island, Vibe Island | Implemented | request-targeted answers, question fixture | Provider-by-provider final matrix |
| Multiple requests in one session | Orbit safety work | Implemented | `Request n of N` navigator, keyboard-accessible controls, exact displayed-UUID callbacks, fixture, and AppModel regression | Final installed-bundle keyboard dogfood |
| Disconnect cleanup | Orbit safety work | Implemented | request-correlated `ActionableStateResolved`, focused regression test | Bridge-level timeout/disconnect integration test |
| Duplicate, conflict, mismatch, and ambiguity rejection | Orbit safety work | Partial | request/session checks and fail-closed legacy fallback | Complete focused contract test matrix |
| Request expiry and failed-delivery truth | Orbit safety work | Partial | hook socket timeout triggers correlated disconnect cleanup | Explicit expiry receipt and user-visible outcome |
| Completion cards | Open Island, Vibe Island | Implemented | completion and long-completion fixtures | Final installed-bundle dogfood |
| Immutable redacted decision receipts | Orbit plan | Implemented | `OrbitReceipt` and tests | Completion-proof drawer UI |
| Completion-proof drawer | Prior Orbit/Vibe Island outline | Missing | receipt model only | Searchable UI with proof/evidence labels |
| Jump back to originating work | Open Island, Vibe Island | Implemented | session jump targets and app activation paths | Accessibility and multi-display dogfood |
| Usage/context evidence | Headroom, Vibe Island | Partial | `OrbitContextBudget`; evidence is labeled live, inferred, stale, or unavailable | Surface context pressure consistently in list and detail views |
| Headroom compression/savings evidence | Headroom | Partial | evidence vocabulary and context-budget model exist | Authoritative local Headroom adapter; never invent savings |
| Hermes gateway health and session metadata | Hermes, Orbit | Implemented within boundary | loopback-only `HermesGatewayAdapter`; live/stale/unavailable fixture coverage | Authenticated session sampling only with runtime-injected user credential |
| Hermes approvals and completion truth | Hermes, Orbit | Externally constrained | UI explicitly labels both unavailable | Requires a documented authoritative Hermes event API |
| Truth-state chips | Prior convergence outline | Partial | Hermes evidence strip and context evidence vocabulary | Reusable chips across sessions, approvals, jobs, and receipts |
| Interrupted-work resume cards | Prior convergence outline | Missing | session persistence exists | Resume summary, blocker, next action, and jump control |
| Background-job and subagent shelf | Prior convergence outline | Missing | no unified shelf | Bounded job list with live/stale/unavailable truth labels |
| Quiet mode | Prior convergence outline | Partial | sound control exists | One explicit mode suppressing noncritical visual/audio interruptions |
| ADHD-friendly next-action footer | Prior convergence outline | Missing | no dedicated footer | One current action, blocker, and stopping condition |
| Error state | Orbit attention hierarchy | Partial | failed phases are represented | Deterministic fixture, visual QA, recovery action |
| Accessibility and reduced motion | Orbit plan, Open Island | Partial | labels, keyboard support, reduced-motion handling exist | Full WCAG-style macOS audit over every fixture |
| Orbit visual identity | Orbit | Implemented | Orbit surface style, icon, bundle display name | Final installed-bundle visual review |
| Local private packaging | Orbit | Implemented | `scripts/launch-dev-app.sh`, ad-hoc signed `Orbit Dev.app` | Rebuild from final commit and verify signature/process |
| Public release or GitHub workflow | None for current goal | Out of scope | both remote push URLs disabled | Only after explicit future authorization |
| Codexboard-specific capabilities | Codexboard | Source unresolved | no exact session, local project, file, or installed app found under this name | Locate the intended source or confirm its exact name before assigning features |

## Product rules

1. Orbit is one focused control surface, not a dashboard of dashboards.
2. Approval and question requests always outrank status and usage information.
3. Every displayed fact is labeled by evidence quality: live, inferred, stale, or unavailable.
4. Originating agents retain enforcement authority; Orbit brokers decisions only where the provider supports it.
5. Credentials are runtime-injected and never discovered, stored, printed, committed, or included in fixtures.
6. Deterministic fixtures prove rendering and state behavior, not live provider integration.
7. Development, packaging, and dogfooding remain local and private. Publication is not part of this goal.

## Completion sequence

1. Finish request lifecycle contract tests and explicit expiry outcomes.
2. Verify actionable queue count, navigation, and keyboard controls in the installed bundle.
3. Add error, resume, proof drawer, background-job shelf, truth chips, quiet mode, and next-action footer in coherent slices.
4. Run accessibility and reduced-motion review across every deterministic fixture.
5. Build, sign, launch, and dogfood the final local bundle.
6. Run full tests, all fixtures, docs, strings, privacy/security, licensing, and artifact checks.
7. Record a local completion receipt and rollback commit. Do not publish.
