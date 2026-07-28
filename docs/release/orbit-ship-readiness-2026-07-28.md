# Orbit ship-readiness receipt — 2026-07-28

## Scope

This receipt covers the isolated integration branch `feat/orbit-ship-integration`
at commit `037075d28a860b7521bde139d30ad1df28896e12`. It proves local source,
build, fixture, visual/accessibility-harness, and bounded runtime behavior. It
does not claim signing, notarization, device transport, publication, push, or
deployment.

## Product contract proved locally

- Native-notch surfaces show multi-agent state, context pressure/headroom,
  cache and compaction savings, usage evidence, external-feed freshness, and
  approval state.
- Approval, denial, question answer, reply, steer, and cancel attempts are
  capability scoped and receipt backed. Source acknowledgement is never
  inferred: terminal text delivery stops at `delivered`; unsupported cancel
  and stale steer fail closed as `rejected`.
- Hermes control uses Hermes's documented cookie-authenticated loopback
  contracts for pending approval, approval response, steer, cancel, and stream
  status. Remote URLs, invalid identity, stale 409, auth failure, malformed
  payloads, oversized responses, and rejected actions fail closed.
- OpenCode and FreeBuff input is explicit-file-only, bounded, regular-file-only,
  symlink resistant, and separate from the byte-only observation host.
- Observation has one owner, coalescing, bounded exponential backoff, watchdog
  expiry, degraded inspection-only mode, sticky emergency stop, and explicit
  restart that clears leases and old reports while preserving policy.
- Notch motion uses one token set: 200 ms expand, 140 ms collapse, 120 ms
  secondary feedback, 160 ms pop, high damping, and immediate Reduce Motion.
- Approval controls include explicit VoiceOver labels, hints, values, traits,
  and deterministic ordering.

## Verification

- `scripts/harness.sh ci`: PASS.
- XCTest: 24 executed, one intentional Ghostty integration skip, zero failures.
- Swift Testing: 458 tests in 56 suites, zero failures.
- `scripts/harness.sh smoke-all`: PASS for all 12 scenarios.
- Visual/AX evidence:
  `output/harness/smoke-all-20260728-163953`.
- Focused action, receipt, context, efficiency, restart, watchdog, loader,
  reduced-motion, and approval-inbox tests: PASS.
- Final closed-notch idle sample: 0.0–0.2% CPU;
  RSS 117,904–117,920 KiB (about 115 MiB), below the 2% CPU and 128 MiB
  acceptance budgets.
- Harness process exited cleanly and `OpenIslandApp` was `NOT_RUNNING`.
- Live loopback health check: Hermes WebUI `127.0.0.1:8787/health` and
  Hermes gateway `127.0.0.1:8642/health` both returned HTTP 200. Both
  `/api/sessions` probes returned HTTP 401 without credentials, correctly
  preserving the authentication gate; no cookies or tokens were read.
- Built executable SHA-256:
  `c053a059a1773be46224975af45268fea4c0d20f693611b0598177f489f51034`.

## Changed artifact hashes

| Artifact | SHA-256 |
|---|---|
| `Sources/OpenIslandApp/AppModel.swift` | `7dede1a3ed9a09720812047bb8b9b10b8e2513c0f93c991a6bd21fe1df35d48a` |
| `Sources/OpenIslandApp/OrbitReceiptStatusPresentation.swift` | `8c8630fff3d9923088997983f7a2b92516f1b9bd6a1332b410926f1422f02a0e` |
| `Sources/OpenIslandApp/OverlayTransitionPolicy.swift` | `8d338229104040a8c9e2d923ad8c2e4ebef18ccde9175a0ff7dc756f76d1327a` |
| `Sources/OpenIslandApp/OverlayUICoordinator.swift` | `b9476c46acea2577bdaf46a9cd551bc69e62526721028126ad8ee7330fdadbcf` |
| `Sources/OpenIslandApp/Views/IslandPanelView.swift` | `e87d85165241a50cf044b7341a58717a975d8597505d8a0e8a53aabb01872eb4` |
| `Sources/OpenIslandApp/Views/UnifiedBars.swift` | `0e285489c47131b0e77a405f5af92f713831e506f4fd36fb3480e5878b84657e` |
| `Sources/OpenIslandApp/Views/V6NotchContent.swift` | `0436f90843798f2a37ad054ad85ec11d33231c28a96a318061816024ce41f2ab` |
| `Sources/OpenIslandCore/OrbitExternalFeedLoader.swift` | `d5b95ac95b7f5abdee164ed92f2222431c95566f4623851b937f813586390e58` |
| `Sources/OpenIslandCore/OrbitExternalObservationRuntime.swift` | `15a6478828162037ffc4ab1bdbf779fc9ffc517e20ad282d3ee5e42cee07e36b` |
| `Sources/OpenIslandCore/OrbitReceipt.swift` | `ec992e9c251433583a4006d4dd8e98d7656791ed6d51d7e8a5c7f2da0f7c6c57` |
| `Sources/OpenIslandCore/HermesControlAdapter.swift` | `edd23d1c5109a3dabf9f49c8187eb7403d5b56391747fc8e088176418645c8ec` |
| `Tests/OpenIslandAppTests/AppModelSessionListTests.swift` | `c80a457d44c05575b5103bddc944a90a179d562398bbe03c9d0ad72f4565ae09` |
| `Tests/OpenIslandAppTests/OverlayTransitionPolicyTests.swift` | `68ca2b9f4ed2461ae7379d7fc1bc35bf698e1f0f909a6360d5d1c6244011670c` |
| `Tests/OpenIslandAppTests/InstallHooksHintPolicyTests.swift` | `7f994e9e585621509a8a02f1d0a9207145a9a7a4d5066512c51021950ad39cdc` |
| `Tests/OpenIslandCoreTests/HermesGatewayAdapterTests.swift` | `c244d6492a1056203ef735d2d9db7e48bae6a6bf5a27efe1a21cbbf28ddde519` |
| `Tests/OpenIslandCoreTests/HermesControlAdapterTests.swift` | `52265c759a8ac9481b72cc2116bd914b759ced78deae2ce241683f33ec9a4c39` |
| `Tests/OpenIslandCoreTests/OrbitExternalFeedLoaderTests.swift` | `680156e4e8a9ea6707388c4ebe8e9e53565fa70efd992d10733558c82c207a08` |
| `Tests/OpenIslandCoreTests/OrbitExternalObservationRuntimeTests.swift` | `48a9d7ecb8b6c5df4c0b2cf91f64fb1d079d5bda8692b785247d276cb18fdcf9` |

## Residual-risk matrix

| Risk | Current disposition | Required closure evidence |
|---|---|---|
| Live Codex/Hermes credentials and routing | HOLD | User-approved credentials, loopback ownership audit, live correlated receipt test |
| Native adapter cancellation | FAIL CLOSED | Adapter-specific bounded cancellation API plus acknowledgement fixture/live proof |
| Hermes live approval/completion parity | HOLD | Cookie-authenticated live proof that 8642 metadata IDs correlate exactly with 8787 control session/stream IDs |
| iPhone/Watch relay | HOLD | Signed-device pairing, stale/replay/mismatch and reconnect tests |
| Manual VoiceOver traversal | HOLD | Human AX traversal on the target Mac and recorded findings |
| Signing/notarization/install | HOLD | Developer ID/provisioning approval, Gatekeeper/notarization/install receipt |
| Publication/push/deployment | HOLD | License confirmation and explicit destination/action approval |

## Rollback

The integration work is split into reversible commits:

1. `037075d` bounded Hermes control adapter and failure contracts.
2. `2d6f456` quiet first-run integration hint and Hermes failure tests.
3. `19886e2` truthful companion-action receipts.
4. `d251687` centralized snappy notch motion.
5. `4fc3080` docs-index repair.
6. `f939558` explicit observation restart.
7. `f1bfcfb` reduced-motion and approval accessibility.
8. `c8ead8e` bounded external-feed loader.

To remove one slice, create a new rollback branch from the current integration
head and use `git revert <commit>`, then rerun `scripts/harness.sh ci` and
`scripts/harness.sh smoke-all`. Do not reset or rewrite shared history.

## Disposition

LOCAL SHIP-READY for the verified Mac fixture/build boundary. External shipping
is not claimed until every HOLD row above has its required human evidence.
