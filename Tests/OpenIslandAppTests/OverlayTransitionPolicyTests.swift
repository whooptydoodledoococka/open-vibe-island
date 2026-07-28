import Testing
@testable import OpenIslandApp

struct OverlayTransitionPolicyTests {
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
