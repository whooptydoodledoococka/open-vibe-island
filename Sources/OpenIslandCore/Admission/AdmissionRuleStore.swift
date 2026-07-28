import Foundation

public struct AdmissionRule: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var bundleID: String
    public var label: String
    public var isEnabled: Bool

    public init(id: String? = nil, bundleID: String, label: String, isEnabled: Bool = true) {
        let normalized = bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.id = id ?? normalized
        self.bundleID = normalized
        self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isEnabled = isEnabled
    }
}

public struct AdmissionRuleStore: Equatable, Sendable {
    public static let settingsKey = "orbit.admissionRules.v1"
    public private(set) var rules: [AdmissionRule]
    public private(set) var saveState: RuleSaveState

    public init(rules: [AdmissionRule] = [], saveState: RuleSaveState = .idle) {
        self.rules = rules
        self.saveState = saveState
    }

    public static func settingsBacked(defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: settingsKey), let rules = try? JSONDecoder().decode([AdmissionRule].self, from: data) else { return .init() }
        return .init(rules: rules)
    }

    public func admits(launcherBundleID: String?) -> Bool {
        guard let bundleID = launcherBundleID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !bundleID.isEmpty else { return true }
        return !rules.contains { $0.isEnabled && $0.bundleID == bundleID }
    }

    public mutating func add(bundleID: String, label: String, persist: (([AdmissionRule]) throws -> Void)? = nil) {
        let normalized = bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { saveState = .failed("Bundle identifier is required"); return }
        if let index = rules.firstIndex(where: { $0.bundleID == normalized }) {
            rules[index].isEnabled = true
            rules[index].label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            rules.append(.init(bundleID: normalized, label: label))
        }
        save(using: persist)
    }

    public mutating func setEnabled(id: String, enabled: Bool, persist: (([AdmissionRule]) throws -> Void)? = nil) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].isEnabled = enabled
        save(using: persist)
    }

    private mutating func save(using persist: (([AdmissionRule]) throws -> Void)?) {
        do {
            if let persist { try persist(rules) }
            else { UserDefaults.standard.set(try JSONEncoder().encode(rules), forKey: Self.settingsKey) }
            saveState = .saved
        } catch { saveState = .failed(ruleSaveFailureMessage(error)) }
    }
}
