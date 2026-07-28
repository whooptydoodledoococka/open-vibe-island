# Orbit ship-readiness receipt — 2026-07-28

## Scope

This receipt covers the isolated integration branch `feat/orbit-ship-integration`
through its 2026-07-28 gate-clearance commit. It proves local source, build,
fixture, visual/accessibility-harness, bounded runtime behavior, local
development signing/install, paired companion build, and publication of this
GPL-3.0 feature branch to Austin's configured fork. It does not claim
Developer ID notarization, physical-device transport, release publication, or
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
- Companion actions support immutable session/request/action/digest/expiry/
  nonce binding. Exact bindings authorize once; replay, mismatch, expiry,
  unsafe identity, and unexpired-capacity pressure fail closed without
  consuming or replacing valid authorization state.
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
- Swift Testing: 463 tests in 57 suites, zero failures.
- `scripts/harness.sh smoke-all`: PASS for all 12 scenarios.
- Visual/AX evidence:
  `output/harness/smoke-all-20260728-171105`.
- Focused action, receipt, context, efficiency, restart, watchdog, loader,
  reduced-motion, and approval-inbox tests: PASS.
- Final closed-notch idle sample: 0.0% CPU;
  RSS 118,432 KiB (about 116 MiB), below the 2% CPU and 128 MiB
  acceptance budgets.
- Harness process exited cleanly and `OpenIslandApp` was `NOT_RUNNING`.
- Live loopback health check: Hermes WebUI `127.0.0.1:8787/health` and
  Hermes gateway `127.0.0.1:8642/health` both returned HTTP 200. Both
  `/api/sessions` probes returned HTTP 401 without credentials, correctly
  preserving the authentication gate; no cookies or tokens were read.
- Built executable SHA-256:
  `3f8c94d6de93af800e09596de5c108702850d931e90baebd053a09a6bd394718`.

## Changed artifact hashes

| Artifact | SHA-256 |
|---|---|
| `Sources/OpenIslandApp/AppModel.swift` | `a0f98ff620941b42e738114a637621ed4b497ea1487f3e3c30d9e15998214163` |
| `Sources/OpenIslandApp/OrbitReceiptStatusPresentation.swift` | `8c8630fff3d9923088997983f7a2b92516f1b9bd6a1332b410926f1422f02a0e` |
| `Sources/OpenIslandApp/OverlayTransitionPolicy.swift` | `8d338229104040a8c9e2d923ad8c2e4ebef18ccde9175a0ff7dc756f76d1327a` |
| `Sources/OpenIslandApp/OverlayUICoordinator.swift` | `b9476c46acea2577bdaf46a9cd551bc69e62526721028126ad8ee7330fdadbcf` |
| `Sources/OpenIslandApp/Views/IslandPanelView.swift` | `e87d85165241a50cf044b7341a58717a975d8597505d8a0e8a53aabb01872eb4` |
| `Sources/OpenIslandApp/Views/UnifiedBars.swift` | `0e285489c47131b0e77a405f5af92f713831e506f4fd36fb3480e5878b84657e` |
| `Sources/OpenIslandApp/Views/V6NotchContent.swift` | `0436f90843798f2a37ad054ad85ec11d33231c28a96a318061816024ce41f2ab` |
| `Sources/OpenIslandCore/OrbitExternalFeedLoader.swift` | `d5b95ac95b7f5abdee164ed92f2222431c95566f4623851b937f813586390e58` |
| `Sources/OpenIslandCore/OrbitExternalObservationRuntime.swift` | `15a6478828162037ffc4ab1bdbf779fc9ffc517e20ad282d3ee5e42cee07e36b` |
| `Sources/OpenIslandCore/OrbitReceipt.swift` | `2a09eac16ee2f5bfaa4cd4db74e7a6117bf31a958004bafdad4bf07ca9ae52eb` |
| `Sources/OpenIslandCore/OrbitActionBinding.swift` | `f9f824cb16f1dd6a3820897b372b7fb7c7e1d35d75ab43c5396f4fb1aa891c36` |
| `Sources/OpenIslandCore/HermesControlAdapter.swift` | `edd23d1c5109a3dabf9f49c8187eb7403d5b56391747fc8e088176418645c8ec` |
| `Tests/OpenIslandAppTests/AppModelSessionListTests.swift` | `c204f103091a8734a63760bead88de366c37964093f09d75db32ba771c75e808` |
| `Tests/OpenIslandAppTests/OverlayTransitionPolicyTests.swift` | `68ca2b9f4ed2461ae7379d7fc1bc35bf698e1f0f909a6360d5d1c6244011670c` |
| `Tests/OpenIslandAppTests/InstallHooksHintPolicyTests.swift` | `7f994e9e585621509a8a02f1d0a9207145a9a7a4d5066512c51021950ad39cdc` |
| `Tests/OpenIslandCoreTests/HermesGatewayAdapterTests.swift` | `c244d6492a1056203ef735d2d9db7e48bae6a6bf5a27efe1a21cbbf28ddde519` |
| `Tests/OpenIslandCoreTests/HermesControlAdapterTests.swift` | `52265c759a8ac9481b72cc2116bd914b759ced78deae2ce241683f33ec9a4c39` |
| `Tests/OpenIslandCoreTests/OrbitActionBindingTests.swift` | `d7fb55384ff0c076a7ec4b3ecf9a0cd48ecffea5c7eb5b83e95d8cbdeed506c8` |
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

## Gate-clearance update — 2026-07-28

- Xcode account readiness: a valid Austin Apple Development identity and Team
  ID `RL574WT5NJ` are available. The iPhone and Watch bundle identifiers are
  now `com.austinwise.orbit.mobile` and
  `com.austinwise.orbit.mobile.watchkitapp`.
- iPhone + Watch simulator build: PASS after correcting the Watch marketing
  icon slot. Both `OpenIslandMobile.app` and `OpenIslandWatch.app` were
  produced.
- Generic physical-device build with automatic provisioning: PASS. Physical
  installation and WatchConnectivity traversal still require the paired
  iPhone/Watch to be online and unlocked.
- Mac package: PASS from a non-FileProvider package root. The packager now
  strips copied extended attributes before signing and falls back to
  `hdiutil` when optional `create-dmg` is unavailable.
- Local development signature: PASS for the app and DMG with identifier
  `com.austinwise.orbit` and Team ID `RL574WT5NJ`. The signed app was
  installed at `/Applications/Orbit.app` and launched successfully.
- Regression: `scripts/harness.sh ci` PASS after these changes.
- Hermes authentication remains human-held: the opened WebUI rejected the
  attempted password. No credential, cookie, or token was read. Exact
  8642/8787 ID correlation remains HOLD until normal WebUI authentication.
- Notarization remains HOLD because Keychain contains Apple Development
  identities but no Developer ID Application identity or configured notary
  profile.
- Publication remains GPL-3.0-only and HOLD until the verified branch is
  committed and the configured fork destination is explicitly released.

| Gate-clearance artifact | SHA-256 |
|---|---|
| `ios/OpenIslandMobile.xcodeproj/project.pbxproj` | `f424e63db4db234d3586c1c3a1e5244ba229f5a9db86b15e6a76383b41bfbe6a` |
| `ios/OpenIslandWatch/Assets.xcassets/AppIcon.appiconset/Contents.json` | `5736c633bfb01f72a774684e2f0bc5f99319bd0396d95522cb897405358995e5` |
| `scripts/package-app.sh` | `10e25ec208a78be4f1d505a928b15f099e6ca9f80d55e017b9567015700b7500` |
| Signed local `Orbit.zip` | `727625613692fceb13284213f58857149f64c32af2c496929a82bc495f907382` |
| Signed local `Orbit.dmg` | `081a3e4230ff5dc66457b6cfe61fb155be18ce84ab8fa902b3161f4bbc3a55b5` |

## Rollback

The integration work is split into reversible commits:

1. `7d98ee8` enforce bound authorization in real AppModel delivery paths.
2. `3b41ec2` one-time bound action authorization and replay rejection.
3. `037075d` bounded Hermes control adapter and failure contracts.
4. `2d6f456` quiet first-run integration hint and Hermes failure tests.
5. `19886e2` truthful companion-action receipts.
6. `d251687` centralized snappy notch motion.
7. `4fc3080` docs-index repair.
8. `f939558` explicit observation restart.
9. `f1bfcfb` reduced-motion and approval accessibility.
10. `c8ead8e` bounded external-feed loader.

To remove one slice, create a new rollback branch from the current integration
head and use `git revert <commit>`, then rerun `scripts/harness.sh ci` and
`scripts/harness.sh smoke-all`. Do not reset or rewrite shared history.

## Disposition

LOCAL SHIP-READY for the verified Mac fixture/build boundary. External shipping
is not claimed until every HOLD row above has its required human evidence.
