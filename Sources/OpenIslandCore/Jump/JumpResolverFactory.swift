import Foundation

public protocol SkeletonLocationResolver: LocationResolver {}

public extension SkeletonLocationResolver {
    func resolve(
        _ input: JumpInput,
        in context: JumpContext
    ) -> Result<ResolvedLocation, NoLocalHandleReason> {
        .failure(.resolverUnsupported)
    }
}

public struct WezTermResolver: SkeletonLocationResolver {
    public static let owningBundleIDs = ["com.github.wez.wezterm"]
    public init() {}
}

public struct KittyResolver: SkeletonLocationResolver {
    public static let owningBundleIDs = ["net.kovidgoyal.kitty"]
    public init() {}
}

public struct ZedResolver: SkeletonLocationResolver {
    public static let owningBundleIDs = ["dev.zed.Zed"]
    public init() {}
}

public struct OrcaResolver: SkeletonLocationResolver {
    public static let owningBundleIDs: [String] = []
    public init() {}
}

public struct SupacodeResolver: SkeletonLocationResolver {
    public static let owningBundleIDs: [String] = []
    public init() {}
}

public struct SupersetResolver: SkeletonLocationResolver {
    public static let owningBundleIDs: [String] = []
    public init() {}
}

public struct OttyResolver: SkeletonLocationResolver {
    public static let owningBundleIDs: [String] = []
    public init() {}
}

public struct CmuxResolver: SkeletonLocationResolver {
    public static let owningBundleIDs: [String] = []
    public init() {}
}

public struct CustomURLSchemeResolver: LocationResolver {
    public static let owningBundleIDs: [String] = []

    public init() {}

    public func resolve(
        _ input: JumpInput,
        in context: JumpContext
    ) -> Result<ResolvedLocation, NoLocalHandleReason> {
        guard let url = input.customActivationURL else {
            return .failure(.resolverUnsupported)
        }
        return .success(ResolvedLocation(
            appBundleID: input.owningBundleID ?? context.frontmostBundleID ?? "",
            activationURL: url
        ))
    }
}

public enum JumpResolverFactory {
    public static func resolvers() -> [any LocationResolver] {
        [
            TerminalAppResolver(),
            ItermResolver(),
            WarpResolver(),
            GhosttyResolver(),
            WezTermResolver(),
            KittyResolver(),
            ZedResolver(),
            TmuxResolver(),
            OrcaResolver(),
            SupacodeResolver(),
            SupersetResolver(),
            OttyResolver(),
            CmuxResolver(),
            CustomURLSchemeResolver(),
        ]
    }
}
