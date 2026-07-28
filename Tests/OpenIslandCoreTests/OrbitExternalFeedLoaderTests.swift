import Darwin
import Foundation
import Testing
@testable import OpenIslandCore

struct OrbitExternalFeedLoaderTests {
    private let now = Date(timeIntervalSince1970: 1_785_014_000)
    private let runtimePolicy = OrbitExternalObservationRuntimePolicy(
        baseBackoffSeconds: 1,
        maxBackoffSeconds: 8,
        watchdogSeconds: 5,
        degradedFailureThreshold: 3
    )

    private func withFixtureDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("orbit-feed-loader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private func write(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url, options: .atomic)
    }

    @Test
    func openCodeFileLoadsAndIngestsLiveReport() throws {
        try withFixtureDirectory { directory in
            let file = directory.appendingPathComponent("opencode-session.json")
            try write("[{\"id\":\"ses_load\",\"updated\":1785014000000}]", to: file)
            var host = OrbitExternalObservationHost(runtimePolicy: runtimePolicy)

            let report = try OrbitExternalFeedLoader.ingestFromFile(
                feed: .openCode,
                fileURL: file,
                host: &host,
                ownerID: "orbit-owner",
                now: now
            ).get()

            #expect(report.observations.count == 1)
            #expect(report.observations.first?.sessionID == "ses_load")
            #expect(report.surfaceState == .liveInspectionOnly)
            #expect(host.reports[.openCode] == report)
        }
    }

    @Test
    func freeBuffManifestLoadsAndIngests() throws {
        try withFixtureDirectory { directory in
            let file = directory.appendingPathComponent("freebuff-manifest.json")
            try write("{\"agent\":\"freebuff\",\"updated_at\":\"2026-07-25T21:13:20Z\"}", to: file)
            var host = OrbitExternalObservationHost(runtimePolicy: runtimePolicy)

            let report = try OrbitExternalFeedLoader.ingestFromFile(
                feed: .freeBuff,
                fileURL: file,
                host: &host,
                ownerID: "orbit-owner",
                now: now
            ).get()

            #expect(report.observations.count == 1)
            #expect(report.observations.first?.sessionID == "agent-freebuff")
            #expect(report.surfaceState == .liveInspectionOnly)
            #expect(host.reports[.freeBuff] == report)
        }
    }

    @Test
    func staleFileRemainsInspectionOnly() throws {
        try withFixtureDirectory { directory in
            let file = directory.appendingPathComponent("opencode-stale.json")
            try write("[{\"id\":\"ses_old\",\"updated\":1784000000000}]", to: file)
            var host = OrbitExternalObservationHost(runtimePolicy: runtimePolicy)

            let report = try OrbitExternalFeedLoader.ingestFromFile(
                feed: .openCode,
                fileURL: file,
                host: &host,
                ownerID: "orbit-owner",
                now: now
            ).get()

            #expect(report.observations.isEmpty)
            #expect(report.rejectedStaleCount == 1)
            #expect(report.surfaceState == .staleInspectionOnly)
        }
    }

    @Test
    func symlinkIsRejected() throws {
        try withFixtureDirectory { directory in
            let target = directory.appendingPathComponent("target.json")
            try write("[{\"id\":\"ses_load\",\"updated\":1785014000000}]", to: target)
            let link = directory.appendingPathComponent("link.json")
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target.path)

            #expect(OrbitExternalFeedLoader.load(feed: .openCode, fileURL: link) == .failure(.symlink))

            var host = OrbitExternalObservationHost(runtimePolicy: runtimePolicy)
            #expect(OrbitExternalFeedLoader.ingestFromFile(
                feed: .openCode,
                fileURL: link,
                host: &host,
                ownerID: "orbit-owner",
                now: now
            ) == .failure(.loader(.symlink)))
            #expect(host.runtimeStates[.openCode] == nil)
            #expect(host.reports[.openCode] == nil)
        }
    }

    @Test
    func directoryIsRejected() throws {
        try withFixtureDirectory { directory in
            #expect(OrbitExternalFeedLoader.load(feed: .openCode, fileURL: directory) == .failure(.directory))
        }
    }

    @Test
    func missingFileIsRejected() throws {
        try withFixtureDirectory { directory in
            let missing = directory.appendingPathComponent("absent.json")
            #expect(OrbitExternalFeedLoader.load(feed: .freeBuff, fileURL: missing) == .failure(.missingOrUnreadable))
        }
    }

    @Test
    func nonFileURLIsRejected() throws {
        let remote = try #require(URL(string: "https://example.invalid/feed.json"))
        #expect(OrbitExternalFeedLoader.load(feed: .openCode, fileURL: remote) == .failure(.notAFileURL))
    }

    @Test
    func nonRegularFileIsRejected() throws {
        try withFixtureDirectory { directory in
            let fifo = directory.appendingPathComponent("pipe")
            #expect(mkfifo(fifo.path, 0o600) == 0)
            #expect(OrbitExternalFeedLoader.load(feed: .openCode, fileURL: fifo) == .failure(.notRegularFile))
        }
    }

    @Test
    func readIsBoundedAtMaxBytesPlusOneAndRejectsOverflow() throws {
        try withFixtureDirectory { directory in
            let policy = OrbitExternalFeedLoaderPolicy(maxBytes: 64)

            let exact = directory.appendingPathComponent("exact.json")
            try Data(repeating: UInt8(ascii: "a"), count: 64).write(to: exact)
            guard case let .success(bytes) = OrbitExternalFeedLoader.load(
                feed: .openCode,
                fileURL: exact,
                policy: policy
            ) else {
                Issue.record("expected exact-size file to load")
                return
            }
            #expect(bytes.count == 64)

            let oversized = directory.appendingPathComponent("oversized.json")
            try Data(repeating: UInt8(ascii: "b"), count: 65).write(to: oversized)
            #expect(OrbitExternalFeedLoader.load(
                feed: .openCode,
                fileURL: oversized,
                policy: policy
            ) == .failure(.exceedsMaxBytes))
        }
    }

    @Test
    func hostMaxByteEnforcementIsPreservedThroughLoader() throws {
        try withFixtureDirectory { directory in
            let file = directory.appendingPathComponent("host-oversized.json")
            try Data(repeating: UInt8(ascii: "c"), count: 100).write(to: file)
            var host = OrbitExternalObservationHost(
                runtimePolicy: runtimePolicy,
                observationPolicy: OrbitExternalObservationPolicy(maxBytes: 64)
            )

            #expect(OrbitExternalFeedLoader.ingestFromFile(
                feed: .openCode,
                fileURL: file,
                host: &host,
                ownerID: "orbit-owner",
                now: now
            ) == .failure(.ingress(.resourceLimit)))
            #expect(host.reports[.openCode] == nil)
            #expect(host.runtimeStates[.openCode]?.consecutiveFailures == 1)
        }
    }

    @Test
    func ownerConflictAndEmergencyStopHandOffThroughLoader() throws {
        try withFixtureDirectory { directory in
            let file = directory.appendingPathComponent("opencode-session.json")
            try write("[{\"id\":\"ses_load\",\"updated\":1785014000000}]", to: file)
            var host = OrbitExternalObservationHost(runtimePolicy: runtimePolicy)

            guard case .success = OrbitExternalFeedLoader.ingestFromFile(
                feed: .openCode,
                fileURL: file,
                host: &host,
                ownerID: "first-owner",
                now: now
            ) else {
                Issue.record("expected first owner ingest to succeed")
                return
            }

            #expect(OrbitExternalFeedLoader.ingestFromFile(
                feed: .openCode,
                fileURL: file,
                host: &host,
                ownerID: "second-owner",
                now: now.addingTimeInterval(1)
            ) == .failure(.ingress(.ownerConflict)))

            host.emergencyStop()
            #expect(OrbitExternalFeedLoader.ingestFromFile(
                feed: .openCode,
                fileURL: file,
                host: &host,
                ownerID: "first-owner",
                now: now.addingTimeInterval(2)
            ) == .failure(.ingress(.stopped)))
        }
    }

    @Test
    func loaderAuthorityContractCannotDiscoverOwnOrExecuteAnything() {
        #expect(OrbitExternalFeedLoaderAuthority.requiresExplicitFileURL)
        #expect(OrbitExternalFeedLoaderAuthority.readsRegularFilesOnly)
        #expect(!OrbitExternalFeedLoaderAuthority.discoversPaths)
        #expect(!OrbitExternalFeedLoaderAuthority.ownsProcess)
        #expect(!OrbitExternalFeedLoaderAuthority.ownsNetwork)
        #expect(!OrbitExternalFeedLoaderAuthority.ownsSockets)
        #expect(!OrbitExternalFeedLoaderAuthority.usesCredentials)
        #expect(!OrbitExternalFeedLoaderAuthority.executesActions)
    }
}
