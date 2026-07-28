import Testing
@testable import OpenIslandApp

struct OverlayTransitionPolicyTests {
    @Test func reducedMotionPolicyRemovesAnimationAndDelay() {
        let policy = OrbitMotionPolicy(reducesMotion: true)

        #expect(policy.reducesMotion)
        #expect(policy.animation(.linear(duration: 1)) == nil)
        #expect(policy.delay(0.3) == 0)
    }

    @Test func standardMotionPolicyPreservesAnimationAndDelay() {
        let policy = OrbitMotionPolicy(reducesMotion: false)

        #expect(policy.animation(.linear(duration: 1)) != nil)
        #expect(policy.delay(0.3) == 0.3)
    }

    @Test
    func newTransitionInvalidatesPreviousToken() {
        var policy = OverlayTransitionPolicy()
        let first = policy.beginTransition()
        #expect(policy.accepts(first))

        let second = policy.beginTransition()
        #expect(!policy.accepts(first))
        #expect(policy.accepts(second))
    }

    @Test
    func initialTokenIsNotAcceptedAfterNoTransition() {
        var policy = OverlayTransitionPolicy()
        let token = policy.beginTransition()
        #expect(policy.accepts(token))
    }

    @Test
    func preservesExistingTransitionDelays() {
        #expect(OverlayTransitionPolicy.popDelay == 0.3)
        #expect(OverlayTransitionPolicy.bootOpenDelay == 0.5)
        #expect(OverlayTransitionPolicy.bootCloseDelay == 1.5)
    }
}
