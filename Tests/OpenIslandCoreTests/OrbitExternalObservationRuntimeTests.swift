import Foundation
import Testing
@testable import OpenIslandCore

struct OrbitExternalObservationRuntimeTests {
    private let now = Date(timeIntervalSince1970: 1_000)
    private let policy = OrbitExternalObservationRuntimePolicy(
        baseBackoffSeconds: 1,
        maxBackoffSeconds: 8,
        watchdogSeconds: 5,
        degradedFailureThreshold: 3
    )

    @Test
    func oneOwnerCoalescesDuplicatesAndRejectsConflicts() {
        var state = OrbitExternalObservationRuntimeState()

        #expect(state.begin(ownerID: "orbit-owner", now: now, policy: policy) == .admitted)
        #expect(state.begin(ownerID: "orbit-owner", now: now, policy: policy) == .coalesced)
        state.cancelInFlight()
        #expect(state.begin(ownerID: "second-owner", now: now, policy: policy) == .rejectedOwnerConflict)
    }

    @Test
    func failuresBackOffBoundedlyAndDegradeInspectionOnly() {
        var state = OrbitExternalObservationRuntimeState()

        for failure in 1...4 {
            #expect(state.begin(ownerID: "orbit-owner", now: now.addingTimeInterval(Double(failure * 10)), policy: policy) == .admitted)
            state.recordFailure(now: now.addingTimeInterval(Double(failure * 10)), policy: policy)
        }

        #expect(state.consecutiveFailures == 4)
        #expect(state.mode == .degradedInspectionOnly)
        #expect(state.nextAllowedAt == now.addingTimeInterval(48))
        #expect(state.begin(ownerID: "orbit-owner", now: now.addingTimeInterval(47), policy: policy) == .backoff(until: now.addingTimeInterval(48)))
    }

    @Test
    func successResetsFailureAndWatchdogExpiresHungWork() {
        var state = OrbitExternalObservationRuntimeState()
        #expect(state.begin(ownerID: "orbit-owner", now: now, policy: policy) == .admitted)
        let earlyExpiry = state.expireWatchdogIfNeeded(
            now: now.addingTimeInterval(4),
            policy: policy
        )
        #expect(!earlyExpiry)
        let watchdogExpiry = state.expireWatchdogIfNeeded(
            now: now.addingTimeInterval(5),
            policy: policy
        )
        #expect(watchdogExpiry)
        #expect(state.consecutiveFailures == 1)

        #expect(state.begin(ownerID: "orbit-owner", now: now.addingTimeInterval(7), policy: policy) == .admitted)
        state.recordSuccess(now: now.addingTimeInterval(7))
        #expect(state.consecutiveFailures == 0)
        #expect(state.mode == .healthy)
        #expect(state.nextAllowedAt == nil)
    }

    @Test
    func hostIngestsCallerBytesAndEmergencyStopFailsClosed() throws {
        var host = OrbitExternalObservationHost(runtimePolicy: policy)
        let data = Data("[{\"id\":\"session_1\",\"updated\":1000000}]".utf8)

        let report = try host.ingest(
            feed: .openCode,
            data: data,
            ownerID: "orbit-owner",
            now: now
        ).get()
        #expect(report.observations.count == 1)
        #expect(host.reports[.openCode] == report)

        host.emergencyStop()
        #expect(host.ingest(
            feed: .openCode,
            data: data,
            ownerID: "orbit-owner",
            now: now.addingTimeInterval(1)
        ) == .failure(.stopped))
    }

    @Test
    func explicitRestartClearsStoppedGenerationAndPreservesPolicies() throws {
        let runtimePolicy = OrbitExternalObservationRuntimePolicy(
            baseBackoffSeconds: 2,
            maxBackoffSeconds: 16,
            watchdogSeconds: 7,
            degradedFailureThreshold: 4
        )
        let observationPolicy = OrbitExternalObservationPolicy(
            maxBytes: 512,
            maxCandidates: 12,
            maxSessions: 6,
            freshnessSeconds: 90,
            futureToleranceSeconds: 3
        )
        var host = OrbitExternalObservationHost(
            runtimePolicy: runtimePolicy,
            observationPolicy: observationPolicy
        )
        let oldData = Data("[{\"id\":\"old_session\",\"updated\":1000000}]".utf8)
        let newData = Data("[{\"id\":\"new_session\",\"updated\":1001000}]".utf8)

        let oldReport = try host.ingest(
            feed: .openCode,
            data: oldData,
            ownerID: "old-owner",
            now: now
        ).get()
        #expect(host.reports[.openCode] == oldReport)

        host.emergencyStop()
        #expect(host.ingest(
            feed: .openCode,
            data: newData,
            ownerID: "old-owner",
            now: now.addingTimeInterval(1)
        ) == .failure(.stopped))

        host.restartAfterEmergencyStop()
        #expect(host.runtimePolicy == runtimePolicy)
        #expect(host.observationPolicy == observationPolicy)
        #expect(host.runtimeStates.isEmpty)
        #expect(host.reports.isEmpty)

        // Restart is idempotent and does not recreate prior ownership or reports.
        host.restartAfterEmergencyStop()
        #expect(host.runtimeStates.isEmpty)
        #expect(host.reports.isEmpty)

        let newReport = try host.ingest(
            feed: .openCode,
            data: newData,
            ownerID: "new-owner",
            now: now.addingTimeInterval(2)
        ).get()
        #expect(host.runtimeStates[.openCode]?.ownerID == "new-owner")
        #expect(host.runtimeStates[.openCode]?.mode == .healthy)
        #expect(host.runtimeStates[.openCode]?.consecutiveFailures == 0)
        #expect(host.runtimeStates[.openCode]?.nextAllowedAt == nil)
        #expect(host.runtimeStates[.openCode]?.inFlightStartedAt == nil)
        #expect(host.reports[.openCode] == newReport)
        #expect(newReport != oldReport)
    }

    @Test
    func resourceFailureBacksOffWithoutReplacingLastGoodReport() throws {
        var host = OrbitExternalObservationHost(
            runtimePolicy: policy,
            observationPolicy: OrbitExternalObservationPolicy(maxBytes: 64)
        )
        let good = Data("[{\"id\":\"session_1\",\"updated\":1000000}]".utf8)
        let first = try host.ingest(feed: .openCode, data: good, ownerID: "orbit-owner", now: now).get()

        let oversized = Data(repeating: 0, count: 65)
        #expect(host.ingest(
            feed: .openCode,
            data: oversized,
            ownerID: "orbit-owner",
            now: now.addingTimeInterval(1)
        ) == .failure(.resourceLimit))
        #expect(host.reports[.openCode] == first)
        #expect(host.runtimeStates[.openCode]?.consecutiveFailures == 1)
    }
}
