import SwiftUI

struct HistoryView: View {
    @Environment(HistoryStore.self) private var history
    @Environment(SpeechService.self) private var speech

    @State private var showFavouritesOnly = false

    private var records: [TranslationRecord] {
        showFavouritesOnly ? history.records.filter(\.isFavourite) : history.records
    }

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        showFavouritesOnly ? "還沒有收藏" : "還沒有翻譯紀錄",
                        systemImage: showFavouritesOnly ? "star" : "clock",
                        description: Text("翻譯過的內容會存在這台裝置上，離線也查得到。")
                    )
                } else {
                    List {
                        ForEach(records) { record in
                            row(record)
                        }
                        .onDelete { offsets in
                            // Map back to the unfiltered indices.
                            let ids = offsets.map { records[$0].id }
                            let real = IndexSet(history.records.indices.filter { ids.contains(history.records[$0].id) })
                            history.delete(at: real)
                        }
                    }
                }
            }
            .navigationTitle("紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Toggle(isOn: $showFavouritesOnly) {
                        Image(systemName: showFavouritesOnly ? "star.fill" : "star")
                    }
                    .toggleStyle(.button)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("清除非收藏項目", systemImage: "trash", role: .destructive) {
                            history.clear()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private func row(_ record: TranslationRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon(for: record.origin))
                    .font(.caption2)
                Text(record.createdAt, format: .relative(presentation: .named))
                    .font(.caption2)
                Spacer()
                Button {
                    history.toggleFavourite(record)
                } label: {
                    Image(systemName: record.isFavourite ? "star.fill" : "star")
                }
                .buttonStyle(.plain)
                .foregroundStyle(record.isFavourite ? .yellow : .secondary)
            }
            .foregroundStyle(.secondary)

            Text(record.sourceText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(record.translatedText)
                .font(.body)
                .lineLimit(3)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("複製譯文", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = record.translatedText
            }
            Button("朗讀", systemImage: "speaker.wave.2") {
                speech.speak(record.translatedText, language: Locale.Language(identifier: record.targetLanguage))
            }
        }
    }

    private func icon(for origin: TranslationRecord.Source) -> String {
        switch origin {
        case .text: "text.bubble"
        case .speech: "mic"
        case .camera: "camera"
        }
    }
}
