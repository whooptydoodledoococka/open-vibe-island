import Foundation

/// Provider-neutral policy for correlating actionable lifecycle requests.
///
/// Provider adapters retain the payload needed to produce their response
/// directives. This module owns the shared safety decision: a session-only
/// resolution is accepted only when exactly one matching request exists, and
/// an explicit request ID must match both session and interaction kind.
public struct BridgeLifecyclePolicy: Sendable {
    public enum InteractionKind: String, Codable, Sendable {
        case permission
        case question
    }

    public struct PendingInteraction: Equatable, Sendable {
        public let requestID: UUID
        public let sessionID: String
        public let kind: InteractionKind

        public init(requestID: UUID, sessionID: String, kind: InteractionKind) {
            self.requestID = requestID
            self.sessionID = sessionID
            self.kind = kind
        }
    }

    public enum ResolutionTarget: Equatable, Sendable {
        case noMatch
        case unique(UUID)
        case ambiguous
    }

    public init() {}

    public func matchingRequestIDs(
        sessionID: String,
        kind: InteractionKind,
        pending: [PendingInteraction]
    ) -> [UUID] {
        pending.filter {
            $0.sessionID == sessionID && $0.kind == kind
        }.map(\.requestID)
    }

    public func resolutionTarget(
        sessionID: String,
        kind: InteractionKind,
        explicitRequestID: UUID? = nil,
        pending: [PendingInteraction]
    ) -> ResolutionTarget {
        let matching = matchingRequestIDs(
            sessionID: sessionID,
            kind: kind,
            pending: pending
        )

        if let explicitRequestID {
            guard matching.filter({ $0 == explicitRequestID }).count == 1 else {
                return .noMatch
            }
            return .unique(explicitRequestID)
        }

        switch matching.count {
        case 0:
            return .noMatch
        case 1:
            return .unique(matching[0])
        default:
            return .ambiguous
        }
    }
}
