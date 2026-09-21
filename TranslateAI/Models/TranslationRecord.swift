import Foundation

/// One completed translation, kept locally so history works offline too.
struct TranslationRecord: Identifiable, Codable, Hashable, Sendable {
    enum Source: String, Codable, Sendable {
        case text, speech, camera
    }

    var id = UUID()
    var sourceText: String
    var translatedText: String
    var sourceLanguage: String?
    var targetLanguage: String
    var origin: Source
    var createdAt = Date()
    var isFavourite = false
}
