import Testing
@testable import OpenIslandCore

struct SessionParityTests {
    @Test
    func canonicalStateVocabularyHasNineCases() {
        #expect(CanonicalSessionStatus.allCases.map(\.rawValue) == [
            "thinking", "runningTool", "waitingApproval", "question", "working", "processing", "ended", "unknown", "compacting",
        ])
    }

    @Test
    func canonicalToolVerbVocabularyHasThirteenCases() {
        #expect(SessionToolVerb.allCases.map(\.rawValue) == [
            "reading", "searching", "editing", "writing", "running", "building", "testing", "debugging", "planning", "reviewing", "fetching", "waiting", "compacting",
        ])
    }

    @Test
    func reducerTracksCanonicalStatusAndToolVerb() {
        var state = SessionState()
        state.apply(.sessionStarted(.init(
            sessionID: "parity", title: "Parity", tool: .codex,
            initialPhase: .running, summary: "Starting", timestamp: .now,
            canonicalStatus: .thinking
        )))
        #expect(state.session(id: "parity")?.canonicalStatus == .thinking)
        state.apply(.activityUpdated(.init(
            sessionID: "parity", summary: "Running tests", phase: .running,
            timestamp: .now, canonicalStatus: .runningTool, toolVerb: .testing
        )))
        #expect(state.session(id: "parity")?.canonicalStatus == .runningTool)
        #expect(state.session(id: "parity")?.toolVerb == .testing)
    }
}
