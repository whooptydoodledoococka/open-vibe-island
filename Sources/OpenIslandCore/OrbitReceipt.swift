import Foundation

/// An immutable local record of a bounded action routed through an originating adapter.
/// Receipts intentionally contain metadata, not raw commands, prompts, paths, or secrets.
public struct OrbitReceipt: Codable, Equatable, Identifiable, Sendable {
    public enum Action: String, Codable, Sendable {
        case permissionDenied
        case permissionAllowedOnce
        case permissionAllowedWithUpdates
        case questionAnswered
        case sessionReplied
        case sessionSteered
        case sessionCancelled
    }

    public enum Status: String, Codable, Sendable {
        /// The user decision is bound to the request, but no delivery has begun.
        case decisionCaptured
        /// Orbit has started delivery to the originating adapter.
        case deliveryPending
        /// The bridge accepted the command for delivery; source acknowledgement is pending.
        case delivered
        /// The originating adapter explicitly confirmed the correlated decision.
        case acknowledged
        case rejected
        case expired
        case disconnected
        case deliveryFailed

        // Legacy values retained so previously encoded local receipts still decode.
        case queued
        case sent
        case failed

        public var isTerminal: Bool {
            switch self {
            case .acknowledged, .rejected, .expired, .disconnected, .deliveryFailed, .failed:
                true
            case .decisionCaptured, .deliveryPending, .delivered, .queued, .sent:
                false
            }
        }

        fileprivate func canTransition(to next: Status) -> Bool {
            if self == next {
                return true
            }
            if isTerminal {
                return false
            }

            return switch (self, next) {
            case (.decisionCaptured, .deliveryPending),
                 (.decisionCaptured, .delivered),
                 (.queued, .deliveryPending),
                 (.queued, .delivered),
                 (.queued, .sent),
                 (.deliveryPending, .delivered),
                 (.deliveryPending, .sent),
                 (.delivered, .acknowledged),
                 (.sent, .acknowledged):
                true
            case (_, .rejected), (_, .expired), (_, .disconnected),
                 (_, .deliveryFailed), (_, .failed):
                true
            default:
                false
            }
        }
    }

    public let id: UUID
    public let createdAt: Date
    public let sessionID: String
    public let requestID: UUID?
    public let providerCorrelationID: String?
    public let adapter: String
    public let action: Action
    public let scope: String
    public let bindingDigest: String?
    public let bindingNonce: String?
    public let bindingExpiresAt: Date?
    public let status: Status
    public let summary: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        sessionID: String,
        requestID: UUID? = nil,
        providerCorrelationID: String? = nil,
        adapter: String,
        action: Action,
        scope: String,
        bindingDigest: String? = nil,
        bindingNonce: String? = nil,
        bindingExpiresAt: Date? = nil,
        status: Status,
        summary: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sessionID = sessionID
        self.requestID = requestID
        self.providerCorrelationID = providerCorrelationID
        self.adapter = adapter
        self.action = action
        self.scope = scope
        self.bindingDigest = bindingDigest
        self.bindingNonce = bindingNonce
        self.bindingExpiresAt = bindingExpiresAt
        self.status = status
        self.summary = summary
    }

    public func with(status: Status) -> OrbitReceipt {
        OrbitReceipt(
            id: id,
            createdAt: createdAt,
            sessionID: sessionID,
            requestID: requestID,
            providerCorrelationID: providerCorrelationID,
            adapter: adapter,
            action: action,
            scope: scope,
            bindingDigest: bindingDigest,
            bindingNonce: bindingNonce,
            bindingExpiresAt: bindingExpiresAt,
            status: status,
            summary: summary
        )
    }
}

/// A bounded append-only receipt log for one Orbit process.
public struct OrbitReceiptLedger: Codable, Equatable, Sendable {
    public enum TransitionResult: Equatable, Sendable {
        case appended
        case unchanged
        case missingReceipt
        case invalidTransition
    }

    public private(set) var entries: [OrbitReceipt]
    public let maxEntries: Int

    public init(maxEntries: Int = 512) {
        self.entries = []
        self.maxEntries = max(1, maxEntries)
    }

    public mutating func append(_ receipt: OrbitReceipt) {
        entries.append(receipt)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    public func entry(id: UUID) -> OrbitReceipt? {
        entries.last { $0.id == id }
    }

    public func history(id: UUID) -> [OrbitReceipt] {
        entries.filter { $0.id == id }
    }

    @discardableResult
    public mutating func transition(id: UUID, to status: OrbitReceipt.Status) -> TransitionResult {
        guard let current = entry(id: id) else {
            return .missingReceipt
        }
        guard current.status != status else {
            return .unchanged
        }
        guard current.status.canTransition(to: status) else {
            return .invalidTransition
        }
        append(current.with(status: status))
        return .appended
    }
}
