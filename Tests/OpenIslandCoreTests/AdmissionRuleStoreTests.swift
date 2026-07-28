import Foundation
import Testing
@testable import OpenIslandCore

struct AdmissionRuleStoreTests {
    @Test
    func dropsMatchingLauncherBeforeSessionDisplay() {
        let store = AdmissionRuleStore(rules: [AdmissionRule(bundleID: "app.orbit.background-helper", label: "Background helper")])
        var state = SessionState(admissionRuleStore: store)
        state.apply(.sessionStarted(.init(
            sessionID: "blocked", title: "Blocked", tool: .codex,
            summary: "Should not display", timestamp: .now,
            launcherBundleID: "APP.ORBIT.BACKGROUND-HELPER"
        )))
        #expect(state.session(id: "blocked") == nil)
    }

    @Test
    func addReenablesExistingRuleWithoutDuplicatingIt() {
        var store = AdmissionRuleStore(rules: [AdmissionRule(bundleID: "app.orbit.helper", label: "Helper", isEnabled: false)])
        store.add(bundleID: " app.orbit.helper ", label: "Updated") { _ in }
        #expect(store.rules.count == 1)
        #expect(store.rules[0].isEnabled)
        #expect(store.rules[0].label == "Updated")
        #expect(store.saveState == .saved)
    }

    @Test
    func saveFailureIsVisibleAndRuleRemainsEditable() {
        var store = AdmissionRuleStore()
        store.add(bundleID: "app.orbit.helper", label: "Helper") { _ in throw RulePersistenceTestError.failed }
        #expect(store.rules.count == 1)
        #expect(store.saveState == .failed("failed"))
        store.setEnabled(id: store.rules[0].id, enabled: false) { _ in }
        #expect(store.rules[0].isEnabled == false)
        #expect(store.saveState == .saved)
    }
    @Test
    func rulesRoundTripThroughSettingsStorage() throws {
        let name = "AdmissionRuleStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var store = AdmissionRuleStore()
        store.add(bundleID: "app.orbit.background", label: "Background") { rules in
            defaults.set(try JSONEncoder().encode(rules), forKey: AdmissionRuleStore.settingsKey)
        }
        let loaded = AdmissionRuleStore.settingsBacked(defaults: defaults)
        #expect(!loaded.admits(launcherBundleID: "app.orbit.background"))
    }

    @Test
    func replacingRulesRemovesAnAlreadyVisibleMatchingLauncher() {
        var state = SessionState(admissionRuleStore: .init())
        state.apply(.sessionStarted(.init(
            sessionID: "existing", title: "Existing", tool: .codex,
            summary: "Working", timestamp: .now,
            launcherBundleID: "app.orbit.background"
        )))
        #expect(state.session(id: "existing") != nil)
        let rules = AdmissionRuleStore(rules: [.init(bundleID: "app.orbit.background", label: "Background")])
        state.replaceRuleStores(silence: .init(), admission: rules)
        #expect(state.session(id: "existing") == nil)
    }

}

enum RulePersistenceTestError: Error, LocalizedError {
    case failed
    var errorDescription: String? { "failed" }
}
