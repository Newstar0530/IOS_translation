import SwiftUI

struct TextTranslateView: View {
    @Environment(TranslationEngine.self) private var engine
    @Environment(FoundationModelsAssistant.self) private var assistant
    @Environment(SpeechService.self) private var speech
    @Environment(HistoryStore.self) private var history
    @Environment(AppSettings.self) private var settings

    @State private var input = ""
    @State private var output = ""
    @State private var explanation: String?
    @State private var errorMessage: String?
    @State private var isTranslating = false
    @State private var translateTask: Task<Void, Never>?
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LanguageBar()
                    .padding(.vertical, 8)

                ScrollView {
                    VStack(spacing: 16) {
                        inputCard
                        if !output.isEmpty || isTranslating {
                            outputCard
                        }
                        if let explanation {
                            explanationCard(explanation)
                        }
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("翻譯")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: speech.transcript) { _, new in
                if !new.isEmpty { input = new }
            }
            .onChange(of: input) { _, _ in scheduleTranslation() }
            .onChange(of: settings.targetLanguage) { _, _ in scheduleTranslation() }
            .onChange(of: settings.sourceLanguage) { _, _ in scheduleTranslation() }
        }
    }

    // MARK: - Cards

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $input)
                .focused($inputFocused)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .overlay(alignment: .topLeading) {
                    if input.isEmpty {
                        Text("輸入或口述要翻譯的文字…")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 16) {
                Button {
                    toggleDictation()
                } label: {
                    Label(
                        speech.isRecording ? "停止" : "口述",
                        systemImage: speech.isRecording ? "stop.circle.fill" : "mic.circle"
                    )
                }
                .tint(speech.isRecording ? .red : .accentColor)

                Spacer()

                if !input.isEmpty {
                    Button("清除", systemImage: "xmark.circle") {
                        clearAll()
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)

            if let speechError = speech.lastError {
                Text(speechError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(AppLanguage(language: settings.targetLanguage).displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if isTranslating {
                    ProgressView().controlSize(.small)
                }
            }

            Text(output.isEmpty ? " " : output)
                .font(.title3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !output.isEmpty {
                actionRow
            }
        }
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 18) {
                Button("朗讀", systemImage: "speaker.wave.2") {
                    speech.speak(output, language: settings.targetLanguage)
                }
                Button("複製", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = output
                }
                Button("收藏", systemImage: "star") {
                    saveToHistory(favourite: true)
                }
                Spacer()
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .foregroundStyle(.secondary)

            if assistant.isAvailable {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FoundationModelsAssistant.Tone.allCases) { tone in
                            Button(tone.label) { adjust(to: tone) }
                                .font(.caption.weight(.medium))
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                        }
                        Button("語意解釋") { explainInput() }
                            .font(.caption.weight(.medium))
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                    }
                }
                .overlay(alignment: .trailing) {
                    if assistant.isWorking {
                        ProgressView().controlSize(.small)
                    }
                }
            } else if let reason = assistant.availability.explanation {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func explanationCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("語意解釋", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(.tint.opacity(0.08), in: .rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Actions

    /// Debounced so we are not firing a translation on every keystroke.
    private func scheduleTranslation() {
        translateTask?.cancel()
        explanation = nil

        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            output = ""
            errorMessage = nil
            return
        }

        translateTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            isTranslating = true
            defer { isTranslating = false }

            do {
                let result = try await engine.translate(text)
                guard !Task.isCancelled else { return }
                output = result
                errorMessage = nil
                if settings.speakTranslations {
                    speech.speak(result, language: settings.targetLanguage)
                }
                saveToHistory(favourite: false)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func toggleDictation() {
        if speech.isRecording {
            speech.stopRecording()
        } else {
            inputFocused = false
            Task {
                await speech.startRecording(language: settings.sourceLanguage ?? Locale.current.language)
            }
        }
    }

    private func adjust(to tone: FoundationModelsAssistant.Tone) {
        Task {
            let target = AppLanguage(language: settings.targetLanguage).displayName
            if let rewritten = await assistant.adjustTone(output, to: tone, targetLanguage: target) {
                output = rewritten
            }
        }
    }

    private func explainInput() {
        Task {
            let source = settings.sourceLanguage.map { AppLanguage(language: $0).displayName } ?? "自動偵測"
            explanation = await assistant.explain(input, sourceLanguage: source)
        }
    }

    private func saveToHistory(favourite: Bool) {
        guard !output.isEmpty else { return }
        history.add(
            TranslationRecord(
                sourceText: input,
                translatedText: output,
                sourceLanguage: settings.sourceLanguage?.maxIdentifier,
                targetLanguage: settings.targetLanguage.maxIdentifier,
                origin: speech.transcript.isEmpty ? .text : .speech,
                isFavourite: favourite
            )
        )
    }

    private func clearAll() {
        translateTask?.cancel()
        input = ""
        output = ""
        explanation = nil
        errorMessage = nil
    }
}
