import Foundation
// Translation's types (TranslationSession, LanguageAvailability) are not yet
// annotated for Swift 6 concurrency; they are only ever touched from the main
// actor here, so downgrade the Sendable diagnostics to warnings.
@preconcurrency import Translation

/// Wraps Apple's on-device Translation framework.
///
/// The framework hands out a `TranslationSession` only through the
/// `.translationTask` view modifier, and the session is valid just for the
/// lifetime of that closure. So the engine keeps a queue: callers `await`
/// `translate(_:)` from anywhere, and whichever view is currently hosting the
/// session drains the queue in `serve(_:)`.
@MainActor
@Observable
final class TranslationEngine {

    enum EngineError: LocalizedError {
        case notConfigured
        case sessionEnded

        var errorDescription: String? {
            switch self {
            case .notConfigured: "尚未選擇翻譯語言。"
            case .sessionEnded: "翻譯工作階段已結束，請再試一次。"
            }
        }
    }

    private struct Job {
        let id = UUID()
        let text: String
    }

    /// Driven into `.translationTask`. Replacing it restarts the session.
    private(set) var configuration: TranslationSession.Configuration?

    /// True while a session is live and able to translate.
    private(set) var isReady = false

    /// Set when the language pair needs assets that are not downloaded yet.
    private(set) var needsDownload = false

    private(set) var sourceLanguage: Locale.Language?
    private(set) var targetLanguage: Locale.Language?

    private var jobs: AsyncStream<Job>?
    private var jobFeed: AsyncStream<Job>.Continuation?
    private var waiters: [UUID: CheckedContinuation<String, Error>] = [:]

    private let availability = LanguageAvailability()

    // MARK: - Configuration

    /// Point the engine at a language pair. Pass `source: nil` to let the
    /// framework detect the source language.
    func configure(source: Locale.Language?, target: Locale.Language) {
        guard source != sourceLanguage || target != targetLanguage || configuration == nil else { return }

        sourceLanguage = source
        targetLanguage = target
        restartQueue()
        configuration = TranslationSession.Configuration(source: source, target: target)

        Task { await refreshAvailability() }
    }

    /// Force the current session to tear down and come back, e.g. after the
    /// user downloads a language pack.
    func reload() {
        restartQueue()
        configuration?.invalidate()
    }

    private func restartQueue() {
        jobFeed?.finish()
        failAllWaiters(with: EngineError.sessionEnded)
        let (stream, feed) = AsyncStream.makeStream(of: Job.self)
        jobs = stream
        jobFeed = feed
    }

    private func failAllWaiters(with error: Error) {
        let pending = waiters
        waiters.removeAll()
        for (_, continuation) in pending {
            continuation.resume(throwing: error)
        }
    }

    // MARK: - Translating

    /// Translate a single string. Safe to call before the session is live —
    /// the request waits in the queue.
    func translate(_ text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let jobFeed else { throw EngineError.notConfigured }

        let job = Job(text: trimmed)
        return try await withCheckedThrowingContinuation { continuation in
            waiters[job.id] = continuation
            if case .terminated = jobFeed.yield(job) {
                waiters.removeValue(forKey: job.id)
                continuation.resume(throwing: EngineError.sessionEnded)
            }
        }
    }

    /// Attached by the hosting view: `.translationTask(engine.configuration) { await engine.serve($0) }`
    func serve(_ session: TranslationSession) async {
        guard let jobs else { return }

        do {
            // Prompts the user to download the language pack if it is missing.
            try await session.prepareTranslation()
            needsDownload = false
        } catch {
            needsDownload = true
        }

        isReady = true
        defer {
            isReady = false
            failAllWaiters(with: EngineError.sessionEnded)
        }

        for await job in jobs {
            guard let continuation = waiters.removeValue(forKey: job.id) else { continue }
            do {
                let response = try await session.translate(job.text)
                continuation.resume(returning: response.targetText)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Availability

    private func refreshAvailability() async {
        guard let targetLanguage else { return }
        let status = await availability.status(from: sourceLanguage ?? targetLanguage, to: targetLanguage)
        needsDownload = (status == .supported)
    }

    /// Every language pair Apple can translate on this device.
    nonisolated func supportedLanguages() async -> [AppLanguage] {
        // A fresh instance: `LanguageAvailability` is not Sendable, so the
        // stored one cannot cross off the main actor.
        let languages = await LanguageAvailability().supportedLanguages
        return languages
            .map(AppLanguage.init(language:))
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    func status(from source: Locale.Language, to target: Locale.Language) async -> LanguageAvailability.Status {
        await availability.status(from: source, to: target)
    }
}
