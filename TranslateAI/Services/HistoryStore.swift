import Foundation

/// Local translation history, written to a JSON file in Application Support.
/// Deliberately not iCloud-backed: the whole point of this app is that it
/// works with no connection at all.
@MainActor
@Observable
final class HistoryStore {

    private(set) var records: [TranslationRecord] = []

    private let fileURL: URL
    private let limit = 500

    init(filename: String = "history.json") {
        let directory = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appending(path: filename)
        load()
    }

    func add(_ record: TranslationRecord) {
        records.insert(record, at: 0)
        if records.count > limit {
            // Keep favourites even once we pass the cap.
            records = Array(records.prefix(limit)) + records.dropFirst(limit).filter(\.isFavourite)
        }
        save()
    }

    func toggleFavourite(_ record: TranslationRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index].isFavourite.toggle()
        save()
    }

    func delete(at offsets: IndexSet) {
        records.remove(atOffsets: offsets)
        save()
    }

    func clear() {
        records.removeAll { !$0.isFavourite }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        records = (try? JSONDecoder().decode([TranslationRecord].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
