import OpenIslandCore
import Testing
@testable import OpenIslandApp

struct OrbitContextEvidencePresentationTests {
    @Test
    func elevatedEvidenceReportsHeadroomSavingsCacheStrategyAndTruth() {
        let report = OrbitContextBudgeter.assess(
            segments: [
                OrbitContextSegment(provenanceID: "keep", kind: .system, estimatedTokens: 4_000, priority: 10),
                OrbitContextSegment(provenanceID: "omit", kind: .tool, estimatedTokens: 6_000),
            ],
            policy: OrbitContextBudgetPolicy(targetTokens: 8_000)
        )
        let evidence = OrbitContextEvidence(
            sessionID: "session",
            adapter: "codex",
            freshness: .fresh,
            confidence: .estimated,
            strategy: .losslessCompaction,
            contextWindowTokens: 12_000,
            cachedContextTokens: 3_000,
            budget: report
        )

        let presentation = OrbitContextEvidencePresentation.make(for: evidence)

        #expect(presentation.title == "Context filling · 17% headroom")
        #expect(presentation.detail == "6.0K saved · 30% cache · lossless compaction · estimated · fresh")
        #expect(presentation.pressure == .elevated)
    }

    @Test
    func unavailableEvidenceMakesNoSavingsOrCostClaimInTitle() {
        let report = OrbitContextBudgeter.assess(
            segments: [],
            policy: OrbitContextBudgetPolicy(targetTokens: 100)
        )
        let evidence = OrbitContextEvidence(
            sessionID: "session",
            adapter: "hermes",
            freshness: .unavailable,
            confidence: .unknown,
            strategy: .none,
            contextWindowTokens: 0,
            budget: report
        )

        let presentation = OrbitContextEvidencePresentation.make(for: evidence)

        #expect(presentation.title == "Context evidence unavailable")
        #expect(presentation.detail == "No current context measurement · unknown · unavailable")
        #expect(!presentation.detail.contains("saved"))
        #expect(!presentation.detail.contains("cache"))
        #expect(!presentation.title.contains("$"))
        #expect(presentation.pressure == .unavailable)
    }

    @Test
    func staleEvidenceDegradesInsteadOfShowingHealthyPressure() {
        let report = OrbitContextBudgeter.assess(
            segments: [OrbitContextSegment(provenanceID: "old", kind: .user, estimatedTokens: 10)],
            policy: OrbitContextBudgetPolicy(targetTokens: 100)
        )
        let evidence = OrbitContextEvidence(
            sessionID: "session",
            adapter: "codex",
            freshness: .stale,
            confidence: .estimated,
            strategy: .cachePrefixStabilization,
            contextWindowTokens: 100,
            budget: report
        )

        let presentation = OrbitContextEvidencePresentation.make(for: evidence)

        #expect(presentation.title == "Context evidence stale")
        #expect(presentation.pressure == .stale)
    }
}
