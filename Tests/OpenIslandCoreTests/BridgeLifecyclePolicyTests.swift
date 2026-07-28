import Foundation
import Testing
@testable import OpenIslandCore

struct BridgeLifecyclePolicyTests {
    private let policy = BridgeLifecyclePolicy()
    private let sessionID = "session-1"

    @Test
    func sessionOnlyResolutionRequiresExactlyOneMatch() {
        let requestID = UUID()
        let pending = [
            BridgeLifecyclePolicy.PendingInteraction(
                requestID: requestID,
                sessionID: sessionID,
                kind: .permission
            )
        ]

        #expect(policy.resolutionTarget(
            sessionID: sessionID,
            kind: .permission,
            pending: pending
        ) == .unique(requestID))
    }

    @Test
    func sessionOnlyResolutionFailsClosedWhenAmbiguous() {
        let pending = [
            BridgeLifecyclePolicy.PendingInteraction(requestID: UUID(), sessionID: sessionID, kind: .permission),
            BridgeLifecyclePolicy.PendingInteraction(requestID: UUID(), sessionID: sessionID, kind: .permission)
        ]

        #expect(policy.resolutionTarget(
            sessionID: sessionID,
            kind: .permission,
            pending: pending
        ) == .ambiguous)
    }

    @Test
    func explicitResolutionRequiresMatchingSessionAndKind() {
        let requestID = UUID()
        let pending = [
            BridgeLifecyclePolicy.PendingInteraction(
                requestID: requestID,
                sessionID: sessionID,
                kind: .permission
            )
        ]

        #expect(policy.resolutionTarget(
            sessionID: sessionID,
            kind: .permission,
            explicitRequestID: requestID,
            pending: pending
        ) == .unique(requestID))
        #expect(policy.resolutionTarget(
            sessionID: "other-session",
            kind: .permission,
            explicitRequestID: requestID,
            pending: pending
        ) == .noMatch)
        #expect(policy.resolutionTarget(
            sessionID: sessionID,
            kind: .question,
            explicitRequestID: requestID,
            pending: pending
        ) == .noMatch)
    }

    @Test
    func unrelatedSessionsAndKindsDoNotBecomeCandidates() {
        let permissionID = UUID()
        let questionID = UUID()
        let pending = [
            BridgeLifecyclePolicy.PendingInteraction(requestID: permissionID, sessionID: sessionID, kind: .permission),
            BridgeLifecyclePolicy.PendingInteraction(requestID: questionID, sessionID: "other-session", kind: .question)
        ]

        #expect(policy.matchingRequestIDs(
            sessionID: sessionID,
            kind: .question,
            pending: pending
        ).isEmpty)
    }

    @Test
    func matchingRequestIDsPreservesAmbiguousCandidatesForCallerPolicy() {
        let first = UUID()
        let second = UUID()
        let pending = [
            BridgeLifecyclePolicy.PendingInteraction(requestID: first, sessionID: sessionID, kind: .question),
            BridgeLifecyclePolicy.PendingInteraction(requestID: second, sessionID: sessionID, kind: .question)
        ]

        #expect(policy.matchingRequestIDs(
            sessionID: sessionID,
            kind: .question,
            pending: pending
        ) == [first, second])
    }

    @Test
    func explicitResolutionFailsClosedForDuplicatePendingEntries() {
        let requestID = UUID()
        let pending = [
            BridgeLifecyclePolicy.PendingInteraction(
                requestID: requestID,
                sessionID: sessionID,
                kind: .permission
            ),
            BridgeLifecyclePolicy.PendingInteraction(
                requestID: requestID,
                sessionID: sessionID,
                kind: .permission
            )
        ]

        #expect(policy.resolutionTarget(
            sessionID: sessionID,
            kind: .permission,
            explicitRequestID: requestID,
            pending: pending
        ) == .noMatch)
    }
}
