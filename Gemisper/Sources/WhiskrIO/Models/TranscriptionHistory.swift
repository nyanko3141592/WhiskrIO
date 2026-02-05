import Foundation

// MARK: - Transcription History Item

struct TranscriptionHistoryItem: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let text: String

    init(id: UUID = UUID(), timestamp: Date = Date(), text: String) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
    }

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: timestamp)
    }

    var textPreview: String {
        let maxLength = 50
        if text.count <= maxLength {
            return text
        }
        return String(text.prefix(maxLength)) + "..."
    }
}

// MARK: - Transcription History Manager

class TranscriptionHistoryManager: ObservableObject {
    static let shared = TranscriptionHistoryManager()

    @Published var items: [TranscriptionHistoryItem] = []

    private let maxItems = 20
    private let storageKey = "io.whiskr.transcriptionHistory"

    private init() {}

    // MARK: - Load

    func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let savedItems = try? JSONDecoder().decode([TranscriptionHistoryItem].self, from: data) {
            items = savedItems
            print("[DEBUG] TranscriptionHistoryManager: Loaded \(items.count) items")
        } else {
            print("[DEBUG] TranscriptionHistoryManager: No saved history found")
        }
    }

    // MARK: - Save

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
            print("[DEBUG] TranscriptionHistoryManager: Saved \(items.count) items")
        }
    }

    // MARK: - Add

    func addItem(text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let item = TranscriptionHistoryItem(text: trimmedText)
        items.insert(item, at: 0)

        // 最大件数を超えた場合は古いものを削除
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }

        saveHistory()
        print("[DEBUG] TranscriptionHistoryManager: Added item, total count: \(items.count)")
    }

    // MARK: - Delete

    func deleteItem(at index: Int) {
        guard index >= 0 && index < items.count else { return }
        items.remove(at: index)
        saveHistory()
    }

    func deleteItem(id: UUID) {
        items.removeAll { $0.id == id }
        saveHistory()
    }

    // MARK: - Clear All

    func clearAll() {
        items.removeAll()
        saveHistory()
        print("[DEBUG] TranscriptionHistoryManager: Cleared all items")
    }

    // MARK: - Get Item

    func getItem(id: UUID) -> TranscriptionHistoryItem? {
        return items.first { $0.id == id }
    }
}
