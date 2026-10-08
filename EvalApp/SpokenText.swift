import Accessibility
import EvalCore
import SwiftUI

/// Words for VoiceOver, built on the spoken French of EvalCore.
enum SpokenValue {
    /// A number with its unit named, such as « 81 kilogrammes ». The fallback
    /// is read when the unit is not one the engine can name.
    static func text(_ value: Double, unit: String, fallback: String) -> String {
        guard value.isFinite else { return fallback }
        let source = unit.isEmpty ? String(value) : "\(value) \(unit)"
        return MathSpeech.description(source) ?? fallback
    }
}

/// Spoken confirmations for effects that happen away from the focused element.
@MainActor
enum VoiceOverAnnouncement {
    /// Queues the text after what VoiceOver is already saying. Without an
    /// assistive technology running, nothing happens.
    static func post(_ text: String, after delay: Duration = .zero) {
        var announcement = AttributedString(text)
        announcement.accessibilitySpeechAnnouncementPriority = .low
        guard delay > .zero else {
            AccessibilityNotification.Announcement(announcement).post()
            return
        }
        Task {
            try? await Task.sleep(for: delay)
            AccessibilityNotification.Announcement(announcement).post()
        }
    }
}
