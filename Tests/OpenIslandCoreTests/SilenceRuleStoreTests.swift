import Foundation
import Testing
@testable import OpenIslandCore

struct SilenceRuleStoreTests {
    @Test
    func shipsCanonicalBuiltInRules() {
        #expect(SilenceRuleStore.builtInRules.map(\.id) == [
            "chronicle", "claudeMem", "codexAppGitHelper", "codexAppSuggestions",
            "codexInternalWorkers", "craftTitle", "guardian", "memoryConsolidation", "memoryWriter",
        ])
    }

    @Test
    func matchesCWDAndPromptPatternsWithoutDroppingSession() {
        let store = SilenceRuleStore(rules: [
            SilenceRule(id: "both", label: "Both", cwdPattern: "/helpers/", promptPattern: "background index"),
        ])
        #expect(store.shouldSilence(cwd: "/repo/helpers/worker", prompt: "Run background index now"))
        #expect(!store.shouldSilence(cwd: "/repo/app", prompt: "Run background index now"))
        var state = SessionState(silenceRuleStore: store)
        state.apply(.sessionStarted(.init(
            sessionID: "visible-silent", title: "Helper", tool: .codex,
            summary: "Indexing", timestamp: .now,
            jumpTarget: .init(terminalApp: "Terminal", workspaceName: "repo", paneTitle: "worker", workingDirectory: "/repo/helpers/worker"),
            initialPrompt: "Run background index now"
        )))
        #expect(state.session(id: "visible-silent") != nil)
        #expect(state.session(id: "visible-silent")?.notificationsSilenced == true)
    }

    @Test
    func userRuleCanBeReenabledAndSurfacesSaveFailure() {
        var store = SilenceRuleStore(rules: [SilenceRule(id: "custom", label: "Custom", promptPattern: "quiet task", isEnabled: false)])
        store.setEnabled(id: "custom", enabled: true) { _ in throw RulePersistenceTestError.failed }
        #expect(store.rules.first?.isEnabled == true)
        #expect(store.saveState == .failed("failed"))
        #expect(store.shouldSilence(cwd: nil, prompt: "quiet task"))
    }
    @Test
    func everyBuiltInRuleHasAnEffectiveMatcher() {
        let store = SilenceRuleStore()
        #expect(store.shouldSilence(cwd: "/tmp/.chronicle/work", prompt: nil))
        #expect(store.shouldSilence(cwd: "/tmp/.claude-mem/work", prompt: nil))
        for prompt in [
            "[git-helper]", "[suggestions-worker]", "[internal-worker]",
            "craft a concise title", "[guardian]", "[memory-consolidation]", "[memory-writer]",
        ] {
            #expect(store.shouldSilence(cwd: nil, prompt: prompt))
        }
    }

    @Test
    func customRulesRoundTripThroughSettingsStorage() throws {
        let name = "SilenceRuleStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var store = SilenceRuleStore()
        store.add(label: "Quiet build", promptPattern: "quiet-build") { rules in
            defaults.set(try JSONEncoder().encode(rules), forKey: SilenceRuleStore.settingsKey)
        }
        let loaded = SilenceRuleStore.settingsBacked(defaults: defaults)
        #expect(loaded.shouldSilence(cwd: nil, prompt: "start quiet-build now"))
    }

    @Test
    func replacingRulesReevaluatesVisibleSessionSilence() {
        var state = SessionState(silenceRuleStore: .init(rules: []))
        state.apply(.sessionStarted(.init(
            sessionID: "existing", title: "Existing", tool: .codex,
            summary: "Working", timestamp: .now,
            jumpTarget: .init(terminalApp: "Terminal", workspaceName: "repo", paneTitle: "pane", workingDirectory: "/repo/helper"),
            initialPrompt: "quiet helper task"
        )))
        let rules = SilenceRuleStore(rules: [.init(id: "helper", label: "Helper", promptPattern: "quiet helper")])
        state.replaceRuleStores(silence: rules, admission: .init())
        #expect(state.session(id: "existing")?.notificationsSilenced == true)
    }

    @Test
    func promptArrivalAfterSessionStartSilencesWithoutDroppingSession() {
        let rules = SilenceRuleStore(rules: [.init(id: "late", label: "Late prompt", promptPattern: "background helper")])
        var state = SessionState(silenceRuleStore: rules)
        state.apply(.sessionStarted(.init(
            sessionID: "late-prompt", title: "Visible", tool: .codex,
            summary: "Started", timestamp: .now
        )))
        #expect(state.session(id: "late-prompt")?.notificationsSilenced == false)
        state.apply(.activityUpdated(.init(
            sessionID: "late-prompt", summary: "Prompt submitted", phase: .running,
            timestamp: .now, silencePromptContext: "run background helper"
        )))
        #expect(state.session(id: "late-prompt") != nil)
        #expect(state.session(id: "late-prompt")?.notificationsSilenced == true)
    }

}
