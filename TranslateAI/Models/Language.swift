import Foundation

/// A language the app can translate to or from, wrapping `Locale.Language`
/// with a display name suitable for the picker.
struct AppLanguage: Identifiable, Hashable, Sendable {
    let language: Locale.Language

    var id: String { language.maxIdentifier }

    /// Localised name shown in the UI, e.g. "繁體中文" or "日本語".
    var displayName: String {
        let identifier = language.maxIdentifier
        let locale = Locale(identifier: identifier)
        return locale.localizedString(forIdentifier: identifier)?.capitalized(with: locale)
            ?? Locale.current.localizedString(forIdentifier: identifier)
            ?? identifier
    }

    /// Name in the user's own language, used as a subtitle.
    var localisedName: String {
        Locale.current.localizedString(forIdentifier: language.maxIdentifier) ?? ""
    }
}

extension Locale.Language {
    /// `zh-Hant-TW` style identifier. The Translation framework matches on
    /// language + script, so we always carry the script through.
    var maxIdentifier: String {
        let components = Locale.Language.Components(language: self)
        var parts = [components.languageCode?.identifier].compactMap { $0 }
        if let script = components.script?.identifier { parts.append(script) }
        if let region = components.region?.identifier { parts.append(region) }
        return parts.joined(separator: "-")
    }
}
