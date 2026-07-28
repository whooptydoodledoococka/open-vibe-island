import Foundation
import Testing
@testable import OpenIslandCore

struct OrbitReceiptTests {
    @Test
    func ledgerKeepsAppendOnlyStatusTransitionsWithinBound() {
        let receiptID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        var ledger = OrbitReceiptLedger(maxEntries: 2)
        let queued = OrbitReceipt(
            id: receiptID,
            createdAt: Date(timeIntervalSince1970: 1_000),
            sessionID: "session-1",
            requestID: receiptID,
            adapter: "codex",
            action: .permissionAllowedOnce,
            scope: "SettingsView.swift",
            status: .queued,
            summary: "permission decision queued"
        )

        ledger.append(queued)
        ledger.append(queued.with(status: .sent))
        ledger.append(
            OrbitReceipt(
                sessionID: "session-2",
                adapter: "claudeCode",
                action: .questionAnswered,
                scope: "question",
                status: .failed,
                summary: "question answer failed"
            )
        )

        #expect(ledger.entries.count == 2)
        #expect(ledger.entries[0] == queued.with(status: .sent))
        #expect(ledger.entries[1].status == .failed)
        #expect(ledger.entry(id: receiptID)?.status == .sent)
    }

    @Test
    func receiptRoundTripsWithoutChangingIdentityOrStatus() throws {
        let receipt = OrbitReceipt(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            createdAt: Date(timeIntervalSince1970: 2_000),
            sessionID: "session-1",
            requestID: nil,
            adapter: "codex",
            action: .permissionDenied,
            scope: "SettingsView.swift",
            status: .failed,
            summary: "permission decision failed"
        )

        let data = try JSONEncoder().encode(receipt)
        let decoded = try JSONDecoder().decode(OrbitReceipt.self, from: data)

        #expect(decoded == receipt)
        #expect(decoded.id == receipt.id)
        #expect(decoded.status == .failed)
    }

    @Test
    func latestEntryWinsAndProviderCorrelationSurvivesTransitions() {
        let receiptID = UUID(uuidString: "22222222-3333-4444-5555-666666666666")!
        var ledger = OrbitReceiptLedger()
        let captured = OrbitReceipt(
            id: receiptID,
            createdAt: Date(timeIntervalSince1970: 3_000),
            sessionID: "session-correlated",
            requestID: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001"),
            providerCorrelationID: "toolu_provider_123",
            adapter: "claudeCode",
            action: .permissionAllowedOnce,
            scope: "Bash",
            status: .decisionCaptured,
            summary: "permission decision captured"
        )

        ledger.append(captured)
        #expect(ledger.transition(id: receiptID, to: .deliveryPending) == .appended)
        #expect(ledger.transition(id: receiptID, to: .delivered) == .appended)

        let latest = ledger.entry(id: receiptID)
        #expect(latest?.status == .delivered)
        #expect(latest?.providerCorrelationID == "toolu_provider_123")
        #expect(latest?.requestID == captured.requestID)
        #expect(ledger.history(id: receiptID).map(\.status) == [
            .decisionCaptured,
            .deliveryPending,
            .delivered,
        ])
    }

    @Test
    func terminalReceiptTransitionsAreIdempotentAndFailClosed() {
        let receiptID = UUID(uuidString: "33333333-4444-5555-6666-777777777777")!
        var ledger = OrbitReceiptLedger()
        ledger.append(OrbitReceipt(
            id: receiptID,
            sessionID: "session-terminal",
            requestID: receiptID,
            adapter: "codex",
            action: .permissionDenied,
            scope: "shell",
            status: .decisionCaptured,
            summary: "denial captured"
        ))

        #expect(ledger.transition(id: receiptID, to: .delivered) == .appended)
        #expect(ledger.transition(id: receiptID, to: .acknowledged) == .appended)
        let countAfterAcknowledgement = ledger.entries.count
        #expect(ledger.transition(id: receiptID, to: .acknowledged) == .unchanged)
        #expect(ledger.entries.count == countAfterAcknowledgement)
        #expect(ledger.transition(id: receiptID, to: .rejected) == .invalidTransition)
        #expect(ledger.transition(id: UUID(), to: .disconnected) == .missingReceipt)
        #expect(ledger.entry(id: receiptID)?.status == .acknowledged)
    }

    @Test
    func expiryRejectionAndDisconnectAreDistinctTerminalStates() {
        for (index, status) in [
            OrbitReceipt.Status.expired,
            .rejected,
            .disconnected,
            .deliveryFailed,
        ].enumerated() {
            let receiptID = UUID(uuidString: String(format: "44444444-5555-6666-7777-%012d", index + 1))!
            var ledger = OrbitReceiptLedger()
            ledger.append(OrbitReceipt(
                id: receiptID,
                sessionID: "session-\(index)",
                adapter: "opencode",
                action: .questionAnswered,
                scope: "question",
                status: .decisionCaptured,
                summary: "decision captured"
            ))

            #expect(ledger.transition(id: receiptID, to: status) == .appended)
            #expect(ledger.entry(id: receiptID)?.status == status)
            #expect(status.isTerminal)
        }
    }
}
