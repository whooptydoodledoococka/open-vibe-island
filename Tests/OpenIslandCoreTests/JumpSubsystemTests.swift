import Foundation
import Testing
@testable import OpenIslandCore

struct JumpSubsystemTests {
    @Test
    func registryFixturesMapTTYMultiplexerAndUnknownTerminal() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let tty = try decoder.decode(RegistryRecord.self, from: Data(Self.ttyFixture.utf8))
        let multiplexer = try decoder.decode(RegistryRecord.self, from: Data(Self.multiplexerFixture.utf8))
        let unknown = try decoder.decode(RegistryRecord.self, from: Data(Self.unknownFixture.utf8))

        #expect(tty.jumpInput.controllingTTY == "/dev/ttys001")
        #expect(tty.jumpInput.owningBundleID == TerminalAppResolver.owningBundleIDs.first)
        #expect(multiplexer.jumpInput.isInTmux)
        #expect(multiplexer.jumpInput.tmuxTarget == "work:2.1")
        #expect(unknown.jumpInput.owningBundleID == nil)
        #expect(unknown.jumpInput.controllingTTY == nil)
    }

    @Test
    func terminalResolverMatchesTTYAndRejectsAmbiguity() {
        let input = JumpInput(
            sessionID: "session-terminal",
            controllingTTY: "ttys001",
            owningBundleID: TerminalAppResolver.owningBundleIDs[0]
        )
        let surfaces = [
            TerminalSurface(tty: "/dev/ttys001", windowID: 41, tabIndex: 2),
            TerminalSurface(tty: "/dev/ttys002", windowID: 42, tabIndex: 1),
        ]
        let resolver = TerminalAppResolver(isRunning: { _ in true }, surfaceProvider: { .success(surfaces) })

        #expect(resolver.resolve(input, in: JumpContext()) == .success(
            ResolvedLocation(
                appBundleID: TerminalAppResolver.owningBundleIDs[0],
                windowID: 41,
                tabIdentifier: "2",
                paneIdentifier: nil
            )
        ))

        let ambiguous = TerminalAppResolver(
            isRunning: { _ in true },
            surfaceProvider: { .success([surfaces[0], surfaces[0]]) }
        )
        #expect(ambiguous.resolve(input, in: JumpContext()) == .failure(.ambiguousMultipleMatches))
    }

    @Test
    func itermResolverMatchesTTYToStableSessionIdentity() {
        let input = JumpInput(
            sessionID: "session-iterm",
            controllingTTY: "/dev/ttys003",
            owningBundleID: ItermResolver.owningBundleIDs[0]
        )
        let resolver = ItermResolver(
            isRunning: { _ in true },
            surfaceProvider: {
                .success([ItermSurface(tty: "/dev/ttys003", windowID: 9, sessionID: "session-guid")])
            }
        )

        let result = resolver.resolve(input, in: JumpContext())
        #expect(result == .success(ResolvedLocation(
            appBundleID: ItermResolver.owningBundleIDs[0],
            windowID: 9,
            tabIdentifier: "session-guid",
            paneIdentifier: nil
        )))
    }

    @Test
    func ghosttyResolverUsesStableSessionThenUniquePath() {
        let surfaces = [
            GhosttySurface(sessionID: "terminal-1", workingDirectory: "/tmp/one", title: "one", tty: nil),
            GhosttySurface(sessionID: "terminal-2", workingDirectory: "/tmp/two", title: "two", tty: nil),
        ]
        let resolver = GhosttyResolver(isRunning: { _ in true }, surfaceProvider: { .success(surfaces) })

        let byIdentity = JumpInput(
            sessionID: "agent",
            workingDirectory: URL(fileURLWithPath: "/tmp/one"),
            owningBundleID: GhosttyResolver.owningBundleIDs[0],
            terminalSessionID: "terminal-2"
        )
        #expect(resolver.resolve(byIdentity, in: JumpContext()).successValue?.tabIdentifier == "terminal-2")

        let byPath = JumpInput(
            sessionID: "agent",
            workingDirectory: URL(fileURLWithPath: "/tmp/one"),
            owningBundleID: GhosttyResolver.owningBundleIDs[0]
        )
        #expect(resolver.resolve(byPath, in: JumpContext()).successValue?.tabIdentifier == "terminal-1")
    }

    @Test
    func tmuxProbeParsesListPanesAndResolverMatchesTTY() {
        let probe = TmuxHostProbe(commandRunner: { _, _ in
            JumpCommandResult(
                exitCode: 0,
                stdout: "/dev/ttys004 work:2.1\n/dev/ttys005 other:0.0\n",
                stderr: ""
            )
        })
        #expect(probe.listPanes(socketPath: nil) == .success([
            TmuxPane(tty: "/dev/ttys004", target: "work:2.1"),
            TmuxPane(tty: "/dev/ttys005", target: "other:0.0"),
        ]))

        let resolver = TmuxResolver(hostProbe: probe)
        let input = JumpInput(
            sessionID: "session-tmux",
            controllingTTY: "/dev/ttys004",
            owningBundleID: TerminalAppResolver.owningBundleIDs[0],
            isInTmux: true
        )
        #expect(resolver.resolve(input, in: JumpContext()).successValue?.paneIdentifier == "work:2.1")
    }

    @Test
    func warpResolverUsesProcessIdentityBeforeExistingCWDLookup() {
        let resolver = WarpResolver(
            isRunning: { _ in true },
            paneLookup: { _ in "CWD-PANE" },
            processContextLookup: { _ in .init(shellPID: 401, terminalServerPID: 88) },
            processPaneLookup: { $0 == 401 && $1 == 88 ? "PROCESS-PANE" : nil }
        )
        let input = JumpInput(
            sessionID: "session-warp",
            workingDirectory: URL(fileURLWithPath: "/tmp/project"),
            owningBundleID: WarpResolver.owningBundleIDs[0],
            sourceProcessID: 900
        )
        #expect(resolver.resolve(input, in: JumpContext()).successValue?.paneIdentifier == "PROCESS-PANE")
    }

    @Test
    func factoryContainsRealFleetAndRegisteredSkeletons() {
        let names = JumpResolverFactory.resolvers().map { String(describing: type(of: $0)) }
        for expected in [
            "TerminalAppResolver", "ItermResolver", "WarpResolver", "GhosttyResolver", "TmuxResolver",
            "WezTermResolver", "KittyResolver", "ZedResolver", "OrcaResolver", "SupacodeResolver",
            "SupersetResolver", "OttyResolver", "CmuxResolver", "CustomURLSchemeResolver",
        ] {
            #expect(names.contains(expected))
        }
    }

    @Test
    func failureEnumCoversEverySpecifiedReason() {
        #expect(Set(NoLocalHandleReason.allCases) == [
            .ttyUnavailable, .owningAppNotRunning, .windowNotFound, .tabNotFound, .paneNotFound,
            .tmuxSessionDetached, .sshRemoteUnsupported, .permissionDeniedAppleEvents,
            .ambiguousMultipleMatches, .resolverUnsupported,
        ])
    }

    @Test
    func plannerBuildsEveryAvailableDegradationAttempt() {
        let primary = StubResolver(
            bundleIDs: ["app.terminal"],
            result: .success(ResolvedLocation(
                appBundleID: "app.terminal",
                windowID: 7,
                tabIdentifier: "tab-2",
                paneIdentifier: nil
            ))
        )
        let url = URL(string: "orbit-terminal://session/123")!
        let planner = JumpPlanner(
            resolvers: [primary],
            customURLResolver: CustomURLSchemeResolver(),
            legacyRouteProvider: { _ in "legacy-session-123" }
        )
        let plan = planner.plan(
            for: JumpInput(
                sessionID: "123",
                owningBundleID: "app.terminal",
                customActivationURL: url
            ),
            in: JumpContext()
        )

        let expectedLevels: [JumpDegradationLevel] = [.resolver, .customURLScheme, .legacyRoute, .continueInTerminal]
        let expectedSteps: [JumpStep] = [.continueInTerminal(workingDirectory: nil)]
        #expect(plan.attempts.map(\.degradation) == expectedLevels)
        #expect(plan.attempts.last?.steps == expectedSteps)
    }

    @Test
    @MainActor
    func executorFallsThroughFailedAttemptsAndNeverDeadEnds() {
        let recorder = ExecutionRecorder()
        let environment = JumpExecutionEnvironment(
            activateApp: { _ in throw TestFailure.operationFailed },
            focusWindow: { _, _ in },
            selectTab: { _, _ in },
            selectPane: { _, _ in },
            openURL: { _ in throw TestFailure.operationFailed },
            legacyRoute: { route in recorder.events.append("legacy:\(route)"); throw TestFailure.operationFailed },
            continueInTerminal: { url in recorder.events.append("terminal:\(url?.path ?? "none")") }
        )
        let plan = JumpPlan(attempts: [
            JumpAttempt(degradation: .resolver, steps: [.activateApp(bundleID: "app.terminal")]),
            JumpAttempt(degradation: .customURLScheme, steps: [.openURL(URL(string: "orbit-terminal://session")!)]),
            JumpAttempt(degradation: .legacyRoute, steps: [.legacyRoute("session")]),
            JumpAttempt(degradation: .continueInTerminal, steps: [.continueInTerminal(workingDirectory: URL(fileURLWithPath: "/tmp/project"))]),
        ])

        let result = JumpExecutor(environment: environment).execute(plan)
        #expect(result.succeeded)
        #expect(result.completedLevel == .continueInTerminal)
        #expect(result.attemptedLevels == [.resolver, .customURLScheme, .legacyRoute, .continueInTerminal])
        #expect(recorder.events == ["legacy:session", "terminal:/tmp/project"])
    }
}

private extension JumpSubsystemTests {
    struct RegistryRecord: Decodable {
        struct RegistryTarget: Decodable {
            var terminalApp: String
            var terminalTTY: String?
            var paneTitle: String?
            var workingDirectory: String?
            var workspaceName: String?
            var tmuxTarget: String?
        }

        var sessionID: String
        var jumpTarget: RegistryTarget

        var jumpInput: JumpInput {
            JumpInput(
                sessionID: sessionID,
                controllingTTY: jumpTarget.terminalTTY,
                workingDirectory: jumpTarget.workingDirectory.map(URL.init(fileURLWithPath:)),
                owningBundleID: Self.bundleID(for: jumpTarget.terminalApp),
                paneTitle: jumpTarget.paneTitle,
                workspaceName: jumpTarget.workspaceName,
                tmuxTarget: jumpTarget.tmuxTarget,
                isInTmux: jumpTarget.tmuxTarget != nil
            )
        }

        static func bundleID(for app: String) -> String? {
            switch app.lowercased() {
            case "terminal": TerminalAppResolver.owningBundleIDs.first
            case "iterm": ItermResolver.owningBundleIDs.first
            case "ghostty": GhosttyResolver.owningBundleIDs.first
            case "warp": WarpResolver.owningBundleIDs.first
            default: nil
            }
        }
    }

    static let ttyFixture = #"{"sessionID":"session-tty","jumpTarget":{"terminalApp":"Terminal","terminalTTY":"/dev/ttys001","paneTitle":"agent","workingDirectory":"/tmp/project","workspaceName":"project"}}"#
    static let multiplexerFixture = #"{"sessionID":"session-tmux","jumpTarget":{"terminalApp":"Terminal","terminalTTY":"/dev/ttys004","paneTitle":"agent","workingDirectory":"/tmp/project","workspaceName":"project","tmuxTarget":"work:2.1"}}"#
    static let unknownFixture = #"{"sessionID":"session-unknown","jumpTarget":{"terminalApp":"Unknown","paneTitle":"agent","workingDirectory":"/tmp/project","workspaceName":"project"}}"#
}

private struct StubResolver: LocationResolver {
    static let owningBundleIDs: [String] = []
    let bundleIDs: [String]
    let result: Result<ResolvedLocation, NoLocalHandleReason>

    var supportedBundleIDs: [String] { bundleIDs }

    func resolve(_ input: JumpInput, in context: JumpContext) -> Result<ResolvedLocation, NoLocalHandleReason> {
        result
    }
}

@MainActor
private final class ExecutionRecorder {
    var events: [String] = []
}

private enum TestFailure: Error {
    case operationFailed
}

private extension Result {
    var successValue: Success? {
        guard case .success(let value) = self else { return nil }
        return value
    }
}
