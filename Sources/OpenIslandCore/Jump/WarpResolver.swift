import Foundation
import Darwin

public struct WarpResolver: LocationResolver {
    public static let owningBundleIDs = [
        JumpBundleIdentifier.warp,
        "dev.warp.Warp-Beta",
    ]

    public typealias RunningProbe = @Sendable (String) -> Bool
    public typealias PaneLookup = @Sendable (String) -> String?
    public typealias ProcessContextLookup = @Sendable (pid_t) -> WarpProcessResolver.PaneContext?
    public typealias ProcessPaneLookup = @Sendable (pid_t, pid_t) -> String?

    private let isRunning: RunningProbe
    private let paneLookup: PaneLookup
    private let processContextLookup: ProcessContextLookup
    private let processPaneLookup: ProcessPaneLookup

    public init(
        isRunning: @escaping RunningProbe = JumpRuntime.isApplicationRunning(bundleID:),
        paneLookup: @escaping PaneLookup = { WarpSQLiteReader().lookupPaneUUID(forCwd: $0) },
        processContextLookup: ProcessContextLookup? = nil,
        processPaneLookup: ProcessPaneLookup? = nil
    ) {
        self.isRunning = isRunning
        self.paneLookup = paneLookup
        self.processContextLookup = processContextLookup ?? Self.liveProcessContext
        self.processPaneLookup = processPaneLookup ?? Self.liveProcessPane
    }

    public func resolve(
        _ input: JumpInput,
        in context: JumpContext
    ) -> Result<ResolvedLocation, NoLocalHandleReason> {
        let requestedBundleID = input.owningBundleID ?? Self.owningBundleIDs[0]
        guard Self.owningBundleIDs.contains(requestedBundleID) else {
            return .failure(.resolverUnsupported)
        }
        guard isRunning(requestedBundleID) else { return .failure(.owningAppNotRunning) }

        if let paneUUID = input.warpPaneUUID?.trimmingCharacters(in: .whitespacesAndNewlines), !paneUUID.isEmpty {
            return .success(ResolvedLocation(appBundleID: requestedBundleID, paneIdentifier: paneUUID))
        }

        if let sourceProcessID = input.sourceProcessID,
           let paneContext = processContextLookup(pid_t(sourceProcessID)),
           let paneUUID = processPaneLookup(paneContext.shellPID, paneContext.terminalServerPID) {
            return .success(ResolvedLocation(appBundleID: requestedBundleID, paneIdentifier: paneUUID))
        }

        guard let path = input.workingDirectory?.standardizedFileURL.path else {
            return .failure(.paneNotFound)
        }
        guard let paneUUID = paneLookup(path) else { return .failure(.paneNotFound) }
        return .success(ResolvedLocation(appBundleID: requestedBundleID, paneIdentifier: paneUUID))
    }

    private static func liveProcessContext(_ sourcePID: pid_t) -> WarpProcessResolver.PaneContext? {
        WarpProcessResolver.resolvePaneContext(
            startingFrom: sourcePID,
            parentPIDProvider: WarpProcessResolver.defaultParentPIDProvider,
            commandProvider: WarpProcessResolver.defaultCommandProvider
        )
    }

    private static func liveProcessPane(_ shellPID: pid_t, _ terminalServerPID: pid_t) -> String? {
        WarpSQLiteReader().lookupPaneUUIDByShellPID(
            shellPID,
            terminalServerPID: terminalServerPID
        )
    }
}
