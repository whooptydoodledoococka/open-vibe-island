import Foundation

/// Pure transition-token policy for delayed overlay callbacks.
///
/// The coordinator owns scheduling and state mutation. This module only
/// decides whether a callback still belongs to the transition that created it.
struct OverlayTransitionPolicy: Sendable {
    struct Token: Equatable, Sendable {
        let generation: UInt64
    }

    private(set) var generation: UInt64 = 0

    mutating func beginTransition() -> Token {
        generation &+= 1
        return Token(generation: generation)
    }

    func accepts(_ token: Token) -> Bool {
        token.generation == generation
    }

    static let popDelay: TimeInterval = OrbitMotionTokens.popDuration
    static let bootOpenDelay: TimeInterval = 0.5
    static let bootCloseDelay: TimeInterval = 1.5
}
