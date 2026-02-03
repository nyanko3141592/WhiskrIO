import SwiftUI
import AppKit

// MARK: - Dictionary Window Controller

@MainActor
class DictionaryWindowController {
    static let shared = DictionaryWindowController()
    private var window: NSWindow?
    
    func showWindow() {
        if window == nil {
            let contentView = DictionaryView()
                .frame(minWidth: 500, minHeight: 400)
            
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            panel.title = "カスタム辞書"
            panel.contentView = NSHostingView(rootView: contentView)
            panel.isReleasedWhenClosed = false
            panel.center()
            
            window = panel
        }
        
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Dictionary View

struct DictionaryView: View {
    @StateObject private var settingsManager = SettingsManager.shared
    @State private var newFrom: String = ""
    @State private var newTo: String = ""
    @State private var searchText: String = ""
    
    var filteredEntries: [CustomDictionaryEntry] {
        if searchText.isEmpty {
            return settingsManager.customDictionary
        }
        return settingsManager.customDictionary.filter {
            $0.from.localizedCaseInsensitiveContains(searchText) ||
            $0.to.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 検索バー
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("検索...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .padding()
            
            // リスト
            List {
                Section {
                    ForEach(filteredEntries) { entry in
                        DictionaryEntryRow(entry: entry) {
                            if let index = settingsManager.customDictionary.firstIndex(where: { $0.id == entry.id }) {
                                settingsManager.removeDictionaryEntry(at: index)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("変換前")
                            .frame(width: 200, alignment: .leading)
                        Spacer()
                        Text("→")
                            .frame(width: 30)
                        Spacer()
                        Text("変換後")
                            .frame(width: 200, alignment: .leading)
                        Spacer()
                        Text("")
                            .frame(width: 60)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // 追加フォーム
            VStack(spacing: 12) {
                Text("新しい辞書エントリ")
                    .font(.headline)
                
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("変換前")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("例: つまり", text: $newFrom)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Text("→")
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("変換後")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("例: つまり、", text: $newTo)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Button(action: addEntry) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(newFrom.isEmpty || newTo.isEmpty)
                }
            }
            .padding()
        }
    }
    
    private func addEntry() {
        guard !newFrom.isEmpty && !newTo.isEmpty else { return }
        settingsManager.addDictionaryEntry(from: newFrom, to: newTo)
        newFrom = ""
        newTo = ""
    }
}

struct DictionaryEntryRow: View {
    let entry: CustomDictionaryEntry
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            Text(entry.from)
                .frame(width: 200, alignment: .leading)
                .lineLimit(1)
            
            Spacer()
            
            Text("→")
                .foregroundColor(.secondary)
                .frame(width: 30)
            
            Spacer()
            
            Text(entry.to)
                .frame(width: 200, alignment: .leading)
                .lineLimit(1)
            
            Spacer()
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .frame(width: 60)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Snippets Window Controller

@MainActor
class SnippetsWindowController {
    static let shared = SnippetsWindowController()
    private var window: NSWindow?
    
    func showWindow() {
        if window == nil {
            let contentView = SnippetsView()
                .frame(minWidth: 500, minHeight: 400)
            
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            panel.title = "スニペット"
            panel.contentView = NSHostingView(rootView: contentView)
            panel.isReleasedWhenClosed = false
            panel.center()
            
            window = panel
        }
        
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Snippets View

struct SnippetsView: View {
    @StateObject private var settingsManager = SettingsManager.shared
    @State private var newTrigger: String = ""
    @State private var newExpansion: String = ""
    @State private var searchText: String = ""
    
    var filteredSnippets: [Snippet] {
        if searchText.isEmpty {
            return settingsManager.snippets
        }
        return settingsManager.snippets.filter {
            $0.trigger.localizedCaseInsensitiveContains(searchText) ||
            $0.expansion.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 検索バー
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("検索...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .padding()
            
            // リスト
            List {
                Section {
                    ForEach(filteredSnippets) { snippet in
                        SnippetRow(snippet: snippet) {
                            if let index = settingsManager.snippets.firstIndex(where: { $0.id == snippet.id }) {
                                settingsManager.removeSnippet(at: index)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("トリガー")
                            .frame(width: 150, alignment: .leading)
                        Spacer()
                        Text("展開後")
                            .frame(width: 300, alignment: .leading)
                        Spacer()
                        Text("")
                            .frame(width: 60)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // 追加フォーム
            VStack(spacing: 12) {
                Text("新しいスニペット")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("トリガー:")
                            .frame(width: 70, alignment: .trailing)
                        TextField("例: @mail", text: $newTrigger)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Text("展開:")
                            .frame(width: 70, alignment: .trailing)
                        TextField("例: your.email@example.com", text: $newExpansion)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Spacer()
                        Button("追加") {
                            addSnippet()
                        }
                        .disabled(newTrigger.isEmpty || newExpansion.isEmpty)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding()
        }
    }
    
    private func addSnippet() {
        guard !newTrigger.isEmpty && !newExpansion.isEmpty else { return }
        settingsManager.addSnippet(trigger: newTrigger, expansion: newExpansion)
        newTrigger = ""
        newExpansion = ""
    }
}

struct SnippetRow: View {
    let snippet: Snippet
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            Text(snippet.trigger)
                .frame(width: 150, alignment: .leading)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.blue)
                .lineLimit(1)
            
            Spacer()
            
            Text(snippet.expansion)
                .frame(width: 300, alignment: .leading)
                .lineLimit(1)
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .frame(width: 60)
        }
        .padding(.vertical, 4)
    }
}
