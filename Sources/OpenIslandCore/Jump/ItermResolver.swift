import CoreGraphics
import Foundation

public struct ItermSurface: Sendable, Equatable {
    public var tty: String
    public var windowID: CGWindowID?
    public var sessionID: String

    public init(tty: String, windowID: CGWindowID?, sessionID: String) {
        self.tty = tty
        self.windowID = windowID
        self.sessionID = sessionID
    }
}

public struct ItermResolver: LocationResolver {
    public static let owningBundleIDs = [JumpBundleIdentifier.iterm]

    public typealias RunningProbe = @Sendable (String) -> Bool
    public typealias SurfaceProvider = @Sendable () -> Result<[ItermSurface], NoLocalHandleReason>

    private let isRunning: RunningProbe
    private let surfaceProvider: SurfaceProvider

    public init(
        isRunning: @escaping RunningProbe = JumpRuntime.isApplicationRunning(bundleID:),
        surfaceProvider: SurfaceProvider? = nil
    ) {
        self.isRunning = isRunning
        self.surfaceProvider = surfaceProvider ?? ItermResolver.liveSurfaces
    }

    public func resolve(
        _ input: JumpInput,
        in context: JumpContext
    ) -> Result<ResolvedLocation, NoLocalHandleReason> {
        let bundleID = Self.owningBundleIDs[0]
        guard isRunning(bundleID) else { return .failure(.owningAppNotRunning) }
        guard let tty = JumpRuntime.normalizedTTY(input.controllingTTY) else {
            return .failure(.ttyUnavailable)
        }

        switch surfaceProvider() {
        case .failure(let reason):
            return .failure(reason)
        case .success(let surfaces):
            let matches = surfaces.filter { JumpRuntime.normalizedTTY($0.tty) == tty }
            guard matches.count <= 1 else { return .failure(.ambiguousMultipleMatches) }
            guard let match = matches.first else { return .failure(.tabNotFound) }
            return .success(ResolvedLocation(
                appBundleID: bundleID,
                windowID: match.windowID,
                tabIdentifier: match.sessionID,
                paneIdentifier: nil
            ))
        }
    }

    private static func liveSurfaces() -> Result<[ItermSurface], NoLocalHandleReason> {
        let script = """
        set fieldSeparator to ASCII character 31
        set recordSeparator to ASCII character 30
        tell application "iTerm"
            if not (it is running) then return ""
            set outputLines to {}
            repeat with aWindow in windows
                set windowID to id of aWindow as text
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        set sessionTTY to ""
                        set sessionID to ""
                        try
                            set sessionTTY to tty of aSession as text
                        end try
                        try
                            set sessionID to unique id of aSession as text
                        end try
                        set end of outputLines to sessionTTY & fieldSeparator & windowID & fieldSeparator & sessionID
                    end repeat
                end repeat
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
            let surfaces = rows.compactMap { values -> ItermSurface? in
                guard values.count == 3, !values[2].isEmpty else { return nil }
                return ItermSurface(
                    tty: values[0],
                    windowID: CGWindowID(values[1]),
                    sessionID: values[2]
                )
            }
            return .success(surfaces)
        }
    }
}
