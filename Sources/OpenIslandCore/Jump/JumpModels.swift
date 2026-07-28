import CoreGraphics
import Foundation

public struct JumpInput: Sendable, Equatable {
    public var sessionID: String
    public var controllingTTY: String?
    public var workingDirectory: URL?
    public var owningBundleID: String?
    public var paneTitle: String?
    public var workspaceName: String?
    public var terminalSessionID: String?
    public var tmuxTarget: String?
    public var tmuxSocketPath: String?
    public var warpPaneUUID: String?
    public var customActivationURL: URL?
    public var legacyRoute: String?
    public var sourceProcessID: Int32?
    public var isInTmux: Bool
    public var isSSHRemote: Bool

    public init(
        sessionID: String,
        controllingTTY: String? = nil,
        workingDirectory: URL? = nil,
        owningBundleID: String? = nil,
        paneTitle: String? = nil,
        workspaceName: String? = nil,
        terminalSessionID: String? = nil,
        tmuxTarget: String? = nil,
        tmuxSocketPath: String? = nil,
        warpPaneUUID: String? = nil,
        customActivationURL: URL? = nil,
        legacyRoute: String? = nil,
        sourceProcessID: Int32? = nil,
        isInTmux: Bool = false,
        isSSHRemote: Bool = false
    ) {
        self.sessionID = sessionID
        self.controllingTTY = controllingTTY
        self.workingDirectory = workingDirectory
        self.owningBundleID = owningBundleID
        self.paneTitle = paneTitle
        self.workspaceName = workspaceName
        self.terminalSessionID = terminalSessionID
        self.tmuxTarget = tmuxTarget
        self.tmuxSocketPath = tmuxSocketPath
        self.warpPaneUUID = warpPaneUUID
        self.customActivationURL = customActivationURL
        self.legacyRoute = legacyRoute
        self.sourceProcessID = sourceProcessID
        self.isInTmux = isInTmux
        self.isSSHRemote = isSSHRemote
    }

    public init(sessionID: String, jumpTarget: JumpTarget, customActivationURL: URL? = nil, isSSHRemote: Bool = false) {
        self.init(
            sessionID: sessionID,
            controllingTTY: jumpTarget.terminalTTY,
            workingDirectory: jumpTarget.workingDirectory.map(URL.init(fileURLWithPath:)),
            owningBundleID: JumpBundleIdentifier.bundleID(forTerminalName: jumpTarget.terminalApp),
            paneTitle: jumpTarget.paneTitle,
            workspaceName: jumpTarget.workspaceName,
            terminalSessionID: jumpTarget.terminalSessionID,
            tmuxTarget: jumpTarget.tmuxTarget,
            tmuxSocketPath: jumpTarget.tmuxSocketPath,
            warpPaneUUID: jumpTarget.warpPaneUUID,
            customActivationURL: customActivationURL,
            legacyRoute: sessionID,
            sourceProcessID: nil,
            isInTmux: jumpTarget.tmuxTarget != nil,
            isSSHRemote: isSSHRemote
        )
    }
}

public struct JumpContext: Sendable, Equatable {
    public var frontmostBundleID: String?
    public var runningBundleIDs: Set<String>
    public var capturedAt: Date

    public init(
        frontmostBundleID: String? = nil,
        runningBundleIDs: Set<String> = [],
        capturedAt: Date = .now
    ) {
        self.frontmostBundleID = frontmostBundleID
        self.runningBundleIDs = runningBundleIDs
        self.capturedAt = capturedAt
    }
}

public enum NoLocalHandleReason: String, Error, CaseIterable, Codable, Sendable {
    case ttyUnavailable
    case owningAppNotRunning
    case windowNotFound
    case tabNotFound
    case paneNotFound
    case tmuxSessionDetached
    case sshRemoteUnsupported
    case permissionDeniedAppleEvents
    case ambiguousMultipleMatches
    case resolverUnsupported
}

public struct ResolvedLocation: Sendable, Equatable {
    public var appBundleID: String
    public var windowID: CGWindowID?
    public var tabIdentifier: String?
    public var paneIdentifier: String?
    public var activationURL: URL?
    public var focusIdentityData: Data?

    public init(
        appBundleID: String,
        windowID: CGWindowID? = nil,
        tabIdentifier: String? = nil,
        paneIdentifier: String? = nil,
        activationURL: URL? = nil,
        focusIdentityData: Data? = nil
    ) {
        self.appBundleID = appBundleID
        self.windowID = windowID
        self.tabIdentifier = tabIdentifier
        self.paneIdentifier = paneIdentifier
        self.activationURL = activationURL
        self.focusIdentityData = focusIdentityData
    }

    public func merging(_ other: ResolvedLocation) -> ResolvedLocation {
        ResolvedLocation(
            appBundleID: appBundleID.isEmpty ? other.appBundleID : appBundleID,
            windowID: windowID ?? other.windowID,
            tabIdentifier: tabIdentifier ?? other.tabIdentifier,
            paneIdentifier: other.paneIdentifier ?? paneIdentifier,
            activationURL: activationURL ?? other.activationURL,
            focusIdentityData: focusIdentityData ?? other.focusIdentityData
        )
    }
}

public protocol LocationResolver: Sendable {
    static var owningBundleIDs: [String] { get }
    var supportedBundleIDs: [String] { get }
    func resolve(
        _ input: JumpInput,
        in context: JumpContext
    ) -> Result<ResolvedLocation, NoLocalHandleReason>
}

public extension LocationResolver {
    var supportedBundleIDs: [String] { Self.owningBundleIDs }

    func supports(_ input: JumpInput) -> Bool {
        guard let bundleID = input.owningBundleID else {
            return supportedBundleIDs.isEmpty
        }
        return supportedBundleIDs.contains(bundleID)
    }
}

public protocol FocusIdentity: Sendable, Equatable {
    associatedtype SurfaceID: Hashable & Sendable
    var bundleID: String { get }
    var windowID: CGWindowID? { get }
    var surfaceID: SurfaceID? { get }
    func isSameSurface(as other: Self) -> Bool
}

public extension FocusIdentity {
    func isSameSurface(as other: Self) -> Bool {
        bundleID == other.bundleID
            && windowID == other.windowID
            && surfaceID == other.surfaceID
    }
}

public struct TerminalFocusIdentity: FocusIdentity {
    public var bundleID: String
    public var windowID: CGWindowID?
    public var surfaceID: String?

    public init(bundleID: String, windowID: CGWindowID?, surfaceID: String?) {
        self.bundleID = bundleID
        self.windowID = windowID
        self.surfaceID = surfaceID
    }
}

public enum JumpBundleIdentifier {
    public static let terminal = "com.apple.Terminal"
    public static let iterm = "com.googlecode.iterm2"
    public static let ghostty = "com.mitchellh.ghostty"
    public static let warp = "dev.warp.Warp-Stable"

    public static func bundleID(forTerminalName name: String) -> String? {
        switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "terminal", "terminal.app", "apple_terminal": terminal
        case "iterm", "iterm2", "iterm.app": iterm
        case "ghostty": ghostty
        case "warp", "warpterminal": warp
        default: nil
        }
    }
}

public enum JumpDegradationLevel: String, Sendable, Equatable {
    case resolver
    case customURLScheme
    case legacyRoute
    case continueInTerminal
}

public extension JumpDegradationLevel {
    static var urlScheme: JumpDegradationLevel { .customURLScheme }
    static var legacy: JumpDegradationLevel { .legacyRoute }
}

public enum JumpStep: Sendable, Equatable {
    case activateApp(bundleID: String)
    case focusWindow(appBundleID: String, windowID: CGWindowID)
    case selectTab(appBundleID: String, identifier: String)
    case selectPane(appBundleID: String, identifier: String)
    case openURL(URL)
    case legacyRoute(String)
    case continueInTerminal(workingDirectory: URL?)
}

public struct JumpAttempt: Sendable, Equatable {
    public var degradation: JumpDegradationLevel
    public var steps: [JumpStep]

    public init(degradation: JumpDegradationLevel, steps: [JumpStep]) {
        self.degradation = degradation
        self.steps = steps
    }

    public init(level: JumpDegradationLevel, steps: [JumpStep]) {
        self.init(degradation: level, steps: steps)
    }

    public var level: JumpDegradationLevel { degradation }
}

public struct JumpPlan: Sendable, Equatable {
    public var attempts: [JumpAttempt]
    public var primaryFailure: NoLocalHandleReason?

    public init(attempts: [JumpAttempt], primaryFailure: NoLocalHandleReason? = nil) {
        self.attempts = attempts
        self.primaryFailure = primaryFailure
    }

    public init(attempts: [JumpAttempt], primaryFailureReason: NoLocalHandleReason?) {
        self.init(attempts: attempts, primaryFailure: primaryFailureReason)
    }

    public var steps: [JumpStep] { attempts.first?.steps ?? [] }
    public var primaryFailureReason: NoLocalHandleReason? { primaryFailure }
}

public struct JumpExecutionResult: Sendable, Equatable {
    public var succeeded: Bool
    public var completedLevel: JumpDegradationLevel?
    public var attemptedLevels: [JumpDegradationLevel]
    public var failedStep: JumpStep?

    public init(
        succeeded: Bool,
        completedLevel: JumpDegradationLevel?,
        attemptedLevels: [JumpDegradationLevel],
        failedStep: JumpStep?
    ) {
        self.succeeded = succeeded
        self.completedLevel = completedLevel
        self.attemptedLevels = attemptedLevels
        self.failedStep = failedStep
    }
}
