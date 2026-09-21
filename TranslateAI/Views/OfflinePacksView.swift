import SwiftUI
import Translation

/// Shows which language packs are already on the device, and lets the user
/// pull down the missing ones while they still have a connection.
///
/// Apple does not expose a direct "download pack X" call. The supported way
/// is `prepareTranslation()` on a session for that pair, which presents the
/// system download sheet — that is what `downloadTarget` drives here.
struct OfflinePacksView: View {
    @Environment(TranslationEngine.self) private var engine
    @Environment(AppSettings.self) private var settings

    @State private var languages: [AppLanguage] = []
    @State private var statuses: [String: LanguageAvailability.Status] = [:]
    @State private var isLoading = true
    @State private var downloadConfiguration: TranslationSession.Configuration?
    @State private var query = ""

    private var pivot: Locale.Language { settings.targetLanguage }

    private var filtered: [AppLanguage] {
        let list = languages.filter { $0.language != pivot }
        guard !query.isEmpty else { return list }
        return list.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.localisedName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("載入支援的語言…")
                } else {
                    list
                }
            }
            .navigationTitle("離線語言包")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜尋語言")
            .task { await reload() }
            // Presenting a configuration here triggers the system download
            // prompt for that pair.
            .translationTask(downloadConfiguration) { session in
                try? await session.prepareTranslation()
                downloadConfiguration = nil
                await reload()
                engine.reload()
            }
        }
    }

    private var list: some View {
        List {
            Section {
                Text("以下是與「\(AppLanguage(language: pivot).displayName)」互譯的語言包狀態。已下載的語言在完全沒有網路時也能翻譯。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("語言") {
                ForEach(filtered) { language in
                    row(for: language)
                }
            }

            Section {
                Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                    Label("在「設定」中管理已下載的語言", systemImage: "gearshape")
                }
            } footer: {
                Text("系統的翻譯語言清單位於「設定 → App → 翻譯 → 已下載的語言」。")
            }
        }
    }

    private func row(for language: AppLanguage) -> some View {
        let status = statuses[language.id]
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(language.displayName)
                if !language.localisedName.isEmpty && language.localisedName != language.displayName {
                    Text(language.localisedName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            switch status {
            case .installed:
                Label("已下載", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
                    .accessibilityLabel("已下載")
            case .supported:
                Button("下載") {
                    downloadConfiguration = TranslationSession.Configuration(
                        source: language.language,
                        target: pivot
                    )
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .font(.caption)
            case .unsupported:
                Text("不支援")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            default:
                ProgressView().controlSize(.mini)
            }
        }
    }

    private func reload() async {
        if languages.isEmpty {
            languages = await engine.supportedLanguages()
        }
        var next: [String: LanguageAvailability.Status] = [:]
        for language in languages where language.language != pivot {
            next[language.id] = await engine.status(from: language.language, to: pivot)
        }
        statuses = next
        isLoading = false
    }
}
