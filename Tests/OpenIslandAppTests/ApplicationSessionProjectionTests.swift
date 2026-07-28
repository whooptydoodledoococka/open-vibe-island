import Foundation
import Testing
import OpenIslandCore
@testable import OpenIslandApp

struct ApplicationSessionProjectionTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    @Test
    func primaryDeduplicatesLiveAttachments() {
        let first = makeSession(id: "first", title: "First", updatedAt: now)
        let duplicate = makeSession(id: "duplicate", title: "Duplicate", updatedAt: now.addingTimeInterval(-1))

        let result = ApplicationSessionProjection.buckets(
            sessions: [duplicate, first],
            now: now,
            completedStaleThreshold: .fiveMinutes,
            liveAttachmentKeysBySessionID: [
                "first": "terminal-1",
                "duplicate": "terminal-1"
            ]
        )

        #expect(result.primary.map(\.id) == ["first"])
        #expect(result.overflow.map(\.id) == ["duplicate"])
    }

    @Test
    func nonVisibleSessionRemainsInOverflow() {
        let completed = makeSession(
            id: "completed",
            title: "Completed",
            phase: .completed,
            updatedAt: now.addingTimeInterval(-60)
        )

        let result = ApplicationSessionProjection.buckets(
            sessions: [completed],
            now: now,
            completedStaleThreshold: .fiveMinutes,
            liveAttachmentKeysBySessionID: [:]
        )

        #expect(result.primary.isEmpty)
        #expect(result.overflow.map(\.id) == ["completed"])
    }

    @Test
    func equalPrioritySessionsUseStableTitleTieBreak() {
        let beta = makeSession(id: "beta", title: "Beta", updatedAt: now)
        let alpha = makeSession(id: "alpha", title: "Alpha", updatedAt: now)

        let result = ApplicationSessionProjection.buckets(
            sessions: [beta, alpha],
            now: now,
            completedStaleThreshold: .fiveMinutes,
            liveAttachmentKeysBySessionID: [:]
        )

        #expect(result.primary.map(\.id) == ["alpha", "beta"])
    }

    @Test
    func subagentSessionsAreExcludedFromBothBuckets() {
        let subagent = makeSession(
            id: "subagent",
            title: "Subagent",
            updatedAt: now,
            claudeMetadata: ClaudeSessionMetadata(transcriptPath: "/tmp/subagents/child.json")
        )

        let result = ApplicationSessionProjection.buckets(
            sessions: [subagent],
            now: now,
            completedStaleThreshold: .fiveMinutes,
            liveAttachmentKeysBySessionID: [:]
        )

        #expect(result.primary.isEmpty)
        #expect(result.overflow.isEmpty)
    }

    private func makeSession(
        id: String,
        title: String,
        phase: SessionPhase = .running,
        updatedAt: Date,
        claudeMetadata: ClaudeSessionMetadata? = nil
    ) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: title,
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: title,
            updatedAt: updatedAt,
            claudeMetadata: claudeMetadata
        )
        session.isProcessAlive = phase != .completed
        return session
    }
}
