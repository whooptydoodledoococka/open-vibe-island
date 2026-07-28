import Foundation
import Testing
@testable import OpenIslandCore

struct OrbitActionBindingTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)
    private let digest = String(repeating: "a", count: 64)

    @Test
    func exactBindingAuthorizesOnceThenRejectsReplay() throws {
        var ledger = OrbitActionAuthorizationLedger()
        let binding = makeBinding()

        try ledger.authorize(
            binding,
            expectedSessionID: binding.sessionID,
            expectedRequestID: binding.requestID,
            expectedAction: binding.action,
            expectedPayloadDigest: binding.payloadDigest,
            now: now
        ).get()

        #expect(ledger.consumedNonces == [binding.nonce])
        #expect(failure(of: ledger.authorize(
            binding,
            expectedSessionID: binding.sessionID,
            expectedRequestID: binding.requestID,
            expectedAction: binding.action,
            expectedPayloadDigest: binding.payloadDigest,
            now: now
        )) == .replay)
    }

    @Test
    func everyMismatchFailsClosedWithoutConsumingNonce() {
        let binding = makeBinding()
        let cases: [(String, String, String, String, OrbitActionAuthorizationError)] = [
            ("other-session", binding.requestID, binding.action, digest, .sessionMismatch),
            (binding.sessionID, "other-request", binding.action, digest, .requestMismatch),
            (binding.sessionID, binding.requestID, "deny", digest, .actionMismatch),
            (binding.sessionID, binding.requestID, binding.action, String(repeating: "b", count: 64), .digestMismatch),
        ]

        for (sessionID, requestID, action, expectedDigest, error) in cases {
            var ledger = OrbitActionAuthorizationLedger()
            #expect(failure(of: ledger.authorize(
                binding,
                expectedSessionID: sessionID,
                expectedRequestID: requestID,
                expectedAction: action,
                expectedPayloadDigest: expectedDigest,
                now: now
            )) == error)
            #expect(ledger.consumedNonces.isEmpty)
        }
    }

    @Test
    func expiredAndUnsafeBindingsFailClosed() {
        var ledger = OrbitActionAuthorizationLedger()
        let expired = makeBinding(expiresAt: now)
        #expect(failure(of: ledger.authorize(
            expired,
            expectedSessionID: expired.sessionID,
            expectedRequestID: expired.requestID,
            expectedAction: expired.action,
            expectedPayloadDigest: expired.payloadDigest,
            now: now
        )) == .expired)

        let unsafe = OrbitActionBinding(
            sessionID: "../private",
            requestID: "request-1",
            action: "approve",
            payloadDigest: digest,
            expiresAt: now.addingTimeInterval(30),
            nonce: "nonce-unsafe"
        )
        #expect(failure(of: ledger.authorize(
            unsafe,
            expectedSessionID: unsafe.sessionID,
            expectedRequestID: unsafe.requestID,
            expectedAction: unsafe.action,
            expectedPayloadDigest: unsafe.payloadDigest,
            now: now
        )) == .invalidIdentity)
        #expect(ledger.consumedNonces.isEmpty)
    }

    @Test
    func capacityFailsClosedUntilConsumedBindingExpires() throws {
        var ledger = OrbitActionAuthorizationLedger(maxEntries: 1)
        let first = makeBinding(nonce: "nonce-first", expiresAt: now.addingTimeInterval(10))
        let second = makeBinding(nonce: "nonce-second", expiresAt: now.addingTimeInterval(20))

        try ledger.authorize(
            first,
            expectedSessionID: first.sessionID,
            expectedRequestID: first.requestID,
            expectedAction: first.action,
            expectedPayloadDigest: first.payloadDigest,
            now: now
        ).get()
        #expect(failure(of: ledger.authorize(
            second,
            expectedSessionID: second.sessionID,
            expectedRequestID: second.requestID,
            expectedAction: second.action,
            expectedPayloadDigest: second.payloadDigest,
            now: now
        )) == .capacityExceeded)

        try ledger.authorize(
            second,
            expectedSessionID: second.sessionID,
            expectedRequestID: second.requestID,
            expectedAction: second.action,
            expectedPayloadDigest: second.payloadDigest,
            now: now.addingTimeInterval(11)
        ).get()
        #expect(ledger.consumedNonces == ["nonce-second"])
    }

    @Test
    func receiptTransitionsPreserveBindingEvidence() {
        let receipt = OrbitReceipt(
            sessionID: "session-1",
            requestID: UUID(uuidString: "10000000-0000-0000-0000-000000000001"),
            adapter: "hermes",
            action: .permissionAllowedOnce,
            scope: "approval",
            bindingDigest: digest,
            bindingNonce: "nonce-1",
            bindingExpiresAt: now.addingTimeInterval(30),
            status: .decisionCaptured,
            summary: "captured"
        )

        let delivered = receipt.with(status: .delivered)
        #expect(delivered.bindingDigest == digest)
        #expect(delivered.bindingNonce == "nonce-1")
        #expect(delivered.bindingExpiresAt == now.addingTimeInterval(30))
    }

    private func makeBinding(
        nonce: String = "nonce-1",
        expiresAt: Date? = nil
    ) -> OrbitActionBinding {
        OrbitActionBinding(
            sessionID: "session-1",
            requestID: "request-1",
            action: "approve",
            payloadDigest: digest,
            expiresAt: expiresAt ?? now.addingTimeInterval(30),
            nonce: nonce
        )
    }

    private func failure(
        of result: Result<Void, OrbitActionAuthorizationError>
    ) -> OrbitActionAuthorizationError? {
        guard case let .failure(error) = result else { return nil }
        return error
    }
}
