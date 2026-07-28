import CoreGraphics
import Foundation

public struct TerminalSurface: Sendable, Equatable {
    public var tty: String
    public var windowID: CGWindowID
    public var tabIndex: Int

    public init(tty: String, windowID: CGWindowID, tabIndex: Int) {
        self.tty = tty
        self.windowID = windowID
        self.tabIndex = tabIndex
    }
}

public struct TerminalAppResolver: LocationResolver {
    public static let owningBundleIDs = [JumpBundleIdentifier.terminal]

    public typealias RunningProbe = @Sendable (String) -> Bool
    public typealias SurfaceProvider = @Sendable () -> Result<[TerminalSurface], NoLocalHandleReason>

    private let isRunning: RunningProbe
    private let surfaceProvider: SurfaceProvider

    public init(
        isRunning: @escaping RunningProbe = JumpRuntime.isApplicationRunning(bundleID:),
        surfaceProvider: SurfaceProvider? = nil
    ) {
        self.isRunning = isRunning
        self.surfaceProvider = surfaceProvider ?? TerminalAppResolver.liveSurfaces
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
                tabIdentifier: String(match.tabIndex),
                paneIdentifier: nil
            ))
        }
    }

    private static func liveSurfaces() -> Result<[TerminalSurface], NoLocalHandleReason> {
        let script = """
        set fieldSeparator to ASCII character 31
        set recordSeparator to ASCII character 30
        tell application "Terminal"
            if not (it is running) then return ""
            set outputLines to {}
            repeat with aWindow in windows
                set windowID to id of aWindow as text
                set tabNumber to 0
                repeat with aTab in tabs of aWindow
                    set tabNumber to tabNumber + 1
                    set tabTTY to ""
                    try
                        set tabTTY to tty of aTab as text
                    end try
                    set end of outputLines to tabTTY & fieldSeparator & windowID & fieldSeparator & (tabNumber as text)
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
            let surfaces = rows.compactMap { values -> TerminalSurface? in
                guard values.count == 3,
                      let windowID = CGWindowID(values[1]),
                      let tabIndex = Int(values[2]) else { return nil }
                return TerminalSurface(tty: values[0], windowID: windowID, tabIndex: tabIndex)
            }
            return .success(surfaces)
        }
    }
}
