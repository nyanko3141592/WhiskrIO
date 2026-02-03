import Foundation
import SwiftUI
import Combine

// MARK: - Push to Talk Keys (複合キー対応)
enum PushToTalkKey: String, Codable, CaseIterable {
    case option = "option"
    case command = "command"
    case control = "control"
    case shift = "shift"
    case function = "function"
    
    var displayName: String {
        switch self {
        case .option: return "⌥ Option"
        case .command: return "⌘ Command"
        case .control: return "⌃ Control"
        case .shift: return "⇧ Shift"
        case .function: return "Fn"
        }
    }
    
    var shortDisplayName: String {
        switch self {
        case .option: return "⌥"
        case .command: return "⌘"
        case .control: return "⌃"
        case .shift: return "⇧"
        case .function: return "Fn"
        }
    }
    
    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .option: return .option
        case .command: return .command
        case .control: return .control
        case .shift: return .shift
        case .function: return .function
        }
    }
}

extension Array where Element == PushToTalkKey {
    var combinedModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        for key in self {
            flags.insert(key.modifierFlag)
        }
        return flags
    }
    
    var combinedDisplayName: String {
        if isEmpty { return "未設定" }
        return map { $0.shortDisplayName }.joined(separator: " + ")
    }
}

// MARK: - Transcription Style
enum TranscriptionStyle: String, Codable, CaseIterable {
    case natural = "natural"
    case formal = "formal"
    case casual = "casual"
    case concise = "concise"
    
    var displayName: String {
        switch self {
        case .natural: return "自然"
        case .formal: return "フォーマル"
        case .casual: return "カジュアル"
        case .concise: return "簡潔"
        }
    }
    
    var prompt: String {
        switch self {
        case .natural:
            return "自然で読みやすい文章に整形してください。"
        case .formal:
            return "ビジネスメールや文書に適した、丁寧でフォーマルな文体に整形してください。"
        case .casual:
            return "友達とのチャットに適した、カジュアルで親しみやすい文体に整形してください。"
        case .concise:
            return "無駄を省き、簡潔で要点を押さえた文章に整形してください。"
        }
    }
}

// MARK: - Token Usage
struct TokenUsage: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let inputTokens: Int
    let outputTokens: Int
    let modelName: String
    
    init(id: UUID = UUID(), timestamp: Date = Date(), inputTokens: Int, outputTokens: Int, modelName: String) {
        self.id = id
        self.timestamp = timestamp
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.modelName = modelName
    }
    
    var totalTokens: Int { inputTokens + outputTokens }
    
    func calculateCost() -> (usd: Double, jpy: Int) {
        guard let model = GeminiModel(rawValue: modelName) else {
            // Default to flash-lite pricing
            return GeminiModel.flashLite.calculateCost(inputTokens: inputTokens, outputTokens: outputTokens)
        }
        return model.calculateCost(inputTokens: inputTokens, outputTokens: outputTokens)
    }
    
    var estimatedCostUSD: Double {
        return calculateCost().usd
    }
}

// MARK: - App Settings
struct AppSettings: Codable, Equatable {
    var apiKey: String
    var hotkeyModifier: Int
    var hotkeyKeyCode: Int
    var removeFillerWords: Bool
    var addPunctuation: Bool
    var language: String
    var style: TranscriptionStyle
    var showOverlay: Bool
    var playSoundEffects: Bool
    var pushToTalkMode: Bool
    var pushToTalkKeys: [PushToTalkKey]
    var selectedModel: GeminiModel
    var customPrompt: String?
    var appLanguage: AppLanguage
    var rulesEnabled: Bool
    var commandModeTriggers: [String]  // コマンドモードのトリガーワード
    
    static let `default` = AppSettings(
        apiKey: "",
        hotkeyModifier: Int(NSEvent.ModifierFlags.command.union(.shift).rawValue),
        hotkeyKeyCode: 3, // F3
        removeFillerWords: true,
        addPunctuation: true,
        language: "ja",
        style: .natural,
        showOverlay: true,
        playSoundEffects: true,
        pushToTalkMode: true,
        pushToTalkKeys: [.option, .command], // デフォルト: ⌥ + ⌘
        selectedModel: .flashLite, // デフォルト: gemini-2.5-flash-lite
        customPrompt: nil,
        appLanguage: .english,
        rulesEnabled: false,
        commandModeTriggers: ["コマンド", "command"]  // デフォルトのトリガー
    )
}

// MARK: - Settings Manager
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var settings: AppSettings = .default
    @Published var customDictionary: [CustomDictionaryEntry] = []
    @Published var snippets: [Snippet] = []
    @Published var tokenUsages: [TokenUsage] = []
    @Published var rulesContent: String = ""
    @Published var rulesFilePath: String? = nil
    @Published var rulesYAMLContent: String = ""  // YAML形式のルール
    
    private let settingsKey = "com.gemisper.settings"
    private let dictionaryKey = "com.gemisper.dictionary"
    private let snippetsKey = "com.gemisper.snippets"
    private let tokenUsageKey = "com.gemisper.tokenusage"
    
    private init() {}
    
    func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let savedSettings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = savedSettings
        }
        
        if let data = UserDefaults.standard.data(forKey: dictionaryKey),
           let savedDict = try? JSONDecoder().decode([CustomDictionaryEntry].self, from: data) {
            customDictionary = savedDict
        }
        
        if let data = UserDefaults.standard.data(forKey: snippetsKey),
           let savedSnippets = try? JSONDecoder().decode([Snippet].self, from: data) {
            snippets = savedSnippets
        }
        
        if let data = UserDefaults.standard.data(forKey: tokenUsageKey),
           let savedUsages = try? JSONDecoder().decode([TokenUsage].self, from: data) {
            tokenUsages = savedUsages
            print("[DEBUG] Settings.loadSettings(): Loaded \(tokenUsages.count) token usages")
        } else {
            print("[DEBUG] Settings.loadSettings(): No saved token usages found")
        }
        
        // ルールファイルの読み込み
        loadRulesFile()
        
        // YAMLルールの読み込み
        loadYAMLRules()
    }
    
    func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }
    
    func saveDictionary() {
        if let data = try? JSONEncoder().encode(customDictionary) {
            UserDefaults.standard.set(data, forKey: dictionaryKey)
        }
    }
    
    func saveSnippets() {
        if let data = try? JSONEncoder().encode(snippets) {
            UserDefaults.standard.set(data, forKey: snippetsKey)
        }
    }
    
    func saveTokenUsages() {
        if let data = try? JSONEncoder().encode(tokenUsages) {
            UserDefaults.standard.set(data, forKey: tokenUsageKey)
            print("[DEBUG] Settings.saveTokenUsages(): Saved \(tokenUsages.count) token usages")
        }
    }
    
    // MARK: - Dictionary
    func addDictionaryEntry(from: String, to: String) {
        let entry = CustomDictionaryEntry(from: from, to: to)
        customDictionary.append(entry)
        saveDictionary()
    }
    
    func removeDictionaryEntry(at index: Int) {
        customDictionary.remove(at: index)
        saveDictionary()
    }
    
    func applyCustomDictionary(to text: String) -> String {
        var result = text
        for entry in customDictionary {
            result = result.replacingOccurrences(of: entry.from, with: entry.to)
        }
        return result
    }
    
    // MARK: - Snippets
    func addSnippet(trigger: String, expansion: String) {
        let snippet = Snippet(trigger: trigger, expansion: expansion)
        snippets.append(snippet)
        saveSnippets()
    }
    
    func removeSnippet(at index: Int) {
        snippets.remove(at: index)
        saveSnippets()
    }
    
    func expandSnippets(in text: String) -> String {
        var result = text
        for snippet in snippets.sorted(by: { $0.trigger.count > $1.trigger.count }) {
            result = result.replacingOccurrences(of: snippet.trigger, with: snippet.expansion)
        }
        return result
    }
    
    // MARK: - Token Usage
    func addTokenUsage(inputTokens: Int, outputTokens: Int, modelName: String) {
        print("[DEBUG] Settings.addTokenUsage(): input=\(inputTokens), output=\(outputTokens), model=\(modelName)")
        let usage = TokenUsage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            modelName: modelName
        )
        tokenUsages.append(usage)
        print("[DEBUG] Settings.addTokenUsage(): Total usages now: \(tokenUsages.count)")
        
        // 90日以上前のデータを削除
        cleanupOldUsages()
        saveTokenUsages()
    }
    
    func getRecentUsage(limit: Int = 10) -> [TokenUsage] {
        let result = Array(tokenUsages.suffix(limit).reversed())
        print("[DEBUG] Settings.getRecentUsage(): total=\(tokenUsages.count), returning=\(result.count)")
        return result
    }
    
    func getTodayUsage() -> (tokens: Int, costUSD: Double, costJPY: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        let todayUsages = tokenUsages.filter { usage in
            calendar.isDate(usage.timestamp, inSameDayAs: today)
        }
        
        let totalTokens = todayUsages.reduce(0) { $0 + $1.totalTokens }
        let totalUSD = todayUsages.reduce(0.0) { $0 + $1.calculateCost().usd }
        let totalJPY = todayUsages.reduce(0) { $0 + $1.calculateCost().jpy }
        
        return (totalTokens, totalUSD, totalJPY)
    }
    
    func getCurrentMonthUsage() -> (tokens: Int, costUSD: Double, costJPY: Int) {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        
        let monthUsages = tokenUsages.filter { usage in
            let usageComponents = calendar.dateComponents([.year, .month], from: usage.timestamp)
            return usageComponents.year == components.year && usageComponents.month == components.month
        }
        
        let totalTokens = monthUsages.reduce(0) { $0 + $1.totalTokens }
        let totalUSD = monthUsages.reduce(0.0) { $0 + $1.calculateCost().usd }
        let totalJPY = monthUsages.reduce(0) { $0 + $1.calculateCost().jpy }
        
        return (totalTokens, totalUSD, totalJPY)
    }
    
    private func cleanupOldUsages() {
        let calendar = Calendar.current
        let cutoffDate = calendar.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        tokenUsages.removeAll { $0.timestamp < cutoffDate }
    }
    
    // MARK: - Rules File
    
    func loadRulesFile() {
        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        
        let configPath = homeDirectory.appendingPathComponent(".config/gemisper/rules.md")
        let legacyPath = homeDirectory.appendingPathComponent(".gemisper-rules.md")
        
        if fileManager.fileExists(atPath: configPath.path) {
            rulesFilePath = configPath.path
            do {
                rulesContent = try String(contentsOf: configPath, encoding: .utf8)
            } catch {
                rulesContent = ""
                print("[ERROR] Failed to read rules file: \(error)")
            }
        } else if fileManager.fileExists(atPath: legacyPath.path) {
            rulesFilePath = legacyPath.path
            do {
                rulesContent = try String(contentsOf: legacyPath, encoding: .utf8)
            } catch {
                rulesContent = ""
                print("[ERROR] Failed to read rules file: \(error)")
            }
        } else {
            rulesContent = ""
            rulesFilePath = nil
        }
    }
    
    func getRulesFilePath() -> String? {
        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        
        let configPath = homeDirectory.appendingPathComponent(".config/gemisper/rules.md")
        let legacyPath = homeDirectory.appendingPathComponent(".gemisper-rules.md")
        
        if fileManager.fileExists(atPath: configPath.path) {
            return configPath.path
        } else if fileManager.fileExists(atPath: legacyPath.path) {
            return legacyPath.path
        }
        return nil
    }
    
    func rulesFileExists() -> Bool {
        return getRulesFilePath() != nil
    }
    
    func getFormattedRules() -> String {
        guard settings.rulesEnabled, !rulesContent.isEmpty else {
            return ""
        }
        return rulesContent.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - YAML Rules
    
    func loadYAMLRules() {
        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        
        let configPath = homeDirectory.appendingPathComponent(".config/gemisper/rules.yaml")
        
        if fileManager.fileExists(atPath: configPath.path) {
            do {
                rulesYAMLContent = try String(contentsOf: configPath, encoding: .utf8)
            } catch {
                rulesYAMLContent = RuleConfig.defaultYAML
                print("[ERROR] Failed to read YAML rules file: \(error)")
            }
        } else {
            // ファイルが存在しない場合はデフォルトを設定
            rulesYAMLContent = RuleConfig.defaultYAML
        }
    }
    
    func saveYAMLRules(_ content: String) throws {
        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let configDir = homeDirectory.appendingPathComponent(".config/gemisper")
        let configPath = configDir.appendingPathComponent("rules.yaml")
        
        // ディレクトリが存在しない場合は作成
        if !fileManager.fileExists(atPath: configDir.path) {
            try fileManager.createDirectory(at: configDir, withIntermediateDirectories: true, attributes: nil)
        }
        
        try content.write(to: configPath, atomically: true, encoding: .utf8)
        rulesYAMLContent = content
        
        // RuleEngineの設定も更新
        RuleEngine.shared.loadConfig()
    }
    
    func resetYAMLRulesToDefault() throws {
        try saveYAMLRules(RuleConfig.defaultYAML)
    }
    
    func validateYAMLRules(_ content: String) -> (isValid: Bool, error: String?) {
        do {
            _ = try RuleConfig.fromYAML(content)
            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }
    
    func getYAMLRulesFilePath() -> String {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        return homeDirectory.appendingPathComponent(".config/gemisper/rules.yaml").path
    }
}

// MARK: - Custom Dictionary Entry
struct CustomDictionaryEntry: Codable, Identifiable {
    let id: UUID
    var from: String
    var to: String
    
    init(id: UUID = UUID(), from: String, to: String) {
        self.id = id
        self.from = from
        self.to = to
    }
}

// MARK: - Snippet
struct Snippet: Codable, Identifiable {
    let id: UUID
    var trigger: String
    var expansion: String
    
    init(id: UUID = UUID(), trigger: String, expansion: String) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
    }
}
