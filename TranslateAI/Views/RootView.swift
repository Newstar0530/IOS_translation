import SwiftUI
import Translation

struct RootView: View {
    @Environment(TranslationEngine.self) private var engine
    @Environment(AppSettings.self) private var settings

    var body: some View {
        TabView {
            Tab("文字", systemImage: "text.bubble") {
                TextTranslateView()
            }
            Tab("相機", systemImage: "camera.viewfinder") {
                CameraTranslateView()
            }
            Tab("紀錄", systemImage: "clock.arrow.circlepath") {
                HistoryView()
            }
            Tab("語言包", systemImage: "arrow.down.circle") {
                OfflinePacksView()
            }
        }
        // One session for the whole app: the engine queues work from any tab.
        .translationTask(engine.configuration) { session in
            await engine.serve(session)
        }
        .task(id: languageKey) {
            engine.configure(source: settings.sourceLanguage, target: settings.targetLanguage)
        }
    }

    private var languageKey: String {
        "\(settings.sourceLanguage?.maxIdentifier ?? "auto")>\(settings.targetLanguage.maxIdentifier)"
    }
}
