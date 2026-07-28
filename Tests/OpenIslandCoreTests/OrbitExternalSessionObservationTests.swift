import Foundation
import Testing
@testable import OpenIslandCore

struct OrbitExternalSessionObservationTests {
    private let now = Date(timeIntervalSince1970: 1_785_014_000)

    @Test
    func openCodeAdmitsOnlyStableMetadataAndDropsPrivatePayloadFields() throws {
        let data = Data("""
        [{"id":"ses_fixture_1","title":"PRIVATE TASK","updated":1785014000000,"directory":"/private"}]
        """.utf8)

        let report = try OrbitExternalSessionObservationParser.parseOpenCodeJSON(data, now: now).get()

        #expect(report.observations.count == 1)
        let observation = try #require(report.observations.first)
        #expect(observation.feed == .openCode)
        #expect(observation.adapterID == "OpenCodeAdapter.local-readonly")
        #expect(observation.sessionID == "ses_fixture_1")
        #expect(report.surfaceState == .liveInspectionOnly)
        #expect(!String(reflecting: report).contains("PRIVATE"))
        #expect(!String(reflecting: report).contains("/private"))
    }

    @Test
    func freeBuffDropsRepoOwnershipAndTaskPayloadFields() throws {
        let data = Data("""
        {"agent":"freebuff","repo":"/private/repo","owns":["task"],"current_task":"PRIVATE TASK","updated_at":"2026-07-25T21:13:00Z"}
        """.utf8)

        let report = try OrbitExternalSessionObservationParser.parseFreeBuffManifest(data, now: now).get()

        #expect(report.observations.count == 1)
        let observation = try #require(report.observations.first)
        #expect(observation.feed == .freeBuff)
        #expect(observation.adapterID == "FreeBuffAdapter.local-readonly")
        #expect(observation.sessionID == "agent-freebuff")
        #expect(!String(reflecting: report).contains("PRIVATE"))
        #expect(!String(reflecting: report).contains("/private"))
    }

    @Test
    func malformedFutureStaleAndOversizedInputsFailClosed() throws {
        let malformed = Data("[{\"id\":\"bad id\",\"updated\":1785014000000}]".utf8)
        let malformedReport = try OrbitExternalSessionObservationParser.parseOpenCodeJSON(malformed, now: now).get()
        #expect(malformedReport.observations.isEmpty)
        #expect(malformedReport.rejectedInvalidCount == 1)

        let stale = Data("[{\"id\":\"ses_old\",\"updated\":1784000000000}]".utf8)
        let staleReport = try OrbitExternalSessionObservationParser.parseOpenCodeJSON(stale, now: now).get()
        #expect(staleReport.surfaceState == .staleInspectionOnly)
        #expect(staleReport.rejectedStaleCount == 1)

        let future = Data("""
        {"agent":"freebuff","updated_at":"2026-07-25T21:14:00Z"}
        """.utf8)
        let futureReport = try OrbitExternalSessionObservationParser.parseFreeBuffManifest(future, now: now).get()
        #expect(futureReport.rejectedInvalidCount == 1)

        let oversized = Data(repeating: 0, count: 11)
        let result = OrbitExternalSessionObservationParser.parseOpenCodeJSON(
            oversized,
            now: now,
            policy: OrbitExternalObservationPolicy(maxBytes: 10)
        )
        #expect(result == .failure(.resourceLimit))
    }

    @Test
    func candidateAndResultCountsAreBoundedAndDeterministic() throws {
        let records = (0..<5).map { index in
            "{\"id\":\"session_\(index)\",\"updated\":\(1_785_013_990_000 + Int64(index))}"
        }.joined(separator: ",")
        let data = Data("[\(records)]".utf8)
        let policy = OrbitExternalObservationPolicy(maxCandidates: 3, maxSessions: 2)

        let report = try OrbitExternalSessionObservationParser.parseOpenCodeJSON(
            data,
            now: now,
            policy: policy
        ).get()

        #expect(report.observations.count == 2)
        #expect(report.truncatedCandidateCount == 2)
        #expect(report.observations.map(\.sessionID) == ["session_2", "session_1"])
    }

    @Test
    func authorityContractCannotOwnOrExecuteAnything() {
        #expect(OrbitExternalObservationAuthority.acceptsCallerSuppliedBytes)
        #expect(!OrbitExternalObservationAuthority.ownsProcess)
        #expect(!OrbitExternalObservationAuthority.ownsNetwork)
        #expect(!OrbitExternalObservationAuthority.ownsAppServer)
        #expect(!OrbitExternalObservationAuthority.installsHooks)
        #expect(!OrbitExternalObservationAuthority.usesCredentials)
        #expect(!OrbitExternalObservationAuthority.changesRoutes)
        #expect(!OrbitExternalObservationAuthority.executesActions)
    }
}
