import Foundation

public struct OrbitActionBinding: Codable, Equatable, Sendable {
    public let sessionID: String
    public let requestID: String
    public let action: String
    public let payloadDigest: String
    public let expiresAt: Date
    public let nonce: String

    public init(
        sessionID: String,
        requestID: String,
        action: String,
        payloadDigest: String,
        expiresAt: Date,
        nonce: String
    ) {
        self.sessionID = sessionID
        self.requestID = requestID
        self.action = action
        self.payloadDigest = payloadDigest
        self.expiresAt = expiresAt
        self.nonce = nonce
    }
}

public enum OrbitActionAuthorizationError: Error, Codable, Equatable, Sendable {
    case invalidIdentity
    case expired
    case sessionMismatch
    case requestMismatch
    case actionMismatch
    case digestMismatch
    case replay
    case capacityExceeded
}

private struct OrbitConsumedActionNonce: Codable, Equatable, Sendable {
    let nonce: String
    let expiresAt: Date
}

/// One-time, fail-closed authorization for adapter-mediated actions.
///
/// It validates every immutable binding field before consuming the nonce.
/// Replay state is process-local, bounded, and contains no prompts, commands,
/// paths, credentials, or payloads.
public struct OrbitActionAuthorizationLedger: Codable, Equatable, Sendable {
    private var entries: [OrbitConsumedActionNonce]
    public let maxEntries: Int

    public var consumedNonces: [String] {
        entries.map(\.nonce)
    }

    public init(maxEntries: Int = 512) {
        self.entries = []
        self.maxEntries = max(1, maxEntries)
    }

    public mutating func authorize(
        _ binding: OrbitActionBinding,
        expectedSessionID: String,
        expectedRequestID: String,
        expectedAction: String,
        expectedPayloadDigest: String,
        now: Date = .now
    ) -> Result<Void, OrbitActionAuthorizationError> {
        guard Self.safeIdentifier(binding.sessionID),
              Self.safeIdentifier(binding.requestID),
              Self.safeIdentifier(binding.action),
              Self.safeNonce(binding.nonce),
              Self.safeDigest(binding.payloadDigest),
              Self.safeIdentifier(expectedSessionID),
              Self.safeIdentifier(expectedRequestID),
              Self.safeIdentifier(expectedAction),
              Self.safeDigest(expectedPayloadDigest) else {
            return .failure(.invalidIdentity)
        }
        guard now < binding.expiresAt else {
            return .failure(.expired)
        }
        guard binding.sessionID == expectedSessionID else {
            return .failure(.sessionMismatch)
        }
        guard binding.requestID == expectedRequestID else {
            return .failure(.requestMismatch)
        }
        guard binding.action == expectedAction else {
            return .failure(.actionMismatch)
        }
        guard binding.payloadDigest.lowercased() == expectedPayloadDigest.lowercased() else {
            return .failure(.digestMismatch)
        }
        entries.removeAll { $0.expiresAt <= now }
        guard !entries.contains(where: { $0.nonce == binding.nonce }) else {
            return .failure(.replay)
        }
        guard entries.count < maxEntries else {
            return .failure(.capacityExceeded)
        }

        entries.append(OrbitConsumedActionNonce(
            nonce: binding.nonce,
            expiresAt: binding.expiresAt
        ))
        return .success(())
    }

    private static func safeIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 256 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:"))
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func safeNonce(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && safeIdentifier(value)
    }

    private static func safeDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0)
        }
    }
}
