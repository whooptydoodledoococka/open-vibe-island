import Foundation
import OpenIslandCore
import Testing
@testable import OpenIslandApp

struct OrbitReceiptStatusPresentationTests {
    @Test
    func deliveredDoesNotClaimSourceAcknowledgement() {
        let presentation = OrbitReceiptStatusPresentation.make(
            for: receipt(status: .delivered)
        )

        #expect(presentation.title == "Allowed once · delivered")
        #expect(presentation.detail == "Source acknowledgement is still pending")
        #expect(presentation.tone == .pending)
    }

    @Test
    func acknowledgedNamesCorrelatedSourceConfirmation() {
        let presentation = OrbitReceiptStatusPresentation.make(
            for: receipt(status: .acknowledged)
        )

        #expect(presentation.title == "Allowed once · acknowledged")
        #expect(presentation.detail == "codex confirmed the correlated action")
        #expect(presentation.tone == .success)
    }

    @Test(arguments: [
        OrbitReceipt.Status.rejected,
        .expired,
        .disconnected,
        .deliveryFailed,
    ])
    func terminalFailureStatesRemainVisiblyFailClosed(_ status: OrbitReceipt.Status) {
        let presentation = OrbitReceiptStatusPresentation.make(for: receipt(status: status))

        #expect(presentation.tone == .failure)
        #expect(!presentation.title.contains("acknowledged"))
    }

    private func receipt(status: OrbitReceipt.Status) -> OrbitReceipt {
        OrbitReceipt(
            sessionID: "session",
            requestID: UUID(uuidString: "40000000-0000-0000-0000-000000000001"),
            adapter: "codex",
            action: .permissionAllowedOnce,
            scope: "Bash",
            status: status,
            summary: "permission decision captured"
        )
    }
}
