import Foundation
import Yams

// MARK: - Rule Engine

class RuleEngine {
    static let shared = RuleEngine()
    
    private var config: RuleConfig
    private let fileManager = FileManager.default
    
    var currentConfig: RuleConfig { config }
    
    private init() {
        self.config = RuleConfig.default
        loadConfig()
    }
    
    // MARK: - Config File Paths
    
    private var configDirectory: URL {
        let home = fileManager.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/gemisper", isDirectory: true)
    }
    
    private var configFileURL: URL {
        configDirectory.appendingPathComponent("rules.yaml")
    }
    
    // MARK: - Config Management
    
    /// 設定ファイルを読み込み
    func loadConfig() {
        // まず新しい場所をチェック
        if fileManager.fileExists(atPath: configFileURL.path) {
            do {
                let content = try String(contentsOf: configFileURL, encoding: .utf8)
                config = try RuleConfig.fromYAML(content)
                print("[RuleEngine] Loaded config from \(configFileURL.path)")
                return
            } catch {
                print("[RuleEngine] Failed to parse config: \(error)")
            }
        }
        
        // 古い場所（legacy）をチェック
        let legacyURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".gemisper-rules.md")
        if fileManager.fileExists(atPath: legacyURL.path) {
            // 古い形式はマークダウンなので、デフォルトを使用
            print("[RuleEngine] Legacy markdown rules found, using default YAML config")
        }
        
        // デフォルト設定を使用
        config = RuleConfig.default
        print("[RuleEngine] Using default config")
    }
    
    /// 設定ファイルを保存
    func saveConfig() throws {
        // ディレクトリが存在しない場合は作成
        if !fileManager.fileExists(atPath: configDirectory.path) {
            try fileManager.createDirectory(
                at: configDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        
        let yaml = try config.toYAML()
        try yaml.write(to: configFileURL, atomically: true, encoding: .utf8)
        print("[RuleEngine] Saved config to \(configFileURL.path)")
    }
    
    /// YAML文字列から設定を更新
    func updateConfig(fromYAML yaml: String) throws {
        let newConfig = try RuleConfig.fromYAML(yaml)
        config = newConfig
        try saveConfig()
    }
    
    /// 設定をデフォルトにリセット
    func resetToDefault() throws {
        config = RuleConfig.default
        try saveConfig()
    }
    
    /// 設定ファイルが存在するかチェック
    func configFileExists() -> Bool {
        return fileManager.fileExists(atPath: configFileURL.path)
    }
    
    /// 設定ファイルのパスを取得
    func getConfigFilePath() -> String {
        return configFileURL.path
    }
    
    // MARK: - Rule Processing
    
    /// テキストに対してルールを適用
    func process(text: String) -> RuleProcessingResult {
        // 設定が無効な場合はデフォルト処理
        if !SettingsManager.shared.settings.rulesEnabled {
            return .default
        }
        
        // トリガーをチェック
        for rule in config.triggers {
            if rule.matches(text: text) {
                let cleanedText = rule.cleanText(text)
                let template = config.templates[rule.action.rawValue] ?? config.templates["custom"]
                
                return RuleProcessingResult(
                    matchedRule: rule,
                    action: rule.action,
                    cleanedText: cleanedText,
                    template: template,
                    parameters: rule.parameters,
                    isDefault: false
                )
            }
        }
        
        return .default
    }
    
    /// アクションに基づいてプロンプトを生成
    func generatePrompt(for action: TriggerRule.ActionType, text: String, parameters: [String: String]) -> String {
        switch action {
        case .generateCommand:
            return generateCommandPrompt(text: text, parameters: parameters)
        case .translate:
            return generateTranslatePrompt(text: text, parameters: parameters)
        case .format:
            return generateFormatPrompt(text: text, parameters: parameters)
        case .custom:
            return config.defaults.prompt + "\n\nText: \(text)"
        }
    }
    
    private func generateCommandPrompt(text: String, parameters: [String: String]) -> String {
        let shell = parameters["shell"] ?? "zsh"
        
        return """
        Convert the following instruction to a \(shell) command.
        Output ONLY the command itself, with no explanation, no markdown, no backticks.
        The command should be safe and follow best practices.
        
        Instruction: \(text)
        
        Command:
        """
    }
    
    private func generateTranslatePrompt(text: String, parameters: [String: String]) -> String {
        let targetLang = parameters["target_lang"] ?? "en"
        let sourceLang = parameters["source_lang"] ?? "auto"
        
        let targetLangName = languageName(for: targetLang)
        let sourceLangName = sourceLang == "auto" ? "the detected language" : languageName(for: sourceLang)
        
        return """
        Translate the following text from \(sourceLangName) to \(targetLangName).
        Output ONLY the translation, with no explanation or additional text.
        Maintain the original formatting and tone where appropriate.
        
        Text: \(text)
        
        Translation:
        """
    }
    
    private func generateFormatPrompt(text: String, parameters: [String: String]) -> String {
        let format = parameters["format"] ?? "plain"
        
        switch format.lowercased() {
        case "markdown", "md":
            return """
            Format the following text as proper Markdown.
            - Convert appropriate sections to headers (# ## ###)
            - Format lists with proper bullet points or numbering
            - Use bold and italic where appropriate
            - Preserve code blocks and inline code
            - Ensure proper spacing between sections
            
            Text: \(text)
            
            Formatted Markdown:
            """
        case "json":
            return """
            Convert the following text to valid JSON format.
            If the text describes a data structure, convert it to proper JSON.
            Output ONLY valid JSON, with no explanation or markdown formatting.
            
            Text: \(text)
            
            JSON:
            """
        default:
            return """
            Format the following text to be clean and readable.
            - Add proper paragraph breaks
            - Fix punctuation and spacing
            - Ensure consistent formatting
            
            Text: \(text)
            
            Formatted Text:
            """
        }
    }
    
    private func languageName(for code: String) -> String {
        switch code.lowercased() {
        case "ja", "japanese": return "Japanese"
        case "en", "english": return "English"
        case "zh", "chinese": return "Chinese"
        case "ko", "korean": return "Korean"
        case "fr", "french": return "French"
        case "de", "german": return "German"
        case "es", "spanish": return "Spanish"
        case "it", "italian": return "Italian"
        case "pt", "portuguese": return "Portuguese"
        case "ru", "russian": return "Russian"
        default: return code
        }
    }
    
    // MARK: - Template Application
    
    /// テンプレートに値を適用
    func applyTemplate(_ template: String, values: [String: String]) -> String {
        var result = template
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }
    
    /// アクションに対応するテンプレートを取得
    func getTemplate(for action: TriggerRule.ActionType) -> String? {
        return config.templates[action.rawValue]
    }
    
    // MARK: - Rule CRUD Operations
    
    /// トリガールールを追加
    func addTrigger(_ rule: TriggerRule) throws {
        config.triggers.append(rule)
        try saveConfig()
    }
    
    /// トリガールールを更新
    func updateTrigger(_ rule: TriggerRule) throws {
        if let index = config.triggers.firstIndex(where: { $0.id == rule.id }) {
            config.triggers[index] = rule
            try saveConfig()
        }
    }
    
    /// トリガールールを削除
    func removeTrigger(id: UUID) throws {
        config.triggers.removeAll { $0.id == id }
        try saveConfig()
    }
    
    /// テンプレートを更新
    func updateTemplate(key: String, value: String) throws {
        config.templates[key] = value
        try saveConfig()
    }
    
    /// デフォルト設定を更新
    func updateDefaults(_ defaults: DefaultSettings) throws {
        config.defaults = defaults
        try saveConfig()
    }
    
    // MARK: - Validation
    
    /// YAMLの構文を検証
    func validateYAML(_ yaml: String) -> ValidationResult {
        do {
            _ = try RuleConfig.fromYAML(yaml)
            return .valid
        } catch {
            return .invalid(error.localizedDescription)
        }
    }
    
    enum ValidationResult {
        case valid
        case invalid(String)
        
        var isValid: Bool {
            switch self {
            case .valid: return true
            case .invalid: return false
            }
        }
    }
}
