import Foundation

/// Metadata-only evidence describing context pressure and savings for one
/// adapter event. It never stores prompt, transcript, command, file, or tool
/// output contents.
public struct OrbitContextEvidence: Codable, Equatable, Identifiable, Sendable {
    public enum Freshness: String, Codable, Sendable {
        case fresh
        case stale
        case unavailable
    }

    public enum Confidence: String, Codable, Sendable {
        case exact
        case estimated
        case unknown
    }

    public enum Strategy: String, Codable, Sendable {
        case none
        case cachePrefixStabilization
        case losslessCompaction
        case reversibleRetrieval
    }

    public enum Pressure: String, Codable, Sendable {
        case healthy
        case elevated
        case critical
        case stale
        case redactionRequired
        case unavailable
    }

    public let id: UUID
    public let sessionID: String
    public let taskID: String?
    public let adapter: String
    public let model: String?
    public let observedAt: Date
    public let freshness: Freshness
    public let confidence: Confidence
    public let strategy: Strategy
    /// Model/provider context-window capacity used only for pressure/headroom.
    /// The budget report may intentionally use a smaller compaction target.
    public let contextWindowTokens: Int
    /// Cached tokens measured from the same context input represented by
    /// `budget.inputTokens`; callers must not mix provider-global counters.
    public let cachedContextTokens: Int
    public let cacheWriteTokens: Int
    public let budget: OrbitContextBudgetReport
    public let reversibleReferenceID: String?

    public init(
        id: UUID = UUID(),
        sessionID: String,
        taskID: String? = nil,
        adapter: String,
        model: String? = nil,
        observedAt: Date = .now,
        freshness: Freshness,
        confidence: Confidence,
        strategy: Strategy,
        contextWindowTokens: Int,
        cachedContextTokens: Int = 0,
        cacheWriteTokens: Int = 0,
        budget: OrbitContextBudgetReport,
        reversibleReferenceID: String? = nil
    ) {
        self.id = id
        self.sessionID = Self.boundedLabel(sessionID, fallback: "unknown-session")
        self.taskID = Self.optionalBoundedLabel(taskID)
        self.adapter = Self.boundedLabel(adapter, fallback: "unknown-adapter")
        self.model = Self.optionalBoundedLabel(model)
        self.observedAt = observedAt
        self.freshness = freshness
        self.confidence = confidence
        self.strategy = strategy
        self.contextWindowTokens = max(0, contextWindowTokens)
        self.cachedContextTokens = max(0, cachedContextTokens)
        self.cacheWriteTokens = max(0, cacheWriteTokens)
        self.budget = budget
        self.reversibleReferenceID = Self.safeReferenceID(reversibleReferenceID)
    }

    public var pressure: Pressure {
        guard freshness != .unavailable, contextWindowTokens > 0 else {
            return .unavailable
        }
        if freshness == .stale {
            return .stale
        }
        if budget.decision == .redactionRequired {
            return .redactionRequired
        }
        if budget.decision == .needsCompaction, usedFraction < 0.90 {
            return .elevated
        }

        switch usedFraction {
        case ..<0.70:
            return .healthy
        case ..<0.90:
            return .elevated
        default:
            return .critical
        }
    }

    public var usedFraction: Double {
        guard contextWindowTokens > 0 else { return 0 }
        return min(1, Double(budget.inputTokens) / Double(contextWindowTokens))
    }

    public var headroomPercent: Double {
        max(0, (1 - usedFraction) * 100)
    }

    public var savingsPercent: Double {
        budget.estimatedSavingsPercent
    }

    public var cacheReadPercent: Double {
        guard budget.inputTokens > 0 else { return 0 }
        return min(100, (Double(cachedContextTokens) / Double(budget.inputTokens)) * 100)
    }

    private static func boundedLabel(_ value: String, fallback: String) -> String {
        optionalBoundedLabel(value) ?? fallback
    }

    private static func optionalBoundedLabel(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercase = trimmed.lowercased()
        guard !trimmed.isEmpty,
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              !trimmed.contains(":"),
              !trimmed.contains(".."),
              !lowercase.contains("%2f"),
              !lowercase.contains("%5c"),
              !lowercase.contains("%3a"),
              !lowercase.hasPrefix("sk-"),
              !lowercase.contains("api_key"),
              !lowercase.contains("apikey"),
              !lowercase.contains("bearer"),
              !lowercase.contains("authorization"),
              !lowercase.contains("token="),
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              trimmed.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 127 }) else {
            return nil
        }
        return String(trimmed.prefix(128))
    }

    /// Reversible retrieval uses an opaque local identifier only. Paths, URLs,
    /// traversal components, and whitespace-delimited payloads fail closed.
    private static func safeReferenceID(_ value: String?) -> String? {
        guard let candidate = optionalBoundedLabel(value) else {
            return nil
        }
        return candidate
    }
}

/// Bounded process-local evidence ledger. Persistence, if enabled later, must
/// remain local, encrypted where appropriate, and separately retention-gated.
public struct OrbitContextEvidenceLedger: Codable, Equatable, Sendable {
    public private(set) var entries: [OrbitContextEvidence]
    public let maxEntries: Int

    public init(maxEntries: Int = 256) {
        self.entries = []
        self.maxEntries = max(1, maxEntries)
    }

    public mutating func append(_ evidence: OrbitContextEvidence) {
        entries.removeAll { $0.id == evidence.id }
        entries.append(evidence)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    public func latest(sessionID: String? = nil) -> OrbitContextEvidence? {
        guard let sessionID else { return entries.last }
        return entries.last { $0.sessionID == sessionID }
    }
}
