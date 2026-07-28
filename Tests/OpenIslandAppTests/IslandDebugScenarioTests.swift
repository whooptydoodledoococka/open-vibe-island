import Testing
@testable import OpenIslandApp

struct IslandDebugScenarioTests {
    @Test
    func allDebugScenarioSessionsAreDemoSessions() {
        for scenario in IslandDebugScenario.allCases {
            let snapshot = scenario.snapshot()
            #expect(snapshot.sessions.allSatisfy { $0.origin == .demo })
        }
    }

    @Test
    func deliveredReceiptScenarioNeverClaimsAcknowledgement() {
        let snapshot = IslandDebugScenario.receiptDelivered.snapshot()

        #expect(snapshot.receipts.count == 1)
        #expect(snapshot.receipts.first?.status == .delivered)
        #expect(snapshot.receipts.first?.status != .acknowledged)
        #expect(snapshot.islandSurface.sessionID == snapshot.receipts.first?.sessionID)
    }

    @Test
    func contextPressureScenarioIsMetadataOnlyAndSourceBound() {
        let snapshot = IslandDebugScenario.contextPressure.snapshot()
        let evidence = snapshot.contextEvidence.first

        #expect(snapshot.contextEvidence.count == 1)
        #expect(evidence?.sessionID == snapshot.selectedSessionID)
        #expect(evidence?.adapter == "codex")
        #expect(evidence?.confidence == .estimated)
        #expect(evidence?.freshness == .fresh)
        #expect(evidence?.reversibleReferenceID == "blob_demo_context")
    }
}
