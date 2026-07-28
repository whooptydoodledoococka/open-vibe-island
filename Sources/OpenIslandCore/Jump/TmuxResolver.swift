import Foundation

public struct TmuxPane: Sendable, Equatable {
    public var tty: String
    public var target: String

    public init(tty: String, target: String) {
        self.tty = tty
        self.target = target
    }
}

public struct TmuxHostProbe: Sendable {
    private let commandRunner: JumpCommandRunner

    public init(commandRunner: @escaping JumpCommandRunner = JumpRuntime.runCommand(executable:arguments:)) {
        self.commandRunner = commandRunner
    }

    public func listPanes(socketPath: String?) -> Result<[TmuxPane], NoLocalHandleReason> {
        var arguments = ["tmux"]
        if let socketPath = socketPath?.trimmingCharacters(in: .whitespacesAndNewlines), !socketPath.isEmpty {
            arguments += ["-S", socketPath]
        }
        arguments += ["list-panes", "-a", "-F", "#{pane_tty} #{session_name}:#{window_index}.#{pane_index}"]

        let result = commandRunner(URL(fileURLWithPath: "/usr/bin/env"), arguments)
        guard result.exitCode == 0 else { return .failure(.tmuxSessionDetached) }
        let panes = result.stdout
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> TmuxPane? in
                let values = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
                guard values.count == 2 else { return nil }
                return TmuxPane(tty: String(values[0]), target: String(values[1]))
            }
        return .success(panes)
    }
}

public struct TmuxResolver: LocationResolver {
    public static let owningBundleIDs: [String] = []
    private let hostProbe: TmuxHostProbe

    public init(hostProbe: TmuxHostProbe = TmuxHostProbe()) {
        self.hostProbe = hostProbe
    }

    public func resolve(
        _ input: JumpInput,
        in context: JumpContext
    ) -> Result<ResolvedLocation, NoLocalHandleReason> {
        guard input.isInTmux || input.tmuxTarget != nil else {
            return .failure(.resolverUnsupported)
        }

        switch hostProbe.listPanes(socketPath: input.tmuxSocketPath) {
        case .failure(let reason):
            return .failure(reason)
        case .success(let panes):
            let matches: [TmuxPane]
            if let target = input.tmuxTarget?.trimmingCharacters(in: .whitespacesAndNewlines), !target.isEmpty {
                matches = panes.filter { $0.target == target }
            } else if let tty = JumpRuntime.normalizedTTY(input.controllingTTY) {
                matches = panes.filter { JumpRuntime.normalizedTTY($0.tty) == tty }
            } else {
                return .failure(.ttyUnavailable)
            }

            guard matches.count <= 1 else { return .failure(.ambiguousMultipleMatches) }
            guard let match = matches.first else { return .failure(.paneNotFound) }
            return .success(ResolvedLocation(
                appBundleID: input.owningBundleID ?? context.frontmostBundleID ?? JumpBundleIdentifier.terminal,
                paneIdentifier: match.target
            ))
        }
    }
}
