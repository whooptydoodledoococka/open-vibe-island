import Foundation
import OpenIslandCore

struct OrbitAppearanceSettingsSnapshot: Equatable {
    var selectedProfile: IslandAppearanceDisplayProfile
    var notch: IslandAppearancePreferences
    var topBar: IslandAppearancePreferences

    func preferences(for profile: IslandAppearanceDisplayProfile) -> IslandAppearancePreferences {
        profile == .notch ? notch : topBar
    }
}

/// Typed persistence adapter for AppModel-owned appearance settings.
///
/// The adapter owns keys, legacy fallback, validation, and save outcomes. It
/// does not own application reconciliation or overlay behavior.
final class OrbitSettingsStore {
    private let defaults: UserDefaults
    private let injectedPersistence: ((OrbitAppearanceSettingsSnapshot) throws -> Void)?

    init(
        defaults: UserDefaults = .standard,
        persist: ((OrbitAppearanceSettingsSnapshot) throws -> Void)? = nil
    ) {
        self.defaults = defaults
        self.injectedPersistence = persist
    }

    func load() -> OrbitAppearanceSettingsSnapshot {
        OrbitAppearanceSettingsSnapshot(
            selectedProfile: IslandAppearanceDisplayProfile(
                rawValue: defaults.string(forKey: Keys.selectedProfile) ?? ""
            ) ?? .topBar,
            notch: loadPreferences(for: .notch),
            topBar: loadPreferences(for: .topBar)
        )
    }

    @discardableResult
    func save(_ snapshot: OrbitAppearanceSettingsSnapshot) -> RuleSaveState {
        do {
            try injectedPersistence?(snapshot)
            if injectedPersistence == nil {
                defaults.set(snapshot.selectedProfile.rawValue, forKey: Keys.selectedProfile)
                savePreferences(snapshot.notch, for: .notch)
                savePreferences(snapshot.topBar, for: .topBar)
            }
            return .saved
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return .failed(message.isEmpty ? "Unable to save appearance settings" : message)
        }
    }

    private func loadPreferences(for profile: IslandAppearanceDisplayProfile) -> IslandAppearancePreferences {
        IslandAppearancePreferences(
            rightSlot: IslandRightSlot(
                rawValue: value(for: "rightSlot", profile: profile, legacy: Keys.legacyRightSlot)
            ) ?? .count,
            centerLabel: IslandCenterLabel(
                rawValue: value(for: "centerLabel", profile: profile, legacy: Keys.legacyCenterLabel)
            ) ?? .agentAction,
            usageDisplay: IslandUsageDisplay(
                rawValue: value(for: "usageDisplay", profile: profile)
            ) ?? .compact,
            sessionStateIndicator: IslandSessionStateIndicator(
                rawValue: value(for: "stateIndicator", profile: profile, legacy: Keys.legacyStateIndicator)
            ) ?? .animatedDot,
            sessionGroup: IslandSessionGroup(
                rawValue: value(for: "sessionGroup", profile: profile, legacy: Keys.legacySessionGroup)
            ) ?? .none,
            sessionSort: IslandSessionSort(
                rawValue: value(for: "sessionSort", profile: profile, legacy: Keys.legacySessionSort)
            ) ?? .attention,
            completedStaleThreshold: IslandCompletedStaleThreshold(
                rawValue: value(for: "completedStaleThreshold", profile: profile, legacy: Keys.legacyCompletedStaleThreshold)
            ) ?? .fiveMinutes
        )
    }

    private func value(
        for name: String,
        profile: IslandAppearanceDisplayProfile,
        legacy: String? = nil
    ) -> String {
        return defaults.string(forKey: Keys.profile(profile, name))
            ?? legacy.flatMap { defaults.string(forKey: $0) }
            ?? ""
    }

    private func savePreferences(
        _ preferences: IslandAppearancePreferences,
        for profile: IslandAppearanceDisplayProfile
    ) {
        defaults.set(preferences.rightSlot.rawValue, forKey: Keys.profile(profile, "rightSlot"))
        defaults.set(preferences.centerLabel.rawValue, forKey: Keys.profile(profile, "centerLabel"))
        defaults.set(preferences.usageDisplay.rawValue, forKey: Keys.profile(profile, "usageDisplay"))
        defaults.set(preferences.sessionStateIndicator.rawValue, forKey: Keys.profile(profile, "stateIndicator"))
        defaults.set(preferences.sessionGroup.rawValue, forKey: Keys.profile(profile, "sessionGroup"))
        defaults.set(preferences.sessionSort.rawValue, forKey: Keys.profile(profile, "sessionSort"))
        defaults.set(preferences.completedStaleThreshold.rawValue, forKey: Keys.profile(profile, "completedStaleThreshold"))
    }

    private enum Keys {
        static let selectedProfile = "appearance.island.v8.settingsProfile"
        static let legacyRightSlot = "appearance.island.v6.rightSlot"
        static let legacyCenterLabel = "appearance.island.v6.centerLabel"
        static let legacyStateIndicator = "appearance.island.v8.stateIndicator"
        static let legacySessionGroup = "appearance.island.v8.sessionGroup"
        static let legacySessionSort = "appearance.island.v8.sessionSort"
        static let legacyCompletedStaleThreshold = "appearance.island.v8.completedStaleThreshold"

        static func profile(_ profile: IslandAppearanceDisplayProfile, _ name: String) -> String {
            "appearance.island.v8.\(profile.rawValue).\(name)"
        }
    }
}
