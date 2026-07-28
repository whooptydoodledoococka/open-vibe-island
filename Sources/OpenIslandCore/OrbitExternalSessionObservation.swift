import CryptoKit
import Foundation

public enum OrbitExternalFeedKind: String, Codable, CaseIterable, Hashable, Sendable {
    case openCode
    case freeBuff
}

public struct OrbitExternalObservationPolicy: Codable, Equatable, Sendable {
    public let maxBytes: Int
    public let maxCandidates: Int
    public let maxSessions: Int
    public let freshnessSeconds: TimeInterval
    public let futureToleranceSeconds: TimeInterval

    public init(
        maxBytes: Int = 1_048_576,
        maxCandidates: Int = 200,
        maxSessions: Int = 20,
        freshnessSeconds: TimeInterval = 60,
        futureToleranceSeconds: TimeInterval = 5
    ) {
        self.maxBytes = max(1, maxBytes)
        self.maxCandidates = max(1, maxCandidates)
        self.maxSessions = max(1, maxSessions)
        self.freshnessSeconds = max(1, freshnessSeconds)
        self.futureToleranceSeconds = max(0, futureToleranceSeconds)
    }
}

public struct OrbitExternalSessionObservation: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let feed: OrbitExternalFeedKind
    public let adapterID: String
    public let sessionID: String
    public let observedAt: Date
    public let evidenceDigest: String
}

public struct OrbitExternalObservationReport: Codable, Equatable, Sendable {
    public enum SurfaceState: String, Codable, Sendable {
        case liveInspectionOnly
        case staleInspectionOnly
        case degradedInspectionOnly
    }

    public let feed: OrbitExternalFeedKind
    public let observations: [OrbitExternalSessionObservation]
    public let truncatedCandidateCount: Int
    public let rejectedInvalidCount: Int
    public let rejectedStaleCount: Int
    public let surfaceState: SurfaceState

    public static let admittedFields = [
        "feed",
        "adapterID",
        "sessionID",
        "observedAt",
        "evidenceDigest",
    ]
}

public enum OrbitExternalObservationError: Error, Equatable, Sendable {
    case resourceLimit
}

public enum OrbitExternalObservationAuthority {
    public static let acceptsCallerSuppliedBytes = true
    public static let ownsProcess = false
    public static let ownsNetwork = false
    public static let ownsAppServer = false
    public static let installsHooks = false
    public static let usesCredentials = false
    public static let changesRoutes = false
    public static let executesActions = false
}

public enum OrbitExternalSessionObservationParser {
    public static let openCodeAdapterID = "OpenCodeAdapter.local-readonly"
    public static let freeBuffAdapterID = "FreeBuffAdapter.local-readonly"

    public static func parseOpenCodeJSON(
        _ data: Data,
        now: Date = .now,
        policy: OrbitExternalObservationPolicy = OrbitExternalObservationPolicy()
    ) -> Result<OrbitExternalObservationReport, OrbitExternalObservationError> {
        guard data.count <= policy.maxBytes else { return .failure(.resourceLimit) }
        guard let records = try? JSONDecoder().decode([OpenCodeRecord].self, from: data) else {
            return .success(report(feed: .openCode, observations: [], invalid: 1, stale: 0, truncated: 0))
        }

        var observations: [OrbitExternalSessionObservation] = []
        var invalid = 0
        var stale = 0
        for record in records.prefix(policy.maxCandidates) {
            guard isSafeIdentifier(record.id), record.updated > 0 else {
                invalid += 1
                continue
            }
            let observedAt = Date(timeIntervalSince1970: TimeInterval(record.updated) / 1_000)
            switch classify(observedAt: observedAt, now: now, policy: policy) {
            case .invalid:
                invalid += 1
            case .stale:
                stale += 1
            case .fresh:
                observations.append(observation(
                    feed: .openCode,
                    adapterID: openCodeAdapterID,
                    sessionID: record.id,
                    observedAt: observedAt
                ))
            }
        }

        return .success(report(
            feed: .openCode,
            observations: bounded(observations, policy: policy),
            invalid: invalid,
            stale: stale,
            truncated: max(0, records.count - policy.maxCandidates)
        ))
    }

    public static func parseFreeBuffManifest(
        _ data: Data,
        now: Date = .now,
        policy: OrbitExternalObservationPolicy = OrbitExternalObservationPolicy()
    ) -> Result<OrbitExternalObservationReport, OrbitExternalObservationError> {
        guard data.count <= policy.maxBytes else { return .failure(.resourceLimit) }
        guard let record = try? JSONDecoder().decode(FreeBuffRecord.self, from: data),
              isSafeIdentifier(record.agent),
              let observedAt = parseISO8601(record.updatedAt) else {
            return .success(report(feed: .freeBuff, observations: [], invalid: 1, stale: 0, truncated: 0))
        }

        let sessionID = "agent-\(record.agent)"
        switch classify(observedAt: observedAt, now: now, policy: policy) {
        case .invalid:
            return .success(report(feed: .freeBuff, observations: [], invalid: 1, stale: 0, truncated: 0))
        case .stale:
            return .success(report(feed: .freeBuff, observations: [], invalid: 0, stale: 1, truncated: 0))
        case .fresh:
            return .success(report(
                feed: .freeBuff,
                observations: [observation(
                    feed: .freeBuff,
                    adapterID: freeBuffAdapterID,
                    sessionID: sessionID,
                    observedAt: observedAt
                )],
                invalid: 0,
                stale: 0,
                truncated: 0
            ))
        }
    }

    private struct OpenCodeRecord: Decodable {
        let id: String
        let updated: Int64
    }

    private struct FreeBuffRecord: Decodable {
        let agent: String
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case agent
            case updatedAt = "updated_at"
        }
    }

    private enum ObservationAge {
        case fresh
        case stale
        case invalid
    }

    private static func classify(
        observedAt: Date,
        now: Date,
        policy: OrbitExternalObservationPolicy
    ) -> ObservationAge {
        let age = now.timeIntervalSince(observedAt)
        if age < -policy.futureToleranceSeconds { return .invalid }
        if age > policy.freshnessSeconds { return .stale }
        return .fresh
    }

    private static func observation(
        feed: OrbitExternalFeedKind,
        adapterID: String,
        sessionID: String,
        observedAt: Date
    ) -> OrbitExternalSessionObservation {
        let digestInput = "\(feed.rawValue)|\(adapterID)|\(sessionID)|\(Int(observedAt.timeIntervalSince1970))"
        let digest = SHA256.hash(data: Data(digestInput.utf8)).map { String(format: "%02x", $0) }.joined()
        return OrbitExternalSessionObservation(
            id: digest,
            feed: feed,
            adapterID: adapterID,
            sessionID: sessionID,
            observedAt: observedAt,
            evidenceDigest: digest
        )
    }

    private static func bounded(
        _ observations: [OrbitExternalSessionObservation],
        policy: OrbitExternalObservationPolicy
    ) -> [OrbitExternalSessionObservation] {
        Array(observations.sorted {
            if $0.observedAt != $1.observedAt { return $0.observedAt > $1.observedAt }
            return $0.sessionID < $1.sessionID
        }.prefix(policy.maxSessions))
    }

    private static func report(
        feed: OrbitExternalFeedKind,
        observations: [OrbitExternalSessionObservation],
        invalid: Int,
        stale: Int,
        truncated: Int
    ) -> OrbitExternalObservationReport {
        let state: OrbitExternalObservationReport.SurfaceState
        if !observations.isEmpty {
            state = .liveInspectionOnly
        } else if stale > 0 {
            state = .staleInspectionOnly
        } else {
            state = .degradedInspectionOnly
        }
        return OrbitExternalObservationReport(
            feed: feed,
            observations: observations,
            truncatedCandidateCount: truncated,
            rejectedInvalidCount: invalid,
            rejectedStaleCount: stale,
            surfaceState: state
        )
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
