import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Optional enhancement layer built on Apple's on-device LLM.
///
/// The Translation framework produces the actual translation; this adds the
/// things a general model is good at — tone, register, idiom explanation.
/// Everything runs locally, and the whole layer degrades to "unavailable" on
/// devices without Apple Intelligence, so the app stays fully usable.
@MainActor
@Observable
final class FoundationModelsAssistant {

    enum Tone: String, CaseIterable, Identifiable, Sendable {
        case formal, casual, concise, friendly

        var id: String { rawValue }

        var label: String {
            switch self {
            case .formal: "正式"
            case .casual: "口語"
            case .concise: "精簡"
            case .friendly: "親切"
            }
        }

        var instruction: String {
            switch self {
            case .formal: "商務書信等級的正式用語"
            case .casual: "朋友之間的日常口語"
            case .concise: "盡可能精簡，去掉贅字"
            case .friendly: "溫暖、有禮貌但不拘謹"
            }
        }
    }

    enum Availability: Equatable {
        case available
        case deviceNotEligible
        case notEnabled
        case modelNotReady
        case osTooOld

        var explanation: String? {
            switch self {
            case .available: nil
            case .deviceNotEligible: "這台裝置不支援 Apple Intelligence，進階改寫功能無法使用（翻譯本身不受影響）。"
            case .notEnabled: "請到「設定 → Apple Intelligence 與 Siri」開啟 Apple Intelligence。"
            case .modelNotReady: "裝置端模型仍在下載或準備中，請稍後再試。"
            case .osTooOld: "進階改寫需要 iOS 26 以上（翻譯本身不受影響）。"
            }
        }
    }

    private(set) var availability: Availability = .osTooOld
    private(set) var isWorking = false

    init() {
        refreshAvailability()
    }

    func refreshAvailability() {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            availability = .osTooOld
            return
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            availability = .available
        case .unavailable(.deviceNotEligible):
            availability = .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            availability = .notEnabled
        case .unavailable(.modelNotReady):
            availability = .modelNotReady
        case .unavailable:
            availability = .modelNotReady
        }
        #else
        availability = .osTooOld
        #endif
    }

    var isAvailable: Bool { availability == .available }

    // MARK: - Features

    /// Rewrite an existing translation in a different register, without
    /// changing its meaning.
    func adjustTone(_ translation: String, to tone: Tone, targetLanguage: String) async -> String? {
        await run(
            instructions: """
            你是一位專業譯者。使用者會給你一段譯文，你要在不改變原意的前提下調整語氣。
            只輸出改寫後的句子本身，不要加引號、說明或前言。
            """,
            prompt: """
            目標語言：\(targetLanguage)
            期望語氣：\(tone.instruction)

            譯文：
            \(translation)
            """,
            temperature: 0.4
        )
    }

    /// Explain idioms, slang or cultural context in the source text.
    func explain(_ text: String, sourceLanguage: String) async -> String? {
        await run(
            instructions: """
            你是一位語言老師。針對使用者提供的句子，用繁體中文簡短說明其中的成語、俚語、
            文化背景或語氣上的細節。若句子很直白、沒有特別之處，就回答「這句話很直白，沒有特別的文化脈絡。」
            控制在 100 字以內。
            """,
            prompt: """
            原文語言：\(sourceLanguage)

            原文：
            \(text)
            """,
            temperature: 0.3
        )
    }

    /// Tidy up messy speech-to-text or OCR output before it is translated.
    func cleanUp(_ rawText: String) async -> String? {
        await run(
            instructions: """
            使用者會給你一段由語音辨識或文字辨識產生的文字，可能有斷行錯誤、缺漏標點或重複字。
            請修正標點與明顯的辨識錯誤，但不要翻譯、不要改寫、不要增加原本沒有的內容。
            只輸出整理後的文字。
            """,
            prompt: rawText,
            temperature: 0.1
        )
    }

    // MARK: - Plumbing

    private func run(instructions: String, prompt: String, temperature: Double) async -> String? {
        guard isAvailable else { return nil }

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return nil }

        isWorking = true
        defer { isWorking = false }

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: prompt,
                options: GenerationOptions(temperature: temperature)
            )
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}
