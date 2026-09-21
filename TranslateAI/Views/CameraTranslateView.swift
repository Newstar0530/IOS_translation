import PhotosUI
import SwiftUI

/// Point the camera (or pick a photo) and get every line of text translated.
/// Vision does the recognition and the Translation framework the rest, so the
/// whole flow works in airplane mode once the language pack is downloaded.
struct CameraTranslateView: View {
    @Environment(TranslationEngine.self) private var engine
    @Environment(FoundationModelsAssistant.self) private var assistant
    @Environment(HistoryStore.self) private var history
    @Environment(AppSettings.self) private var settings

    @State private var image: UIImage?
    @State private var recognisedText = ""
    @State private var translatedText = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showingCamera = false
    @State private var photoItem: PhotosPickerItem?

    private let ocr = OCRService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LanguageBar()
                    .padding(.vertical, 8)

                ScrollView {
                    VStack(spacing: 16) {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 260)
                                .clipShape(.rect(cornerRadius: 16))
                                .padding(.horizontal)
                        } else {
                            placeholder
                        }

                        captureButtons

                        if isProcessing {
                            ProgressView("辨識中…")
                                .padding()
                        }

                        if !recognisedText.isEmpty {
                            textCard(title: "辨識到的文字", body: recognisedText, muted: true)
                        }
                        if !translatedText.isEmpty {
                            textCard(title: "譯文", body: translatedText, muted: false)
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("相機翻譯")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { captured in
                    image = captured
                    showingCamera = false
                    if let captured { process(captured) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let picked = UIImage(data: data) {
                        image = picked
                        process(picked)
                    }
                }
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("拍下菜單、路標或說明書，\n離線辨識並翻譯。")
                .multilineTextAlignment(.center)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var captureButtons: some View {
        HStack(spacing: 12) {
            Button {
                showingCamera = true
            } label: {
                Label("拍照", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("相簿", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
    }

    private func textCard(title: String, body text: String, muted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(muted ? .callout : .title3)
                .foregroundStyle(muted ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func process(_ image: UIImage) {
        Task {
            isProcessing = true
            errorMessage = nil
            recognisedText = ""
            translatedText = ""
            defer { isProcessing = false }

            do {
                let blocks = try await ocr.recognise(in: image, languageHint: settings.sourceLanguage)
                guard !blocks.isEmpty else {
                    errorMessage = "沒有辨識到文字，換個角度或光線再試一次。"
                    return
                }

                var text = ocr.joinIntoParagraphs(blocks)
                // OCR output is often broken across lines; the on-device LLM
                // can stitch it back together before we translate.
                if settings.cleanUpBeforeTranslating,
                   let tidied = await assistant.cleanUp(text) {
                    text = tidied
                }
                recognisedText = text

                translatedText = try await engine.translate(text)
                history.add(
                    TranslationRecord(
                        sourceText: recognisedText,
                        translatedText: translatedText,
                        sourceLanguage: settings.sourceLanguage?.maxIdentifier,
                        targetLanguage: settings.targetLanguage.maxIdentifier,
                        origin: .camera
                    )
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Minimal UIKit camera bridge. A live-preview overlay would use
/// AVCaptureSession instead, but a still capture keeps the flow simple and
/// gives Vision a full-resolution frame to work with.
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage?) -> Void

        init(onCapture: @escaping (UIImage?) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onCapture(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }
    }
}
