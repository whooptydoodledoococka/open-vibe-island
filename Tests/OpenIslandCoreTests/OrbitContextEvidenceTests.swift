import Foundation
import Testing
@testable import OpenIslandCore

struct OrbitContextEvidenceTests {
    @Test
    func computesPressureHeadroomSavingsAndCacheEvidence() {
        let report = OrbitContextBudgeter.assess(
            segments: [
                OrbitContextSegment(provenanceID: "system", kind: .system, estimatedTokens: 4_000, priority: 10),
                OrbitContextSegment(provenanceID: "tool", kind: .tool, estimatedTokens: 6_000, priority: 1),
            ],
            policy: OrbitContextBudgetPolicy(targetTokens: 8_000)
        )
        let evidence = OrbitContextEvidence(
            sessionID: "session-1",
            adapter: "codex",
            model: "gpt-test",
            freshness: .fresh,
            confidence: .estimated,
            strategy: .losslessCompaction,
            contextWindowTokens: 12_000,
            cachedContextTokens: 3_000,
            budget: report,
            reversibleReferenceID: "blob_abc123"
        )

        #expect(evidence.pressure == .elevated)
        #expect(evidence.headroomPercent > 16 && evidence.headroomPercent < 17)
        #expect(evidence.savingsPercent == 60)
        #expect(evidence.cacheReadPercent == 30)
        #expect(evidence.reversibleReferenceID == "blob_abc123")
    }

    @Test(arguments: [
        "/private/context.json",
        "file://private/context.json",
        "../context",
        "two words",
        "C:\\context",
    ])
    func reversibleReferenceRejectsPathsURLsTraversalAndPayloads(_ value: String) {
        let evidence = fixture(reversibleReferenceID: value)

        #expect(evidence.reversibleReferenceID == nil)
    }

    @Test
    func redactionAndUnavailableStatesFailClosed() {
        let sensitive = OrbitContextSegment(
            provenanceID: "receipt",
            kind: .receipt,
            estimatedTokens: 100,
            containsSensitiveData: true
        )
        let report = OrbitContextBudgeter.assess(
            segments: [sensitive],
            policy: OrbitContextBudgetPolicy(targetTokens: 1_000)
        )

        let redaction = fixture(freshness: .fresh, budget: report)
        let unavailable = fixture(freshness: .unavailable, budget: report)

        #expect(redaction.pressure == .redactionRequired)
        #expect(unavailable.pressure == .unavailable)
    }

    @Test
    func identityAndProvenanceLabelsRejectPathsURLsAndPayloadText() {
        let report = OrbitContextBudgeter.assess(
            segments: [],
            policy: OrbitContextBudgetPolicy(targetTokens: 100)
        )
        let evidence = OrbitContextEvidence(
            sessionID: "/Users/private/session",
            taskID: "two words",
            adapter: "file://adapter",
            model: "provider/model",
            freshness: .fresh,
            confidence: .unknown,
            strategy: .none,
            contextWindowTokens: 100,
            budget: report
        )

        #expect(evidence.sessionID == "unknown-session")
        #expect(evidence.taskID == nil)
        #expect(evidence.adapter == "unknown-adapter")
        #expect(evidence.model == nil)
    }

    @Test
    func ledgerIsBoundedDeduplicatedAndSessionScoped() {
        var ledger = OrbitContextEvidenceLedger(maxEntries: 2)
        let first = fixture(id: UUID(uuidString: "60000000-0000-0000-0000-000000000001")!, sessionID: "one")
        let replacement = fixture(id: first.id, sessionID: "one", cachedContextTokens: 50)
        let second = fixture(id: UUID(uuidString: "60000000-0000-0000-0000-000000000002")!, sessionID: "two")
        let third = fixture(id: UUID(uuidString: "60000000-0000-0000-0000-000000000003")!, sessionID: "three")

        ledger.append(first)
        ledger.append(replacement)
        #expect(ledger.entries.count == 1)
        #expect(ledger.latest(sessionID: "one")?.cachedContextTokens == 50)

        ledger.append(second)
        ledger.append(third)
        #expect(ledger.entries.map(\.sessionID) == ["two", "three"])
        #expect(ledger.latest()?.sessionID == "three")
    }

    private func fixture(
        id: UUID = UUID(),
        sessionID: String = "session",
        freshness: OrbitContextEvidence.Freshness = .fresh,
        cachedContextTokens: Int = 0,
        budget: OrbitContextBudgetReport? = nil,
        reversibleReferenceID: String? = nil
    ) -> OrbitContextEvidence {
        let report = budget ?? OrbitContextBudgeter.assess(
            segments: [OrbitContextSegment(provenanceID: "fixture", kind: .user, estimatedTokens: 100)],
            policy: OrbitContextBudgetPolicy(targetTokens: 200)
        )
        return OrbitContextEvidence(
            id: id,
            sessionID: sessionID,
            adapter: "codex",
            freshness: freshness,
            confidence: .estimated,
            strategy: .cachePrefixStabilization,
            contextWindowTokens: 200,
            cachedContextTokens: cachedContextTokens,
            budget: report,
            reversibleReferenceID: reversibleReferenceID
        )
    }
}
