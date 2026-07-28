import Foundation

/// Content-free, deterministic read model for Orbit's primary approval surface.
/// Provider payloads remain owned by their originating adapters and sessions.
public struct OrbitApprovalInboxProjection: Sendable {
    public enum RequestKind: String, Equatable, Sendable {
        case permission
        case question
    }

    public struct Item: Equatable, Sendable {
        public let sessionID: String
        public let requestID: UUID
        public let kind: RequestKind
        public let adapter: String
        public let stateVerb: String
        public let scope: String
        public let provenance: String
    }

    public struct Output: Equatable, Sendable {
        public let primary: Item?
        public let orderedItems: [Item]
        public let pendingCount: Int
        public let latestReceipt: OrbitReceipt?
    }

    private struct Candidate {
        let item: Item
        let focused: Bool
        let activityDate: Date
        let requestIndex: Int
    }

    public init() {}

    public static func project(
        sessions: [AgentSession],
        receipts: [OrbitReceipt],
        focusedSessionID: String?
    ) -> Output {
        var candidates: [Candidate] = []

        for session in sessions {
            for (index, request) in session.permissionRequests.enumerated() {
                let scope = request.toolName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let sanitizedScope = scope.flatMap { $0.isEmpty ? nil : $0 } ?? "Permission"
                candidates.append(Candidate(
                    item: Item(
                        sessionID: session.id,
                        requestID: request.id,
                        kind: .permission,
                        adapter: session.tool.rawValue,
                        stateVerb: "Approval required",
                        scope: sanitizedScope,
                        provenance: session.origin?.rawValue ?? "unknown"
                    ),
                    focused: session.id == focusedSessionID,
                    activityDate: session.updatedAt,
                    requestIndex: index
                ))
            }

            let questionOffset = session.permissionRequests.count
            for (index, prompt) in session.questionPrompts.enumerated() {
                candidates.append(Candidate(
                    item: Item(
                        sessionID: session.id,
                        requestID: prompt.id,
                        kind: .question,
                        adapter: session.tool.rawValue,
                        stateVerb: "Answer required",
                        scope: "Question",
                        provenance: session.origin?.rawValue ?? "unknown"
                    ),
                    focused: session.id == focusedSessionID,
                    activityDate: session.updatedAt,
                    requestIndex: questionOffset + index
                ))
            }
        }

        let orderedItems = candidates.sorted { lhs, rhs in
            if lhs.focused != rhs.focused {
                return lhs.focused
            }
            if lhs.item.kind != rhs.item.kind {
                return lhs.item.kind == .permission
            }
            if lhs.activityDate != rhs.activityDate {
                return lhs.activityDate < rhs.activityDate
            }
            if lhs.item.sessionID != rhs.item.sessionID {
                return lhs.item.sessionID < rhs.item.sessionID
            }
            if lhs.requestIndex != rhs.requestIndex {
                return lhs.requestIndex < rhs.requestIndex
            }
            return lhs.item.requestID.uuidString < rhs.item.requestID.uuidString
        }.map(\.item)

        return Output(
            primary: orderedItems.first,
            orderedItems: orderedItems,
            pendingCount: orderedItems.count,
            latestReceipt: receipts.last
        )
    }
}
