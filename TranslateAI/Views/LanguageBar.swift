import SwiftUI

/// The source → target selector shared by the text and camera tabs.
struct LanguageBar: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TranslationEngine.self) private var engine

    @State private var languages: [AppLanguage] = []
    @State private var picking: Slot?

    private enum Slot: Identifiable {
        case source, target
        var id: Int { self == .source ? 0 : 1 }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                picking = .source
            } label: {
                slotLabel(settings.sourceLanguage.map(displayName) ?? "自動偵測")
            }

            Button {
                withAnimation(.snappy) { settings.swapLanguages() }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.body.weight(.semibold))
            }
            .disabled(settings.sourceLanguage == nil)
            .accessibilityLabel("交換語言")

            Button {
                picking = .target
            } label: {
                slotLabel(displayName(settings.targetLanguage))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .task {
            if languages.isEmpty {
                languages = await engine.supportedLanguages()
            }
        }
        .sheet(item: $picking) { slot in
            LanguagePickerSheet(
                languages: languages,
                allowsAutomatic: slot == .source,
                selection: slot == .source ? settings.sourceLanguage : settings.targetLanguage
            ) { chosen in
                switch slot {
                case .source: settings.sourceLanguage = chosen
                case .target: if let chosen { settings.targetLanguage = chosen }
                }
                picking = nil
            }
        }
    }

    private func slotLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.quaternary, in: .rect(cornerRadius: 12))
    }

    private func displayName(_ language: Locale.Language) -> String {
        AppLanguage(language: language).displayName
    }
}

struct LanguagePickerSheet: View {
    let languages: [AppLanguage]
    let allowsAutomatic: Bool
    let selection: Locale.Language?
    let onPick: (Locale.Language?) -> Void

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [AppLanguage] {
        guard !query.isEmpty else { return languages }
        return languages.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.localisedName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if allowsAutomatic && query.isEmpty {
                    Button {
                        onPick(nil)
                        dismiss()
                    } label: {
                        row(title: "自動偵測", subtitle: "由系統判斷來源語言", selected: selection == nil)
                    }
                }
                ForEach(filtered) { language in
                    Button {
                        onPick(language.language)
                        dismiss()
                    } label: {
                        row(
                            title: language.displayName,
                            subtitle: language.localisedName,
                            selected: selection?.maxIdentifier == language.id
                        )
                    }
                }
            }
            .searchable(text: $query, prompt: "搜尋語言")
            .navigationTitle("選擇語言")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func row(title: String, subtitle: String, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                if !subtitle.isEmpty && subtitle != title {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark").foregroundStyle(.tint)
            }
        }
    }
}
