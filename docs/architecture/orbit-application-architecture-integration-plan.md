# Orbit Application Architecture Integration Plan

## Goal

Deepen the existing native macOS application across four narrow modules without
adding a second daemon, reducer, status model, event pipeline, or package
dependency.

`SessionState.apply(_:)` remains the only session mutation reducer. `AppModel`
remains the application owner. `BridgeServer` remains the transport owner.
Socket I/O, payload decoding, process discovery, and terminal matching remain
adapters at the edges.

## Dependency order

1. **Phase A: Bridge lifecycle policy**
   Establish provider-neutral request correlation and fail-closed resolution
   before changing application projections.
2. **Phase B: AppModel application projection**
   Extract pure ranking and bucketing from the application owner while keeping
   selection, reconciliation, and collaborator ownership in `AppModel`.
3. **Phase C: Typed settings persistence adapter**
   Centralize the appearance-settings key domain, legacy fallback, validation,
   and explicit save outcomes. Keep setting changes initiated by `AppModel`.
4. **Phase D: Overlay transition policy**
   Extract delayed-callback freshness and timing constants. Keep task ownership
   in `OverlayUICoordinator`, placement in `OverlayPanelController`, and
   rendering in SwiftUI views.

Each phase is independently testable and rollbackable. No later phase is
allowed to become a hidden dependency of an earlier phase.

## Ownership table

| Concern | Owner | Interface/seam | Adapter boundary |
| --- | --- | --- | --- |
| Canonical session mutation | `SessionState.apply(_:)` | Existing reducer interface | None; all callers dispatch events |
| Application coordination | `AppModel` | Existing collaborator callbacks and pure projections | Discovery, monitoring, terminal, and transport collaborators |
| Transport and request response directives | `BridgeServer` | `BridgeLifecyclePolicy` correlation interface | Socket I/O and payload decoding |
| Lifecycle correlation safety | `BridgeLifecyclePolicy` | Typed pending-interaction and resolution-target values | No I/O, no session mutation |
| Session list ranking/bucketing | `ApplicationSessionProjection` | Pure `buckets(...)` function | AppModel supplies live attachment-key snapshot |
| Appearance settings persistence | `OrbitSettingsStore` | Typed snapshot plus `RuleSaveState` | `UserDefaults` or injected persistence failure |
| Overlay transition freshness | `OverlayTransitionPolicy` | Typed generation token | Coordinator owns `Task` and main-queue scheduling |
| Overlay placement | `OverlayPanelController` | Existing panel methods | AppKit screen/window APIs |
| Overlay rendering | SwiftUI island views | Existing observed state | SwiftUI rendering and animations |

## Phase A: Bridge lifecycle policy

### Files

- `Sources/OpenIslandCore/BridgeLifecyclePolicy.swift`
- `Sources/OpenIslandCore/BridgeServer.swift`
- `Tests/OpenIslandCoreTests/BridgeLifecyclePolicyTests.swift`

### Smallest coherent slice

Move request matching and resolution-target selection behind a provider-neutral
policy. The policy may correlate, normalize, and reject ambiguous input, but it
must not mutate `SessionState` or construct provider response directives.

Explicit request IDs must match session and interaction kind. Session-only
resolution is valid only for exactly one matching pending request. Missing,
stale, mismatched, duplicate, or ambiguous requests fail closed.

### Tests

- unique session/kind matching
- no-match rejection
- ambiguity rejection
- explicit request-ID mismatch rejection
- explicit request-ID success
- provider maps remain adapters and still receive the selected request ID

### Deletion test

Deleting `BridgeLifecyclePolicy.swift` should leave transport behavior
compilable only after restoring the old matching code. If deleting it requires
moving session mutation or response decoding, the seam is too deep.

### Rollback point

Revert the policy file, its focused tests, and the `BridgeServer` call-site
changes as one commit. No session reducer change is required.

## Phase B: AppModel application projection

### Files

- `Sources/OpenIslandApp/ApplicationSessionProjection.swift`
- `Sources/OpenIslandApp/AppModel.swift`
- `Tests/OpenIslandAppTests/ApplicationSessionProjectionTests.swift`

### Smallest coherent slice

Extract the pure ranking, visibility, live-attachment deduplication, primary
bucket, and overflow bucket calculation. `AppModel` remains responsible for
state ownership, monitoring lookup, selection, reconciliation, and publishing
the resulting surface state.

The projection receives a snapshot of live attachment keys rather than owning
process monitoring. This preserves locality and prevents a duplicate status
model.

### Tests

- ranking of live and attention-required sessions
- stable tie-breaking
- duplicate live attachment suppression
- overflow preservation
- subagent exclusion from rendered buckets
- stale-completed threshold behavior

### Deletion test

Deleting the projection must require only restoring the previous pure
`computeSessionBuckets()` implementation. It must not require moving selection,
reconciliation, or process monitoring into the projection.

### Rollback point

Revert the projection file, its tests, and the one AppModel delegation seam.
Keep the existing reducer and collaborator interfaces unchanged.

## Phase C: Typed settings persistence adapter

### Files

- `Sources/OpenIslandApp/OrbitSettingsStore.swift`
- `Sources/OpenIslandApp/AppModel.swift`
- `Tests/OpenIslandAppTests/OrbitSettingsStoreTests.swift`

### Smallest coherent slice

Centralize only appearance settings in a typed snapshot. The adapter owns the
key names, typed raw-value validation, legacy fallback, and explicit
`RuleSaveState` results. `AppModel` owns when a save is requested, applies the
new appearance values, and exposes the save state to the application surface.

The adapter supports injected persistence failure for deterministic tests and
keeps the existing `UserDefaults` keys for compatibility. Other settings
stores remain outside this phase.

### Tests

- typed load with defaults
- legacy-key fallback
- typed save/load round trip
- invalid raw values falling back safely
- injected save failure returning an explicit failure without write-through
- AppModel initialization does not persist during startup

### Deletion test

Deleting the adapter should require restoring only the old appearance key
access in AppModel. It must not affect admission rules, silence rules, session
state, or bridge transport.

### Rollback point

Revert the adapter, focused tests, and AppModel appearance persistence seam.
Preserve all unrelated settings work and user changes.

## Phase D: Overlay transition policy

### Files

- `Sources/OpenIslandApp/OverlayTransitionPolicy.swift`
- `Sources/OpenIslandApp/OverlayUICoordinator.swift`
- `Tests/OpenIslandAppTests/OverlayTransitionPolicyTests.swift`

### Smallest coherent slice

Replace the coordinator's raw generation counter with a typed transition token
and retain the existing delay values as named policy constants. Delayed pop,
boot-close, and deferred placement callbacks must verify token freshness before
mutating or presenting state.

The coordinator continues to own cancellation, `Task`, main-queue scheduling,
state mutation, and callback ordering. The policy owns neither UI state nor
AppKit placement.

### Tests

- first token is accepted
- a newer transition invalidates the prior token
- stale delayed callbacks cannot pass the policy
- existing pop and boot delay values remain unchanged

### Deletion test

Deleting the policy should require restoring the coordinator's prior generation
counter and named delays only. It must not require moving panel placement or
SwiftUI rendering into a new owner.

### Rollback point

Revert the policy file, focused tests, and coordinator token wiring. Existing
overlay state and placement APIs remain intact.

## Integration definition of done

- All four phases have one focused conventional commit in dependency order.
- No new package dependency, daemon, reducer, event pipeline, or duplicate
  status model exists.
- `SessionState.apply(_:)`, `AppModel`, and `BridgeServer` retain their stated
  ownership boundaries.
- Focused tests for each phase pass.
- A fresh Xcode 26.6 `swift build && swift test` passes.
- `git diff --check` passes.
- The complete diff is reviewed for unrelated changes, user changes, duplicate
  assets, credentials, and prohibited external publication.
- No app launch, dogfood, publication, push, PR, deploy, notarization, or
  release is implied unless separately requested.
- Final reporting distinguishes designed, implemented, tested, committed,
  dogfooded, and not-yet-verified states.
