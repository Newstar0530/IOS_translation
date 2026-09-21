import Foundation
import SwiftUI

/// The language pair and preferences, persisted across launches.
@MainActor
@Observable
final class AppSettings {

    /// `nil` source means "detect automatically".
    var sourceLanguage: Locale.Language? {
        didSet { persist(sourceLanguage?.maxIdentifier, forKey: Keys.source) }
    }

    var targetLanguage: Locale.Language {
        didSet { persist(targetLanguage.maxIdentifier, forKey: Keys.target) }
    }

    /// Auto-tidy dictation and OCR output with the on-device LLM first.
    var cleanUpBeforeTranslating: Bool {
        didSet { UserDefaults.standard.set(cleanUpBeforeTranslating, forKey: Keys.cleanUp) }
    }

    var speakTranslations: Bool {
        didSet { UserDefaults.standard.set(speakTranslations, forKey: Keys.speak) }
    }

    private enum Keys {
        static let source = "sourceLanguage"
        static let target = "targetLanguage"
        static let cleanUp = "cleanUpBeforeTranslating"
        static let speak = "speakTranslations"
    }

    init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Keys.source) {
            sourceLanguage = Locale.Language(identifier: raw)
        } else {
            sourceLanguage = nil
        }
        let targetRaw = defaults.string(forKey: Keys.target) ?? "zh-Hant-TW"
        targetLanguage = Locale.Language(identifier: targetRaw)
        cleanUpBeforeTranslating = defaults.object(forKey: Keys.cleanUp) as? Bool ?? true
        speakTranslations = defaults.bool(forKey: Keys.speak)
    }

    /// Flip source and target. A detected source cannot be swapped into the
    /// target slot, so this is a no-op while source is "auto".
    func swapLanguages() {
        guard let sourceLanguage else { return }
        let oldTarget = targetLanguage
        targetLanguage = sourceLanguage
        self.sourceLanguage = oldTarget
    }

    private func persist(_ value: String?, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
