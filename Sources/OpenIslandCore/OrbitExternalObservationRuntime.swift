import Foundation

public struct OrbitExternalObservationRuntimePolicy: Codable, Equatable, Sendable {
    public let baseBackoffSeconds: TimeInterval
    public let maxBackoffSeconds: TimeInterval
    public let watchdogSeconds: TimeInterval
    public let degradedFailureThreshold: Int

    public init(
        baseBackoffSeconds: TimeInterval = 1,
        maxBackoffSeconds: TimeInterval = 60,
        watchdogSeconds: TimeInterval = 5,
        degradedFailureThreshold: Int = 3
    ) {
        self.baseBackoffSeconds = max(0.1, baseBackoffSeconds)
        self.maxBackoffSeconds = max(self.baseBackoffSeconds, maxBackoffSeconds)
        self.watchdogSeconds = max(0.1, watchdogSeconds)
        self.degradedFailureThreshold = max(1, degradedFailureThreshold)
    }
}

public struct OrbitExternalObservationRuntimeState: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case healthy
        case degradedInspectionOnly
        case stopped
    }

    public enum Admission: Equatable, Sendable {
        case admitted
        case coalesced
        case backoff(until: Date)
        case rejectedOwnerConflict
        case stopped
    }

    public private(set) var ownerID: String?
    public private(set) var mode: Mode
    public private(set) var consecutiveFailures: Int
    public private(set) var nextAllowedAt: Date?
    public private(set) var inFlightStartedAt: Date?
    public private(set) var lastSuccessAt: Date?

    public init() {
        self.ownerID = nil
        self.mode = .healthy
        self.consecutiveFailures = 0
        self.nextAllowedAt = nil
        self.inFlightStartedAt = nil
        self.lastSuccessAt = nil
    }

    public mutating func begin(
        ownerID candidateOwnerID: String,
        now: Date,
        policy: OrbitExternalObservationRuntimePolicy
    ) -> Admission {
        guard let safeOwnerID = Self.safeOwnerID(candidateOwnerID) else {
            return .rejectedOwnerConflict
        }
        if mode == .stopped { return .stopped }
        if let ownerID, ownerID != safeOwnerID { return .rejectedOwnerConflict }
        if inFlightStartedAt != nil { return .coalesced }
        if let nextAllowedAt, now < nextAllowedAt { return .backoff(until: nextAllowedAt) }

        ownerID = safeOwnerID
        inFlightStartedAt = now
        return .admitted
    }

    public mutating func recordSuccess(now: Date) {
        guard mode != .stopped else { return }
        inFlightStartedAt = nil
        consecutiveFailures = 0
        nextAllowedAt = nil
        lastSuccessAt = now
        mode = .healthy
    }

    public mutating func recordFailure(
        now: Date,
        policy: OrbitExternalObservationRuntimePolicy
    ) {
        guard mode != .stopped else { return }
        inFlightStartedAt = nil
        let (incrementedFailures, overflowed) = consecutiveFailures.addingReportingOverflow(1)
        consecutiveFailures = overflowed ? Int.max : incrementedFailures
        let exponent = min(20, max(0, consecutiveFailures - 1))
        let delay = min(
            policy.maxBackoffSeconds,
            policy.baseBackoffSeconds * pow(2, Double(exponent))
        )
        nextAllowedAt = now.addingTimeInterval(delay)
        if consecutiveFailures >= policy.degradedFailureThreshold {
            mode = .degradedInspectionOnly
        }
    }

    @discardableResult
    public mutating func expireWatchdogIfNeeded(
        now: Date,
        policy: OrbitExternalObservationRuntimePolicy
    ) -> Bool {
        guard let inFlightStartedAt,
              now.timeIntervalSince(inFlightStartedAt) >= policy.watchdogSeconds else {
            return false
        }
        recordFailure(now: now, policy: policy)
        return true
    }

    public mutating func cancelInFlight() {
        inFlightStartedAt = nil
    }

    public mutating func emergencyStop() {
        mode = .stopped
        inFlightStartedAt = nil
        nextAllowedAt = nil
    }

    /// Explicitly starts a new observation-runtime generation after an emergency stop.
    /// Runtime ownership, work, backoff, and success history do not cross generations.
    public mutating func restartAfterEmergencyStop() {
        self = OrbitExternalObservationRuntimeState()
    }

    private static func safeOwnerID(_ value: String) -> String? {
        guard !value.isEmpty, value.count <= 128,
              value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return nil
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return value.unicodeScalars.allSatisfy(allowed.contains) ? value : nil
    }
}

public enum OrbitExternalObservationIngressError: Error, Equatable, Sendable {
    case coalesced
    case backoff
    case ownerConflict
    case stopped
    case resourceLimit
}

/// Synchronous host boundary for bytes supplied by the one canonical app
/// owner. It never opens files, starts processes, owns sockets, or executes an
/// action. Async loaders remain outside and must call this boundary once.
public struct OrbitExternalObservationHost: Codable, Equatable, Sendable {
    public private(set) var runtimeStates: [OrbitExternalFeedKind: OrbitExternalObservationRuntimeState]
    public private(set) var reports: [OrbitExternalFeedKind: OrbitExternalObservationReport]
    public let runtimePolicy: OrbitExternalObservationRuntimePolicy
    public let observationPolicy: OrbitExternalObservationPolicy

    public init(
        runtimePolicy: OrbitExternalObservationRuntimePolicy = OrbitExternalObservationRuntimePolicy(),
        observationPolicy: OrbitExternalObservationPolicy = OrbitExternalObservationPolicy()
    ) {
        self.runtimeStates = [:]
        self.reports = [:]
        self.runtimePolicy = runtimePolicy
        self.observationPolicy = observationPolicy
    }

    public mutating func ingest(
        feed: OrbitExternalFeedKind,
        data: Data,
        ownerID: String,
        now: Date = .now
    ) -> Result<OrbitExternalObservationReport, OrbitExternalObservationIngressError> {
        var state = runtimeStates[feed] ?? OrbitExternalObservationRuntimeState()
        switch state.begin(ownerID: ownerID, now: now, policy: runtimePolicy) {
        case .admitted:
            break
        case .coalesced:
            runtimeStates[feed] = state
            return .failure(.coalesced)
        case .backoff:
            runtimeStates[feed] = state
            return .failure(.backoff)
        case .rejectedOwnerConflict:
            runtimeStates[feed] = state
            return .failure(.ownerConflict)
        case .stopped:
            runtimeStates[feed] = state
            return .failure(.stopped)
        }

        let parsed: Result<OrbitExternalObservationReport, OrbitExternalObservationError>
        switch feed {
        case .openCode:
            parsed = OrbitExternalSessionObservationParser.parseOpenCodeJSON(
                data,
                now: now,
                policy: observationPolicy
            )
        case .freeBuff:
            parsed = OrbitExternalSessionObservationParser.parseFreeBuffManifest(
                data,
                now: now,
                policy: observationPolicy
            )
        }

        switch parsed {
        case let .success(report):
            state.recordSuccess(now: now)
            runtimeStates[feed] = state
            reports[feed] = report
            return .success(report)
        case .failure(.resourceLimit):
            state.recordFailure(now: now, policy: runtimePolicy)
            runtimeStates[feed] = state
            return .failure(.resourceLimit)
        }
    }

    @discardableResult
    public mutating func expireWatchdogIfNeeded(
        feed: OrbitExternalFeedKind,
        now: Date = .now
    ) -> Bool {
        guard var state = runtimeStates[feed] else { return false }
        let expired = state.expireWatchdogIfNeeded(now: now, policy: runtimePolicy)
        runtimeStates[feed] = state
        return expired
    }

    public mutating func emergencyStop() {
        for feed in OrbitExternalFeedKind.allCases {
            var state = runtimeStates[feed] ?? OrbitExternalObservationRuntimeState()
            state.emergencyStop()
            runtimeStates[feed] = state
        }
    }

    /// Explicitly starts a fresh observation generation while retaining the host's
    /// configured runtime and parsing policies. Reports are cleared so observations
    /// accepted before the stop cannot be presented as fresh after the restart.
    public mutating func restartAfterEmergencyStop() {
        runtimeStates.removeAll(keepingCapacity: true)
        reports.removeAll(keepingCapacity: true)
    }
}
