import Testing
@testable import OpenIslandApp

struct InstallHooksHintPolicyTests {
    @Test
    func appearsOnlyForUnresolvedEmptyFirstRun() {
        #expect(InstallHooksHintPolicy.shouldShow(
            hasInstalledAgent: false,
            onboardingCompleted: false,
            hasSessions: false,
            isResolvingSessions: false
        ))
    }

    @Test
    func installedAgentSuppressesHint() {
        #expect(!InstallHooksHintPolicy.shouldShow(
            hasInstalledAgent: true,
            onboardingCompleted: false,
            hasSessions: false,
            isResolvingSessions: false
        ))
    }

    @Test
    func completedOrSkippedOnboardingSuppressesHint() {
        #expect(!InstallHooksHintPolicy.shouldShow(
            hasInstalledAgent: false,
            onboardingCompleted: true,
            hasSessions: false,
            isResolvingSessions: false
        ))
    }

    @Test
    func observedSessionsSuppressRepeatedHint() {
        #expect(!InstallHooksHintPolicy.shouldShow(
            hasInstalledAgent: false,
            onboardingCompleted: false,
            hasSessions: true,
            isResolvingSessions: false
        ))
    }

    @Test
    func discoveryLoadingSuppressesPrematureHint() {
        #expect(!InstallHooksHintPolicy.shouldShow(
            hasInstalledAgent: false,
            onboardingCompleted: false,
            hasSessions: false,
            isResolvingSessions: true
        ))
    }
}
