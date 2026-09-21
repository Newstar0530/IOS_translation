import SwiftUI

@main
struct TranslateAIApp: App {
    @State private var engine = TranslationEngine()
    @State private var assistant = FoundationModelsAssistant()
    @State private var speech = SpeechService()
    @State private var history = HistoryStore()
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                .environment(assistant)
                .environment(speech)
                .environment(history)
                .environment(settings)
        }
    }
}
