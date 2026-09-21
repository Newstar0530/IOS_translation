import AVFoundation
import Foundation
import Speech

/// On-device speech recognition and speech synthesis.
///
/// `requiresOnDeviceRecognition` is forced on, so nothing is sent to Apple's
/// servers — which also means recognition simply fails if the user has not
/// downloaded that language for offline dictation.
@MainActor
@Observable
final class SpeechService: NSObject {

    enum SpeechError: LocalizedError {
        case permissionDenied
        case offlineModelMissing(String)
        case recogniserUnavailable

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                "需要麥克風與語音辨識權限才能聽寫。"
            case .offlineModelMissing(let language):
                "「\(language)」尚未下載離線聽寫資料。請到「設定 → 一般 → 鍵盤 → 聽寫語言」加入該語言。"
            case .recogniserUnavailable:
                "此語言不支援裝置端語音辨識。"
            }
        }
    }

    private(set) var isRecording = false
    private(set) var transcript = ""
    private(set) var lastError: String?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let synthesiser = AVSpeechSynthesizer()

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechGranted else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    // MARK: - Dictation

    func startRecording(language: Locale.Language) async {
        guard !isRecording else { return }
        lastError = nil
        transcript = ""

        guard await requestPermissions() else {
            lastError = SpeechError.permissionDenied.errorDescription
            return
        }

        let locale = Locale(identifier: language.maxIdentifier)
        guard let recogniser = SFSpeechRecognizer(locale: locale), recogniser.isAvailable else {
            lastError = SpeechError.recogniserUnavailable.errorDescription
            return
        }
        guard recogniser.supportsOnDeviceRecognition else {
            let name = Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
            lastError = SpeechError.offlineModelMissing(name).errorDescription
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            recognitionTask = recogniser.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        if result.isFinal { self.stopRecording() }
                    }
                    if error != nil {
                        self.stopRecording()
                    }
                }
            }
        } catch {
            lastError = error.localizedDescription
            stopRecording()
        }
    }

    func stopRecording() {
        guard isRecording || audioEngine.isRunning else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Playback

    /// Read a translation out loud. Voices are bundled or downloadable and
    /// work without a network connection.
    func speak(_ text: String, language: Locale.Language) {
        guard !text.isEmpty else { return }
        if synthesiser.isSpeaking {
            synthesiser.stopSpeaking(at: .immediate)
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language.maxIdentifier)
            ?? AVSpeechSynthesisVoice(language: Locale.Language.Components(language: language).languageCode?.identifier ?? "en")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesiser.speak(utterance)
    }

    func stopSpeaking() {
        synthesiser.stopSpeaking(at: .immediate)
    }
}
