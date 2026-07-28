import Foundation
import Testing
@testable import OpenIslandApp

struct OrbitSettingsStoreTests {
    @Test
    func loadUsesTypedValuesAndLegacyFallback() {
        let defaults = makeDefaults()
        defaults.set(IslandRightSlot.agents.rawValue, forKey: "appearance.island.v6.rightSlot")
        defaults.set(IslandCenterLabel.off.rawValue, forKey: "appearance.island.v6.centerLabel")
        defaults.set(IslandSessionGroup.project.rawValue, forKey: "appearance.island.v8.sessionGroup")

        let snapshot = OrbitSettingsStore(defaults: defaults).load()

        #expect(snapshot.selectedProfile == .topBar)
        #expect(snapshot.notch.rightSlot == .agents)
        #expect(snapshot.notch.centerLabel == .off)
        #expect(snapshot.notch.sessionGroup == .project)
    }

    @Test
    func saveRoundTripsTypedSnapshot() {
        let defaults = makeDefaults()
        let store = OrbitSettingsStore(defaults: defaults)
        var snapshot = store.load()
        snapshot.selectedProfile = .notch
        snapshot.notch.rightSlot = .none
        snapshot.topBar.sessionSort = .lastUpdate

        #expect(store.save(snapshot) == .saved)
        #expect(store.load() == snapshot)
    }

    @Test
    func saveFailureIsExplicitAndDoesNotWriteThrough() {
        let defaults = makeDefaults()
        let error = TestSettingsError.diskFull
        let store = OrbitSettingsStore(defaults: defaults) { _ in throw error }
        var snapshot = store.load()
        snapshot.selectedProfile = .notch

        #expect(store.save(snapshot) == .failed("Settings disk is full"))
        #expect(defaults.string(forKey: "appearance.island.v8.settingsProfile") == nil)
    }

    @Test
    func invalidTypedValuesFallBackToSafeDefaults() {
        let defaults = makeDefaults()
        defaults.set("not-a-right-slot", forKey: "appearance.island.v8.notch.rightSlot")
        defaults.set("not-a-profile", forKey: "appearance.island.v8.settingsProfile")

        let snapshot = OrbitSettingsStore(defaults: defaults).load()

        #expect(snapshot.selectedProfile == .topBar)
        #expect(snapshot.notch.rightSlot == .count)
    }

    @Test
    @MainActor
    func appModelInitializationDoesNotPersistAppearanceSettings() {
        let defaults = makeDefaults()
        _ = AppModel(settingsStore: OrbitSettingsStore(defaults: defaults))

        #expect(defaults.string(forKey: "appearance.island.v8.settingsProfile") == nil)
        #expect(defaults.string(forKey: "appearance.island.v8.notch.rightSlot") == nil)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "OrbitSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private enum TestSettingsError: LocalizedError {
        case diskFull

        var errorDescription: String? {
            "Settings disk is full"
        }
    }
}
