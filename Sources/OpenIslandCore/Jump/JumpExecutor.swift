@preconcurrency import AppKit
import CoreGraphics
import Foundation

public struct JumpExecutionEnvironment: @unchecked Sendable {
    public var activateApp: @MainActor @Sendable (String) throws -> Void
    public var focusWindow: @MainActor @Sendable (String, CGWindowID) throws -> Void
    public var selectTab: @MainActor @Sendable (String, String) throws -> Void
    public var selectPane: @MainActor @Sendable (String, String) throws -> Void
    public var openURL: @MainActor @Sendable (URL) throws -> Void
    public var legacyRoute: @MainActor @Sendable (String) throws -> Void
    public var continueInTerminal: @MainActor @Sendable (URL?) throws -> Void

    public init(
        activateApp: @escaping @MainActor @Sendable (String) throws -> Void,
        focusWindow: @escaping @MainActor @Sendable (String, CGWindowID) throws -> Void,
        selectTab: @escaping @MainActor @Sendable (String, String) throws -> Void,
        selectPane: @escaping @MainActor @Sendable (String, String) throws -> Void,
        openURL: @escaping @MainActor @Sendable (URL) throws -> Void,
        legacyRoute: @escaping @MainActor @Sendable (String) throws -> Void,
        continueInTerminal: @escaping @MainActor @Sendable (URL?) throws -> Void
    ) {
        self.activateApp = activateApp
        self.focusWindow = focusWindow
        self.selectTab = selectTab
        self.selectPane = selectPane
        self.openURL = openURL
        self.legacyRoute = legacyRoute
        self.continueInTerminal = continueInTerminal
    }

    public static let live = JumpExecutionEnvironment(
        activateApp: { bundleID in
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                guard running.activate(options: [.activateAllWindows]) else {
                    throw JumpExecutorError.operationFailed("activate app")
                }
                return
            }
            let result = JumpRuntime.runCommand(
                executable: URL(fileURLWithPath: "/usr/bin/open"),
                arguments: ["-b", bundleID]
            )
            guard result.exitCode == 0 else { throw JumpExecutorError.operationFailed("open app") }
        },
        focusWindow: { bundleID, windowID in
            let appName = JumpExecutionEnvironment.applicationName(for: bundleID)
            let script = """
            tell application "\(appName)"
                activate
                try
                    set index of first window whose id is \(windowID) to 1
                end try
            end tell
            """
            try JumpExecutionEnvironment.require(JumpRuntime.runAppleScript(script))
        },
        selectTab: { bundleID, identifier in
            let script: String
            switch bundleID {
            case JumpBundleIdentifier.terminal:
                guard let index = Int(identifier), index > 0 else {
                    throw JumpExecutorError.operationFailed("invalid tab identifier")
                }
                script = """
                tell application "Terminal"
                    activate
                    set selected tab of front window to tab \(index) of front window
                end tell
                """
            case JumpBundleIdentifier.iterm:
                let escaped = JumpExecutionEnvironment.appleScriptLiteral(identifier)
                script = """
                tell application "iTerm"
                    activate
                    repeat with aWindow in windows
                        repeat with aTab in tabs of aWindow
                            repeat with aSession in sessions of aTab
                                if unique id of aSession is "\(escaped)" then
                                    select aSession
                                    return
                                end if
                            end repeat
                        end repeat
                    end repeat
                end tell
                """
            case JumpBundleIdentifier.ghostty:
                let escaped = JumpExecutionEnvironment.appleScriptLiteral(identifier)
                script = """
                tell application "Ghostty"
                    activate
                    focus terminal id "\(escaped)"
                end tell
                """
            default:
                throw JumpExecutorError.operationFailed("tab selector unavailable")
            }
            try JumpExecutionEnvironment.require(JumpRuntime.runAppleScript(script))
        },
        selectPane: { bundleID, identifier in
            if identifier.contains(":"), identifier.contains(".") {
                let result = JumpRuntime.runCommand(
                    executable: URL(fileURLWithPath: "/usr/bin/env"),
                    arguments: ["tmux", "select-window", "-t", identifier]
                )
                guard result.exitCode == 0 else { throw JumpExecutorError.operationFailed("select multiplexer window") }
                let paneResult = JumpRuntime.runCommand(
                    executable: URL(fileURLWithPath: "/usr/bin/env"),
                    arguments: ["tmux", "select-pane", "-t", identifier]
                )
                guard paneResult.exitCode == 0 else { throw JumpExecutorError.operationFailed("select multiplexer pane") }
                return
            }
            throw JumpExecutorError.operationFailed("pane selector unavailable for \(bundleID)")
        },
        openURL: { url in
            guard NSWorkspace.shared.open(url) else { throw JumpExecutorError.operationFailed("open URL") }
        },
        legacyRoute: { _ in
            throw JumpExecutorError.operationFailed("legacy route adapter not installed")
        },
        continueInTerminal: { directory in
            var arguments = ["-a", "Terminal"]
            if let directory { arguments.append(directory.path) }
            let result = JumpRuntime.runCommand(
                executable: URL(fileURLWithPath: "/usr/bin/open"),
                arguments: arguments
            )
            guard result.exitCode == 0 else { throw JumpExecutorError.operationFailed("continue in Terminal") }
        }
    )

    private static func applicationName(for bundleID: String) -> String {
        switch bundleID {
        case JumpBundleIdentifier.terminal: "Terminal"
        case JumpBundleIdentifier.iterm: "iTerm"
        case JumpBundleIdentifier.ghostty: "Ghostty"
        default: bundleID
        }
    }

    private static func appleScriptLiteral(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func require(_ result: Result<String, NoLocalHandleReason>) throws {
        if case .failure(let reason) = result {
            throw JumpExecutorError.operationFailed(reason.rawValue)
        }
    }
}

public enum JumpExecutorError: Error, Sendable, Equatable {
    case operationFailed(String)
}

public struct JumpExecutor: Sendable {
    private let environment: JumpExecutionEnvironment

    public init(environment: JumpExecutionEnvironment = .live) {
        self.environment = environment
    }

    @MainActor
    public func execute(_ plan: JumpPlan) -> JumpExecutionResult {
        var attemptedLevels: [JumpDegradationLevel] = []
        for attempt in plan.attempts {
            attemptedLevels.append(attempt.level)
            do {
                for step in attempt.steps {
                    try execute(step)
                }
                return JumpExecutionResult(
                    succeeded: true,
                    completedLevel: attempt.level,
                    attemptedLevels: attemptedLevels,
                    failedStep: nil
                )
            } catch {
                continue
            }
        }
        return JumpExecutionResult(
            succeeded: false,
            completedLevel: nil,
            attemptedLevels: attemptedLevels,
            failedStep: plan.attempts.last?.steps.last
        )
    }

    @MainActor
    private func execute(_ step: JumpStep) throws {
        switch step {
        case .activateApp(let bundleID):
            try environment.activateApp(bundleID)
        case .focusWindow(let bundleID, let windowID):
            try environment.focusWindow(bundleID, windowID)
        case .selectTab(let bundleID, let identifier):
            try environment.selectTab(bundleID, identifier)
        case .selectPane(let bundleID, let identifier):
            try environment.selectPane(bundleID, identifier)
        case .openURL(let url):
            try environment.openURL(url)
        case .legacyRoute(let route):
            try environment.legacyRoute(route)
        case .continueInTerminal(let directory):
            try environment.continueInTerminal(directory)
        }
    }
}
