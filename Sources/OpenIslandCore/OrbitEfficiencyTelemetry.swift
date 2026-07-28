import CryptoKit
import Foundation

/// Privacy-safe efficiency evidence for one adapter/provider operation.
/// This type intentionally has no fields capable of storing prompts, commands,
/// paths, transcripts, credentials, or provider response contents.
public struct OrbitEfficiencyTelemetry: Codable, Equatable, Identifiable, Sendable {
    public enum Freshness: String, Codable, Sendable { case fresh, stale, unavailable }
    public enum Confidence: String, Codable, Sendable { case exact, estimated, unknown }

    public struct CostEstimate: Codable, Equatable, Sendable {
        public let amount: Double
        public let currency: String
        public let pricingVersion: String

        /// Cost is omitted unless all identifying pricing metadata is valid.
        public init?(amount: Double, currency: String?, pricingVersion: String?) {
            guard amount.isFinite, amount >= 0, amount <= 1_000_000_000,
                  let currency = Self.label(currency),
                  let pricingVersion = Self.label(pricingVersion) else { return nil }
            self.amount = amount
            self.currency = currency
            self.pricingVersion = pricingVersion
        }

        private static func label(_ value: String?) -> String? {
            guard let rawValue = value else { return nil }
            let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, normalized.count <= 32 else { return nil }
            let safe = normalized.unicodeScalars.allSatisfy { scalar in
                scalar.value < 128 && (scalar.isASCIIAlphaNumeric || scalar == "-" || scalar == "." || scalar == "_")
            }
            guard safe else { return nil }
            return normalized
        }
    }

    public let id: UUID
    public let sessionID: String
    public let taskID: String?
    public let adapter: String
    public let provider: String
    public let model: String?
    public let route: String
    public let observedAt: Date
    public let freshness: Freshness
    public let confidence: Confidence
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedInputTokens: Int
    public let cacheWriteTokens: Int
    public let retainedTokens: Int
    public let omittedTokens: Int
    public let toolCalls: Int
    public let latencyMilliseconds: Int
    public let approvalInterruptions: Int
    public let retries: Int
    public let failures: Int
    public let completionQualityEvidence: Int
    public let cost: CostEstimate?

    public init(
        id: UUID = UUID(), sessionID: String, taskID: String? = nil,
        adapter: String, provider: String, model: String? = nil, route: String,
        observedAt: Date = .now, freshness: Freshness, confidence: Confidence,
        inputTokens: Int = 0, outputTokens: Int = 0, cachedInputTokens: Int = 0,
        cacheWriteTokens: Int = 0, retainedTokens: Int = 0, omittedTokens: Int = 0,
        toolCalls: Int = 0, latencyMilliseconds: Int = 0,
        approvalInterruptions: Int = 0, retries: Int = 0, failures: Int = 0,
        completionQualityEvidence: Int = 0, cost: CostEstimate? = nil
    ) {
        self.id = id
        self.sessionID = Self.requiredLabel(sessionID, fallback: "unknown-session")
        self.taskID = Self.optionalLabel(taskID)
        self.adapter = Self.requiredLabel(adapter, fallback: "unknown-adapter")
        self.provider = Self.requiredLabel(provider, fallback: "unknown-provider")
        self.model = Self.optionalLabel(model)
        self.route = Self.requiredLabel(route, fallback: "unknown-route")
        self.observedAt = observedAt
        self.freshness = freshness
        self.confidence = confidence
        self.inputTokens = Self.boundedCounter(inputTokens)
        self.outputTokens = Self.boundedCounter(outputTokens)
        self.cachedInputTokens = Self.boundedCounter(cachedInputTokens)
        self.cacheWriteTokens = Self.boundedCounter(cacheWriteTokens)
        self.retainedTokens = Self.boundedCounter(retainedTokens)
        self.omittedTokens = Self.boundedCounter(omittedTokens)
        self.toolCalls = Self.boundedCounter(toolCalls)
        self.latencyMilliseconds = Self.boundedCounter(latencyMilliseconds)
        self.approvalInterruptions = Self.boundedCounter(approvalInterruptions)
        self.retries = Self.boundedCounter(retries)
        self.failures = Self.boundedCounter(failures)
        self.completionQualityEvidence = Self.boundedCounter(completionQualityEvidence)
        self.cost = cost
    }

    public var totalTokens: Int { inputTokens + outputTokens }

    fileprivate static func requiredLabel(_ value: String, fallback: String) -> String {
        optionalLabel(value) ?? fallback
    }

    fileprivate static func optionalLabel(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercase = trimmed.lowercased()
        guard !trimmed.isEmpty, trimmed.count <= 128,
              !trimmed.contains("/"), !trimmed.contains("\\"),
              !trimmed.contains("://"), !trimmed.contains(".."),
              !lowercase.contains("%2f"), !lowercase.contains("%5c"),
              !lowercase.contains("%3a"), !lowercase.hasPrefix("sk-"),
              !lowercase.contains("api_key"), !lowercase.contains("apikey"),
              !lowercase.contains("bearer"), !lowercase.contains("authorization"),
              !lowercase.contains("token="),
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              trimmed.unicodeScalars.allSatisfy({ scalar in
                  scalar.isASCIIAlphaNumeric || scalar == "-" || scalar == "." || scalar == "_" || scalar == ":"
              }) else { return nil }
        return trimmed
    }

    private static func boundedCounter(_ value: Int) -> Int {
        min(1_000_000_000_000, max(0, value))
    }
}

public struct OrbitEfficiencyAggregate: Codable, Equatable, Sendable {
    public let sessionID: String
    public let taskID: String?
    public let samples: Int
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedInputTokens: Int
    public let cacheWriteTokens: Int
    public let retainedTokens: Int
    public let omittedTokens: Int
    public let toolCalls: Int
    public let totalLatencyMilliseconds: Int
    public let averageLatencyMilliseconds: Int
    public let maxLatencyMilliseconds: Int
    public let approvalInterruptions: Int
    public let retries: Int
    public let failures: Int
    public let completionQualityEvidence: Int
    public let cost: OrbitEfficiencyTelemetry.CostEstimate?
    public let freshness: OrbitEfficiencyTelemetry.Freshness
    public let confidence: OrbitEfficiencyTelemetry.Confidence

    fileprivate init(sessionID: String, taskID: String?, samples: [OrbitEfficiencyTelemetry]) {
        self.sessionID = sessionID
        self.taskID = taskID
        self.samples = samples.count
        self.inputTokens = Self.saturatingSum(samples.map(\.inputTokens))
        self.outputTokens = Self.saturatingSum(samples.map(\.outputTokens))
        self.cachedInputTokens = Self.saturatingSum(samples.map(\.cachedInputTokens))
        self.cacheWriteTokens = Self.saturatingSum(samples.map(\.cacheWriteTokens))
        self.retainedTokens = Self.saturatingSum(samples.map(\.retainedTokens))
        self.omittedTokens = Self.saturatingSum(samples.map(\.omittedTokens))
        self.toolCalls = Self.saturatingSum(samples.map(\.toolCalls))
        self.totalLatencyMilliseconds = Self.saturatingSum(samples.map(\.latencyMilliseconds))
        self.averageLatencyMilliseconds = samples.isEmpty ? 0 : totalLatencyMilliseconds / samples.count
        self.maxLatencyMilliseconds = samples.map(\.latencyMilliseconds).max() ?? 0
        self.approvalInterruptions = Self.saturatingSum(samples.map(\.approvalInterruptions))
        self.retries = Self.saturatingSum(samples.map(\.retries))
        self.failures = Self.saturatingSum(samples.map(\.failures))
        self.completionQualityEvidence = Self.saturatingSum(samples.map(\.completionQualityEvidence))
        let costs = samples.compactMap(\.cost)
        let samePricing = costs.dropFirst().allSatisfy { $0.currency == costs.first?.currency && $0.pricingVersion == costs.first?.pricingVersion }
        self.cost = !samples.isEmpty && costs.count == samples.count && samePricing ? OrbitEfficiencyTelemetry.CostEstimate(
            amount: costs.reduce(0) { $0 + $1.amount }, currency: costs.first?.currency,
            pricingVersion: costs.first?.pricingVersion
        ) : nil
        self.freshness = samples.isEmpty || samples.contains { $0.freshness == .unavailable } ? .unavailable : (samples.contains { $0.freshness == .stale } ? .stale : .fresh)
        self.confidence = samples.isEmpty || samples.contains { $0.confidence == .unknown } ? .unknown : (samples.contains { $0.confidence == .estimated } ? .estimated : .exact)
    }

    private static func saturatingSum(_ values: [Int]) -> Int {
        values.reduce(0) { partial, value in
            let (sum, overflow) = partial.addingReportingOverflow(value)
            return overflow ? Int.max : sum
        }
    }
}

public struct OrbitEfficiencyRedactedExport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let sessionReference: String
    public let taskReference: String?
    public let samples: Int
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedInputTokens: Int
    public let cacheWriteTokens: Int
    public let retainedTokens: Int
    public let omittedTokens: Int
    public let toolCalls: Int
    public let totalLatencyMilliseconds: Int
    public let averageLatencyMilliseconds: Int
    public let maxLatencyMilliseconds: Int
    public let approvalInterruptions: Int
    public let retries: Int
    public let failures: Int
    public let completionQualityEvidence: Int
    public let cost: OrbitEfficiencyTelemetry.CostEstimate?
    public let freshness: OrbitEfficiencyTelemetry.Freshness
    public let confidence: OrbitEfficiencyTelemetry.Confidence

    fileprivate init(aggregate: OrbitEfficiencyAggregate) {
        self.schemaVersion = 1
        self.sessionReference = Self.reference(for: aggregate.sessionID)
        self.taskReference = aggregate.taskID.map(Self.reference(for:))
        self.samples = aggregate.samples
        self.inputTokens = aggregate.inputTokens
        self.outputTokens = aggregate.outputTokens
        self.cachedInputTokens = aggregate.cachedInputTokens
        self.cacheWriteTokens = aggregate.cacheWriteTokens
        self.retainedTokens = aggregate.retainedTokens
        self.omittedTokens = aggregate.omittedTokens
        self.toolCalls = aggregate.toolCalls
        self.totalLatencyMilliseconds = aggregate.totalLatencyMilliseconds
        self.averageLatencyMilliseconds = aggregate.averageLatencyMilliseconds
        self.maxLatencyMilliseconds = aggregate.maxLatencyMilliseconds
        self.approvalInterruptions = aggregate.approvalInterruptions
        self.retries = aggregate.retries
        self.failures = aggregate.failures
        self.completionQualityEvidence = aggregate.completionQualityEvidence
        self.cost = aggregate.cost
        self.freshness = aggregate.freshness
        self.confidence = aggregate.confidence
    }

    private static func reference(for value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

/// Bounded, in-memory retention for telemetry events.
public struct OrbitEfficiencyTelemetryLedger: Codable, Equatable, Sendable {
    public private(set) var entries: [OrbitEfficiencyTelemetry]
    public let maxEntries: Int

    public init(maxEntries: Int = 256) { self.entries = []; self.maxEntries = max(1, maxEntries) }

    public mutating func append(_ entry: OrbitEfficiencyTelemetry) {
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
    }

    public func aggregate(sessionID: String, taskID: String? = nil) -> OrbitEfficiencyAggregate {
        let safeSessionID = OrbitEfficiencyTelemetry.requiredLabel(sessionID, fallback: "unknown-session")
        let safeTaskID = OrbitEfficiencyTelemetry.optionalLabel(taskID)
        let matches = entries.filter { entry in
            entry.sessionID == safeSessionID && (safeTaskID == nil || entry.taskID == safeTaskID)
        }
        return OrbitEfficiencyAggregate(sessionID: safeSessionID, taskID: safeTaskID, samples: matches)
    }

    /// JSON contains only this contract's bounded, metadata-only aggregate.
    public func redactedExport(sessionID: String, taskID: String? = nil) throws -> Data {
        let export = OrbitEfficiencyRedactedExport(
            aggregate: aggregate(sessionID: sessionID, taskID: taskID)
        )
        return try JSONEncoder().encode(export)
    }
}

private extension Unicode.Scalar {
    var isASCIIAlphaNumeric: Bool { (value >= 48 && value <= 57) || (value >= 65 && value <= 90) || (value >= 97 && value <= 122) }
}
