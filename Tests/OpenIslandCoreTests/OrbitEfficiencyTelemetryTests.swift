import Foundation
import Testing
@testable import OpenIslandCore

struct OrbitEfficiencyTelemetryTests {
    private let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    @Test
    func preservesSafeIdentityAndClampsCounters() {
        let value = OrbitEfficiencyTelemetry(
            id: id,
            sessionID: "session-one",
            adapter: "Codex",
            provider: "OpenAI",
            model: "GPT-5",
            route: "responses-api",
            freshness: .fresh,
            confidence: .exact,
            inputTokens: -1,
            latencyMilliseconds: -5
        )

        #expect(value.sessionID == "session-one")
        #expect(value.route == "responses-api")
        #expect(value.inputTokens == 0)
        #expect(value.latencyMilliseconds == 0)
        #expect(value.provider == "OpenAI")
    }

    @Test(arguments: [
        "/private/prompt",
        "file://private/prompt",
        "two words",
        "../prompt",
        "sk-secret",
        "token=secret",
    ])
    func unsafeIdentityLabelsFailClosed(_ sessionID: String) {
        let value = OrbitEfficiencyTelemetry(
            sessionID: sessionID,
            adapter: "codex",
            provider: "openai",
            route: "responses-api",
            freshness: .fresh,
            confidence: .exact
        )

        #expect(value.sessionID == "unknown-session")
    }

    @Test
    func aggregatesSessionAndTaskDeterministically() {
        var ledger = OrbitEfficiencyTelemetryLedger()
        ledger.append(sample(
            id: id,
            taskID: "task-one",
            input: 10,
            output: 4,
            latency: 10,
            cost: .init(amount: 0.25, currency: "USD", pricingVersion: "v1")
        ))
        ledger.append(sample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            taskID: "task-one",
            input: 5,
            output: 2,
            latency: 30,
            cost: .init(amount: 0.10, currency: "USD", pricingVersion: "v1")
        ))
        ledger.append(sample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            taskID: "task-two",
            input: 7,
            output: 1,
            latency: 20,
            cost: .init(amount: 0.05, currency: "USD", pricingVersion: "v1")
        ))

        let task = ledger.aggregate(sessionID: "session", taskID: "task-one")
        #expect(task.samples == 2)
        #expect(task.inputTokens == 15)
        #expect(task.outputTokens == 6)
        #expect(task.totalLatencyMilliseconds == 40)
        #expect(task.averageLatencyMilliseconds == 20)
        #expect(task.maxLatencyMilliseconds == 30)
        #expect(task.cost?.amount == 0.35)

        let session = ledger.aggregate(sessionID: "session")
        #expect(session.samples == 3)
        #expect(session.inputTokens == 22)
        #expect(abs((session.cost?.amount ?? 0) - 0.40) < 0.000_001)
    }

    @Test
    func emptyAndPartiallyPricedAggregatesFailClosed() {
        var ledger = OrbitEfficiencyTelemetryLedger()
        let empty = ledger.aggregate(sessionID: "missing")
        #expect(empty.samples == 0)
        #expect(empty.freshness == .unavailable)
        #expect(empty.confidence == .unknown)
        #expect(empty.cost == nil)

        ledger.append(sample(id: id, input: 5, cost: .init(amount: 0.10, currency: "USD", pricingVersion: "v1")))
        ledger.append(sample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            input: 5,
            cost: nil
        ))
        #expect(ledger.aggregate(sessionID: "session").cost == nil)
    }

    @Test
    func retentionIsBoundedAndDuplicateIDsReplace() {
        var ledger = OrbitEfficiencyTelemetryLedger(maxEntries: 2)
        ledger.append(sample(id: id, input: 1))
        ledger.append(sample(id: id, input: 9))
        ledger.append(sample(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, input: 2))
        ledger.append(sample(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, input: 3))

        #expect(ledger.entries.count == 2)
        #expect(ledger.entries.map(\.inputTokens) == [2, 3])
    }

    @Test
    func invalidCostFailsClosed() {
        #expect(OrbitEfficiencyTelemetry.CostEstimate(amount: .nan, currency: "USD", pricingVersion: "v1") == nil)
        #expect(OrbitEfficiencyTelemetry.CostEstimate(amount: 1, currency: nil, pricingVersion: "v1") == nil)
        #expect(OrbitEfficiencyTelemetry.CostEstimate(amount: 1, currency: "USD", pricingVersion: nil) == nil)
        #expect(OrbitEfficiencyTelemetry.CostEstimate(amount: 1, currency: "USD", pricingVersion: "v1") != nil)
    }

    @Test
    func redactedExportContainsOnlyBoundedMetadata() throws {
        var ledger = OrbitEfficiencyTelemetryLedger()
        ledger.append(sample(id: id, input: 7, output: 3, toolCalls: 2))

        let data = try ledger.redactedExport(sessionID: "session")
        let json = String(decoding: data, as: UTF8.self).lowercased()

        #expect(json.contains("inputtokens"))
        #expect(json.contains("toolcalls"))
        #expect(!json.contains("prompt"))
        #expect(!json.contains("command"))
        #expect(!json.contains("/private"))
        #expect(!json.contains("transcript"))
        #expect(!json.contains("secret"))
    }

    private func sample(
        id: UUID,
        taskID: String? = nil,
        input: Int = 0,
        output: Int = 0,
        toolCalls: Int = 0,
        latency: Int = 10,
        cost: OrbitEfficiencyTelemetry.CostEstimate? = nil
    ) -> OrbitEfficiencyTelemetry {
        OrbitEfficiencyTelemetry(
            id: id,
            sessionID: "session",
            taskID: taskID,
            adapter: "codex",
            provider: "openai",
            model: "gpt-5",
            route: "responses-api",
            freshness: .fresh,
            confidence: .exact,
            inputTokens: input,
            outputTokens: output,
            cachedInputTokens: 2,
            cacheWriteTokens: 1,
            retainedTokens: 4,
            omittedTokens: 1,
            toolCalls: toolCalls,
            latencyMilliseconds: latency,
            approvalInterruptions: 1,
            retries: 1,
            failures: 0,
            completionQualityEvidence: 1,
            cost: cost
        )
    }
}
