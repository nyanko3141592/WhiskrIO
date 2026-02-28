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

// MARK: - Push to Talk Shortcut (任意キー組み合わせ対応)
struct PushToTalkShortcut: Codable, Equatable {
    var modifierFlags: UInt    // NSEvent.ModifierFlags.rawValue
    var keyCode: UInt16?       // nil = モディファイアのみ

    /// 表示名を生成（例: "⌥ + ⌘" "⌃ + Space" "F13"）
    var displayName: String {
        let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)
        var parts: [String] = []

        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        if flags.contains(.function) { parts.append("Fn") }

        if let kc = keyCode {
            parts.append(PushToTalkShortcut.keyCodeToString(kc))
        }

        return parts.isEmpty ? "未設定" : parts.joined(separator: " + ")
    }

    /// キーコードを人間に読める文字列に変換
    static func keyCodeToString(_ keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
            36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
            42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
            48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
            103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10",
            111: "F12", 113: "F15", 118: "F4", 120: "F2", 122: "F1",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }

    /// モディファイアキーのキーコードかどうか
    static func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        // 54=RightCmd, 55=LeftCmd, 56=LeftShift, 57=CapsLock, 58=LeftOption,
        // 59=LeftControl, 60=RightShift, 61=RightOption, 62=RightControl, 63=Fn
        [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
    }

    static let `default` = PushToTalkShortcut(
        modifierFlags: NSEvent.ModifierFlags([.option, .command]).rawValue,
        keyCode: nil
    )

    /// 旧PushToTalkKeys配列からマイグレーション
    static func fromLegacy(_ keys: [PushToTalkKey]) -> PushToTalkShortcut {
        let flags = keys.combinedModifierFlags
        return PushToTalkShortcut(modifierFlags: flags.rawValue, keyCode: nil)
    }
}

// MARK: - Overlay Position
enum OverlayPosition: String, Codable, CaseIterable {
    case bottomCenter = "bottomCenter"
    case bottomLeft = "bottomLeft"
    case bottomRight = "bottomRight"

    var displayName: String {
        switch self {
        case .bottomCenter: return "中央下"
        case .bottomLeft: return "左下"
        case .bottomRight: return "右下"
        }
    }

    var icon: String {
        switch self {
        case .bottomCenter: return "arrow.down"
        case .bottomLeft: return "arrow.down.left"
        case .bottomRight: return "arrow.down.right"
        }
    }
}

// MARK: - Speech Language
enum SpeechLanguage: String, Codable, CaseIterable {
    case auto = "auto"
    case japanese = "ja"
    case english = "en"
    case chinese = "zh"
    case korean = "ko"
    case spanish = "es"
    case french = "fr"
    case german = "de"

    var displayName: String {
        switch self {
        case .auto: return "自動検出"
        case .japanese: return "日本語"
        case .english: return "English"
        case .chinese: return "中文"
        case .korean: return "한국어"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        }
    }

    var promptInstruction: String? {
        switch self {
        case .auto: return nil
        case .japanese: return "The audio is in Japanese. Transcribe in Japanese only. Output must be in Japanese."
        case .english: return "The audio is in English. Transcribe in English only. Output must be in English."
        case .chinese: return "The audio is in Chinese. Transcribe in Chinese only. Output must be in Chinese."
        case .korean: return "The audio is in Korean. Transcribe in Korean only. Output must be in Korean."
        case .spanish: return "The audio is in Spanish. Transcribe in Spanish only. Output must be in Spanish."
        case .french: return "The audio is in French. Transcribe in French only. Output must be in French."
        case .german: return "The audio is in German. Transcribe in German only. Output must be in German."
        }
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
    var apiKey: String {
        get { KeychainManager.shared.getAPIKey() ?? "" }
        set { 
            if newValue.isEmpty {
                _ = KeychainManager.shared.deleteAPIKey()
            } else {
                _ = KeychainManager.shared.saveAPIKey(newValue)
            }
        }
    }
    var hotkeyModifier: Int
    var hotkeyKeyCode: Int
    var removeFillerWords: Bool
    var addPunctuation: Bool
    var speechLanguage: SpeechLanguage
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
    var maxRecordingDuration: Int  // 録音時間の上限（秒）
    var captureScreenshot: Bool  // スクリーンショットを送信するか
    var captureSize: CaptureSize  // キャプチャサイズ
    var overlayPosition: OverlayPosition  // オーバーレイの位置
    var selectedMicrophoneID: String?  // 選択したマイクのUID（nilの場合はシステムデフォルト）
    var useLocalTranscription: Bool  // ローカルモデルで文字起こしを行うか
    var voxtralHost: String  // Voxtralサーバーのホスト
    var voxtralPort: Int  // Voxtralサーバーのポート
    var useAppleIntelligenceForEdit: Bool  // 選択編集にApple Intelligenceを使う
    var pushToTalkShortcut: PushToTalkShortcut  // 任意キー組み合わせ対応ショートカット

    static let `default` = AppSettings(
        hotkeyModifier: Int(NSEvent.ModifierFlags.command.union(.shift).rawValue),
        hotkeyKeyCode: 3, // F3
        removeFillerWords: true,  // 常にtrue（プロンプトで制御）
        addPunctuation: true,     // 常にtrue（プロンプトで制御）
        speechLanguage: .japanese, // デフォルト: 日本語
        style: .natural,          // プロンプトで制御
        showOverlay: true,        // 常にtrue（録音インジケーター必須）
        playSoundEffects: true,
        pushToTalkMode: true,
        pushToTalkKeys: [.option, .command], // デフォルト: ⌥ + ⌘
        selectedModel: .flashLite, // デフォルト: gemini-2.5-flash-lite
        customPrompt: nil,
        appLanguage: .english,
        rulesEnabled: false,
        commandModeTriggers: ["コマンド", "command"],  // デフォルトのトリガー
        maxRecordingDuration: 60,  // デフォルト: 1分
        captureScreenshot: false,  // デフォルト: OFF（権限が必要）
        captureSize: .medium,  // デフォルト: 800×800px
        overlayPosition: .bottomCenter,  // デフォルト: 中央下
        selectedMicrophoneID: nil,  // デフォルト: システムデフォルト
        useLocalTranscription: false,  // デフォルト: OFF（Gemini APIで文字起こし）
        voxtralHost: "127.0.0.1",  // デフォルト: ローカルホスト
        voxtralPort: 8000,  // デフォルト: voxmlxのデフォルトポート
        useAppleIntelligenceForEdit: true,  // デフォルト: ON（Apple Intelligenceで選択編集）
        pushToTalkShortcut: .default  // デフォルト: ⌥ + ⌘
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
    
    private let settingsKey = "io.whiskr.settings"
    private let dictionaryKey = "io.whiskr.dictionary"
    private let snippetsKey = "io.whiskr.snippets"
    private let tokenUsageKey = "io.whiskr.tokenusage"
    
    private init() {}
    
    func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let savedSettings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = savedSettings

            // 旧形式からのマイグレーション: pushToTalkShortcutがデフォルトのままで、
            // pushToTalkKeysがカスタム設定されている場合はマイグレーション
            if settings.pushToTalkShortcut == .default &&
               settings.pushToTalkKeys != [.option, .command] {
                settings.pushToTalkShortcut = .fromLegacy(settings.pushToTalkKeys)
                saveSettings()
            }
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
        
        let configPath = homeDirectory.appendingPathComponent(".config/whiskrio/rules.md")
        let legacyPath = homeDirectory.appendingPathComponent(".whiskrio-rules.md")

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

        let configPath = homeDirectory.appendingPathComponent(".config/whiskrio/rules.md")
        let legacyPath = homeDirectory.appendingPathComponent(".whiskrio-rules.md")
        
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

        let configPath = homeDirectory.appendingPathComponent(".config/whiskrio/rules.yaml")

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
        let configDir = homeDirectory.appendingPathComponent(".config/whiskrio")
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
        return homeDirectory.appendingPathComponent(".config/whiskrio/rules.yaml").path
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
