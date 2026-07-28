import Foundation

public struct JumpPlanner: Sendable {
    public typealias LegacyRouteProvider = @Sendable (JumpInput) -> String?

    private let resolvers: [any LocationResolver]
    private let customURLResolver: CustomURLSchemeResolver
    private let legacyRouteProvider: LegacyRouteProvider

    public init(
        resolvers: [any LocationResolver] = JumpResolverFactory.resolvers(),
        customURLResolver: CustomURLSchemeResolver = CustomURLSchemeResolver(),
        legacyRouteProvider: @escaping LegacyRouteProvider = JumpPlanner.defaultLegacyRoute
    ) {
        self.resolvers = resolvers
        self.customURLResolver = customURLResolver
        self.legacyRouteProvider = legacyRouteProvider
    }

    public func plan(for input: JumpInput, in context: JumpContext) -> JumpPlan {
        var attempts: [JumpAttempt] = []
        var primaryFailure: NoLocalHandleReason?

        if !input.isSSHRemote {
            switch resolvePrimary(input, in: context) {
            case .success(let location):
                attempts.append(JumpAttempt(level: .resolver, steps: steps(for: location)))
            case .failure(let reason):
                primaryFailure = reason
            }
        } else {
            primaryFailure = .sshRemoteUnsupported
        }

        if case .success(let location) = customURLResolver.resolve(input, in: context),
           let url = location.activationURL {
            attempts.append(JumpAttempt(level: .urlScheme, steps: [.openURL(url)]))
        }

        if let legacyRoute = legacyRouteProvider(input), !legacyRoute.isEmpty {
            attempts.append(JumpAttempt(level: .legacy, steps: [.legacyRoute(legacyRoute)]))
        }

        attempts.append(JumpAttempt(
            level: .continueInTerminal,
            steps: [.continueInTerminal(workingDirectory: input.workingDirectory)]
        ))

        return JumpPlan(attempts: attempts, primaryFailureReason: primaryFailure)
    }

    public func plan(_ result: Result<ResolvedLocation, NoLocalHandleReason>) -> [JumpStep] {
        switch result {
        case .success(let location):
            return steps(for: location)
        case .failure:
            return [.continueInTerminal(workingDirectory: nil)]
        }
    }

    private func resolvePrimary(
        _ input: JumpInput,
        in context: JumpContext
    ) -> Result<ResolvedLocation, NoLocalHandleReason> {
        let hostResolver = resolvers.first { resolver in
            !(resolver is TmuxResolver)
                && !(resolver is CustomURLSchemeResolver)
                && resolver.supports(input)
        }

        if input.isInTmux || input.tmuxTarget != nil,
           let tmuxResolver = resolvers.first(where: { $0 is TmuxResolver }) {
            let tmuxResult = tmuxResolver.resolve(input, in: context)
            guard case .success(let tmuxLocation) = tmuxResult else { return tmuxResult }

            if let hostResolver {
                switch hostResolver.resolve(input, in: context) {
                case .success(let hostLocation):
                    return .success(ResolvedLocation(
                        appBundleID: hostLocation.appBundleID,
                        windowID: hostLocation.windowID,
                        tabIdentifier: hostLocation.tabIdentifier,
                        paneIdentifier: tmuxLocation.paneIdentifier,
                        activationURL: hostLocation.activationURL,
                        focusIdentityData: hostLocation.focusIdentityData
                    ))
                case .failure(let reason):
                    return .failure(reason)
                }
            }
            return .success(tmuxLocation)
        }

        guard let hostResolver else { return .failure(.resolverUnsupported) }
        return hostResolver.resolve(input, in: context)
    }

    private func steps(for location: ResolvedLocation) -> [JumpStep] {
        if let activationURL = location.activationURL {
            return [.openURL(activationURL)]
        }

        var steps: [JumpStep] = []
        if !location.appBundleID.isEmpty {
            steps.append(.activateApp(bundleID: location.appBundleID))
        }
        if let windowID = location.windowID {
            steps.append(.focusWindow(appBundleID: location.appBundleID, windowID: windowID))
        }
        if let tabIdentifier = location.tabIdentifier {
            steps.append(.selectTab(appBundleID: location.appBundleID, identifier: tabIdentifier))
        }
        if let paneIdentifier = location.paneIdentifier {
            steps.append(.selectPane(appBundleID: location.appBundleID, identifier: paneIdentifier))
        }
        return steps.isEmpty ? [.continueInTerminal(workingDirectory: nil)] : steps
    }

    public static func defaultLegacyRoute(_ input: JumpInput) -> String? {
        if let route = input.legacyRoute?.trimmingCharacters(in: .whitespacesAndNewlines), !route.isEmpty {
            return route
        }
        if input.controllingTTY != nil || input.workingDirectory != nil || input.owningBundleID != nil {
            return input.sessionID
        }
        return nil
    }
}
