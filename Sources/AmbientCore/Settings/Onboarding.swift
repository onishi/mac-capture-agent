import Foundation

/// First-run guide steps and their state.
public enum OnboardingStep: Int, CaseIterable, Sendable, Identifiable {
    case briefing
    case screenAccess
    case translation
    case appleIntelligence
    /// What the on-device knowledge can and cannot do (no cloud, estimates).
    case localKnowledge
    case privacy

    public var id: Int { rawValue }

    /// Steps the app cannot work without.
    public var isRequired: Bool { self == .screenAccess }

    public var code: String { String(format: "%02d", rawValue + 1) }
}

public enum OnboardingStatus: String, Sendable, Equatable {
    case done
    case pending
    case optional
    case unavailable
}

public struct OnboardingState: Sendable, Equatable {
    public var screenRecordingGranted: Bool
    public var appleIntelligenceAvailable: Bool
    public var visitedSteps: Set<OnboardingStep>

    public init(screenRecordingGranted: Bool, appleIntelligenceAvailable: Bool, visitedSteps: Set<OnboardingStep> = []) {
        self.screenRecordingGranted = screenRecordingGranted
        self.appleIntelligenceAvailable = appleIntelligenceAvailable
        self.visitedSteps = visitedSteps
    }

    public func status(of step: OnboardingStep) -> OnboardingStatus {
        switch step {
        case .briefing, .privacy, .translation, .localKnowledge:
            return visitedSteps.contains(step) ? .done : .pending
        case .screenAccess:
            return screenRecordingGranted ? .done : .pending
        case .appleIntelligence:
            return appleIntelligenceAvailable ? .done : .unavailable
        }
    }

    /// The guide can be finished once every required step is done.
    public var canFinish: Bool {
        OnboardingStep.allCases.filter(\.isRequired).allSatisfy { status(of: $0) == .done }
    }

    /// The first step that still needs attention.
    public var nextStep: OnboardingStep? {
        OnboardingStep.allCases.first { status(of: $0) == .pending }
    }
}
