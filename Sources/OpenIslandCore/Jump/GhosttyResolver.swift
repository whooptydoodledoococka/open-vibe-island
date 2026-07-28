import Foundation

public struct GhosttySurface: Sendable, Equatable {
    public var sessionID: String
    public var workingDirectory: String?
    public var title: String?
    public var tty: String?

    public init(sessionID: String, workingDirectory: String?, title: String?, tty: String?) {
        self.sessionID = sessionID
        self.workingDirectory = workingDirectory
        self.title = title
        self.tty = tty
    }
}

public struct GhosttyResolver: LocationResolver {
    public static let owningBundleIDs = [JumpBundleIdentifier.ghostty]

    public typealias RunningProbe = @Sendable (String) -> Bool
    public typealias SurfaceProvider = @Sendable () -> Result<[GhosttySurface], NoLocalHandleReason>

    private let isRunning: RunningProbe
    private let surfaceProvider: SurfaceProvider

    public init(
        isRunning: @escaping RunningProbe = JumpRuntime.isApplicationRunning(bundleID:),
        surfaceProvider: SurfaceProvider? = nil
    ) {
        self.isRunning = isRunning
        self.surfaceProvider = surfaceProvider ?? GhosttyResolver.liveSurfaces
    }

    public func resolve(
        _ input: JumpInput,
        in context: JumpContext
    ) -> Result<ResolvedLocation, NoLocalHandleReason> {
        let bundleID = Self.owningBundleIDs[0]
        guard isRunning(bundleID) else { return .failure(.owningAppNotRunning) }

        switch surfaceProvider() {
        case .failure(let reason):
            return .failure(reason)
        case .success(let surfaces):
            let matches: [GhosttySurface]
            if let sessionID = nonEmpty(input.terminalSessionID) {
                matches = surfaces.filter { $0.sessionID == sessionID }
            } else if let tty = JumpRuntime.normalizedTTY(input.controllingTTY),
                      surfaces.contains(where: { JumpRuntime.normalizedTTY($0.tty) != nil }) {
                matches = surfaces.filter { JumpRuntime.normalizedTTY($0.tty) == tty }
            } else if let title = nonEmpty(input.paneTitle) {
                matches = surfaces.filter {
                    nonEmpty($0.title)?.localizedCaseInsensitiveCompare(title) == .orderedSame
                }
            } else if let path = JumpRuntime.normalizedPath(input.workingDirectory?.path) {
                matches = surfaces.filter {
                    JumpRuntime.normalizedPath($0.workingDirectory) == path
                }
            } else {
                return .failure(.ttyUnavailable)
            }

            guard matches.count <= 1 else { return .failure(.ambiguousMultipleMatches) }
            guard let match = matches.first else { return .failure(.paneNotFound) }
            return .success(ResolvedLocation(
                appBundleID: bundleID,
                tabIdentifier: match.sessionID,
                paneIdentifier: nil
            ))
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func liveSurfaces() -> Result<[GhosttySurface], NoLocalHandleReason> {
        let script = """
        set fieldSeparator to ASCII character 31
        set recordSeparator to ASCII character 30
        tell application "Ghostty"
            if not (it is running) then return ""
            set outputLines to {}
            repeat with aTerminal in terminals
                set terminalID to ""
                set terminalDirectory to ""
                set terminalTitle to ""
                try
                    set terminalID to id of aTerminal as text
                end try
                try
                    set terminalDirectory to working directory of aTerminal as text
                end try
                try
                    set terminalTitle to name of aTerminal as text
                end try
                set end of outputLines to terminalID & fieldSeparator & terminalDirectory & fieldSeparator & terminalTitle
            end repeat
            set AppleScript's text item delimiters to recordSeparator
            set joinedOutput to outputLines as string
            set AppleScript's text item delimiters to ""
            return joinedOutput
        end tell
        """

        return JumpRuntime.runAppleScript(script).flatMap { output in
            let rows = output
                .split(separator: Character("\u{1e}"), omittingEmptySubsequences: true)
                .map { $0.split(separator: Character("\u{1f}"), omittingEmptySubsequences: false).map(String.init) }
            let surfaces = rows.compactMap { values -> GhosttySurface? in
                guard values.count == 3, !values[0].isEmpty else { return nil }
                return GhosttySurface(
                    sessionID: values[0],
                    workingDirectory: values[1],
                    title: values[2],
                    tty: nil
                )
            }
            return .success(surfaces)
        }
    }
}
