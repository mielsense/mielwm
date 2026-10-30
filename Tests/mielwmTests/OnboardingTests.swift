@testable import mielwm
import Testing

// The welcome window, built but never shown.

@MainActor @Test func closingTheWelcomeWindowEndsOnboarding() {
    var finished = 0
    let onboarding = Onboarding(note: nil) { finished += 1 }
    onboarding.window.close()
    #expect(finished == 1)
}

@MainActor @Test func continueThenCloseEndsOnboardingOnce() {
    var finished = 0
    let onboarding = Onboarding(note: nil) { finished += 1 }
    onboarding.model.finish()
    onboarding.window.close()
    #expect(finished == 1)
}
