import Foundation

public enum HookSkipConfiguration {
    public static let openIslandSkipKey = "OPEN_ISLAND_SKIP_HOOKS"
    public static let legacyVibeIslandSkipKey = "VIBE_ISLAND_SKIP"

    public static func shouldSkipHooks(environment: [String: String]) -> Bool {
        isTruthy(environment[openIslandSkipKey]) || isTruthy(environment[legacyVibeIslandSkipKey])
    }

    private static func isTruthy(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["1", "true", "yes", "on"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

public struct SilenceRule: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var cwdPattern: String?
    public var promptPattern: String?
    public var isEnabled: Bool
    public var isBuiltIn: Bool

    public init(id: String, label: String, cwdPattern: String? = nil, promptPattern: String? = nil, isEnabled: Bool = true, isBuiltIn: Bool = false) {
        self.id = id
        self.label = label
        self.cwdPattern = Self.normalized(cwdPattern)
        self.promptPattern = Self.normalized(promptPattern)
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
    }

    public func matches(cwd: String?, prompt: String?) -> Bool {
        guard isEnabled, cwdPattern != nil || promptPattern != nil else { return false }
        let cwdMatches = cwdPattern.map { cwd?.localizedCaseInsensitiveContains($0) == true } ?? true
        let promptMatches = promptPattern.map { prompt?.localizedCaseInsensitiveContains($0) == true } ?? true
        return cwdMatches && promptMatches
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

public struct SilenceRuleStore: Equatable, Sendable {
    public static let settingsKey = "orbit.silenceRules.v1"
    public static let builtInRules: [SilenceRule] = [
        .init(id: "chronicle", label: "Chronicle helper", cwdPattern: "/.chronicle/", isBuiltIn: true),
        .init(id: "claudeMem", label: "Memory helper", cwdPattern: "/.claude-mem/", isBuiltIn: true),
        .init(id: "codexAppGitHelper", label: "Git helper", promptPattern: "[git-helper]", isBuiltIn: true),
        .init(id: "codexAppSuggestions", label: "Suggestions helper", promptPattern: "[suggestions-worker]", isBuiltIn: true),
        .init(id: "codexInternalWorkers", label: "Internal worker", promptPattern: "[internal-worker]", isBuiltIn: true),
        .init(id: "craftTitle", label: "Title helper", promptPattern: "craft a concise title", isBuiltIn: true),
        .init(id: "guardian", label: "Guardian helper", promptPattern: "[guardian]", isBuiltIn: true),
        .init(id: "memoryConsolidation", label: "Memory consolidation", promptPattern: "[memory-consolidation]", isBuiltIn: true),
        .init(id: "memoryWriter", label: "Memory writer", promptPattern: "[memory-writer]", isBuiltIn: true),
    ]

    public private(set) var rules: [SilenceRule]
    public private(set) var saveState: RuleSaveState

    public init(rules: [SilenceRule] = Self.builtInRules, saveState: RuleSaveState = .idle) {
        self.rules = rules
        self.saveState = saveState
    }

    public static func settingsBacked(defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: settingsKey), let saved = try? JSONDecoder().decode([SilenceRule].self, from: data) else { return .init() }
        var byID = Dictionary(uniqueKeysWithValues: builtInRules.map { ($0.id, $0) })
        for rule in saved { byID[rule.id] = rule }
        let builtInIDs = Set(builtInRules.map(\.id))
        let ordered = builtInRules.compactMap { byID[$0.id] } + saved.filter { !builtInIDs.contains($0.id) }
        return .init(rules: ordered)
    }

    public func shouldSilence(cwd: String?, prompt: String?) -> Bool {
        rules.contains { $0.matches(cwd: cwd, prompt: prompt) }
    }

    public mutating func add(
        label: String,
        cwdPattern: String? = nil,
        promptPattern: String? = nil,
        persist: (([SilenceRule]) throws -> Void)? = nil
    ) {
        let rule = SilenceRule(
            id: UUID().uuidString.lowercased(),
            label: label,
            cwdPattern: cwdPattern,
            promptPattern: promptPattern
        )
        guard rule.cwdPattern != nil || rule.promptPattern != nil else {
            saveState = .failed("A working-directory or prompt pattern is required")
            return
        }
        rules.append(rule)
        save(using: persist)
    }

    public mutating func setEnabled(
        id: String,
        enabled: Bool,
        persist: (([SilenceRule]) throws -> Void)? = nil
    ) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].isEnabled = enabled
        save(using: persist)
    }

    private mutating func save(using persist: (([SilenceRule]) throws -> Void)?) {
        do {
            if let persist {
                try persist(rules)
            } else {
                let data = try JSONEncoder().encode(rules)
                UserDefaults.standard.set(data, forKey: Self.settingsKey)
            }
            saveState = .saved
        } catch {
            saveState = .failed(ruleSaveFailureMessage(error))
        }
    }
}
