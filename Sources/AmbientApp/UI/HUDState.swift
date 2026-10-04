import SwiftUI

enum BriefingState: Equatable {
    case none
    case pending
    case ready(String)
}

/// Everything the overlay draws, in overlay view coordinates (top-left origin).
@MainActor
final class HUDState: ObservableObject {
    @Published var message: HUDMessage?
    @Published var briefing: BriefingState = .none
    @Published var cardRect: CGRect = .zero
    @Published var targetRect: CGRect?
    @Published var canvasSize: CGSize = .zero
    /// When the current message appeared; drives all intro animations.
    @Published var shownAt = Date()
    /// The timeline is paused when nothing moves, to keep CPU usage near zero.
    @Published var animating = false
    /// The card accepts clicks and shows its More actions (pointer rested on it).
    @Published var interactive = false
}
