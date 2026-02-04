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
    func generatePrompt(for action: TriggerRule.ActionType, text: String, parameters: [String: String], customPrompt: String? = nil) -> String {
        // カスタムプロンプトが指定されている場合はそれを使用
        if let customPrompt = customPrompt, !customPrompt.isEmpty {
            return customPrompt.replacingOccurrences(of: "{text}", with: text)
        }

        switch action {
        case .generateCommand:
            return generateCommandPrompt(text: text, parameters: parameters)
        case .translate:
            return generateTranslatePrompt(text: text, parameters: parameters)
        case .format:
            return generateFormatPrompt(text: text, parameters: parameters)
        case .rewrite:
            return generateRewritePrompt(text: text, parameters: parameters)
        case .summarize:
            return generateSummarizePrompt(text: text, parameters: parameters)
        case .expand:
            return generateExpandPrompt(text: text, parameters: parameters)
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

        CRITICAL RULES:
        - Output ONLY the translated text itself
        - DO NOT include the original text
        - DO NOT add labels like "(原文)", "(Original)", "Translation:", etc.
        - DO NOT add any introduction or explanation
        - DO NOT wrap the text in quotes or parentheses
        - Just output the pure translation, nothing else

        Text to translate: \(text)
        """
    }
    
    private func generateFormatPrompt(text: String, parameters: [String: String]) -> String {
        let format = parameters["format"] ?? "plain"

        switch format.lowercased() {
        case "markdown", "md":
            return """
            Format the following text as proper Markdown.

            CRITICAL RULES:
            - Output ONLY the formatted Markdown content
            - DO NOT add labels like "Formatted Markdown:" or "結果:"
            - DO NOT add any introduction or explanation
            - Convert appropriate sections to headers (# ## ###)
            - Format lists with proper bullet points or numbering
            - Use bold and italic where appropriate
            - Preserve code blocks and inline code

            Text to format: \(text)
            """
        case "json":
            return """
            Convert the following text to valid JSON format.

            CRITICAL RULES:
            - Output ONLY valid JSON, nothing else
            - DO NOT add labels like "JSON:" or "結果:"
            - DO NOT wrap in markdown code blocks
            - DO NOT add any explanation
            - If the text describes a data structure, convert it to proper JSON

            Text to convert: \(text)
            """
        case "bullet", "list":
            return """
            Convert the following text to a bullet point list.

            CRITICAL RULES:
            - Output ONLY the bullet list itself
            - DO NOT add labels like "Bullet Points:" or "箇条書き:"
            - DO NOT add any introduction or explanation
            - Use bullet points (- or •) for each item
            - Keep each point concise and clear
            - Maintain the same language as the original text

            Text to convert: \(text)
            """
        default:
            return """
            Format the following text to be clean and readable.

            CRITICAL RULES:
            - Output ONLY the formatted text itself
            - DO NOT add labels like "Formatted Text:" or "整形結果:"
            - DO NOT add any introduction or explanation
            - Add proper paragraph breaks
            - Fix punctuation and spacing

            Text to format: \(text)
            """
        }
    }
    
    private func generateRewritePrompt(text: String, parameters: [String: String]) -> String {
        let style = parameters["style"] ?? "natural"

        switch style.lowercased() {
        case "business_email", "business":
            return """
            Rewrite the following text as a professional business email.

            CRITICAL RULES:
            - Output ONLY the rewritten email content itself
            - DO NOT add labels like "Business Email:" or "ビジネスメール:"
            - DO NOT add any introduction or explanation
            - Use formal and polite language
            - Add appropriate greetings and closings
            - If the text is in Japanese, write in Japanese
            - If the text is in English, write in English

            Text to rewrite: \(text)
            """
        case "casual", "friendly":
            return """
            Rewrite the following text in a casual, friendly tone.

            CRITICAL RULES:
            - Output ONLY the rewritten text itself
            - DO NOT add labels like "Casual Version:" or "カジュアル版:"
            - DO NOT add any introduction or explanation
            - Use conversational language
            - Keep it natural and approachable
            - If the text is in Japanese, write in Japanese
            - If the text is in English, write in English

            Text to rewrite: \(text)
            """
        default:
            return """
            Rewrite the following text in a \(style) style.

            CRITICAL RULES:
            - Output ONLY the rewritten text itself
            - DO NOT add any labels or headers
            - DO NOT add any introduction or explanation
            - Maintain the original meaning
            - Match the target style appropriately

            Text to rewrite: \(text)
            """
        }
    }

    private func generateSummarizePrompt(text: String, parameters: [String: String]) -> String {
        let length = parameters["length"] ?? "medium"

        let lengthInstruction: String
        switch length.lowercased() {
        case "short", "brief":
            lengthInstruction = "in 1-2 sentences"
        case "long", "detailed":
            lengthInstruction = "in 3-5 sentences, covering key points"
        default:
            lengthInstruction = "in 2-3 sentences"
        }

        return """
        Summarize the following text \(lengthInstruction).

        CRITICAL RULES:
        - Output ONLY the summary itself
        - DO NOT add labels like "Summary:" or "要約:"
        - DO NOT add any introduction or explanation
        - Capture the main points and key information
        - Use clear and concise language
        - Maintain the same language as the original text

        Text to summarize: \(text)
        """
    }

    private func generateExpandPrompt(text: String, parameters: [String: String]) -> String {
        let style = parameters["style"] ?? "detailed"

        return """
        Expand the following text with more detail.

        CRITICAL RULES:
        - Output ONLY the expanded text itself
        - DO NOT add labels like "Expanded:" or "展開:"
        - DO NOT add any introduction or explanation
        - Add relevant context and explanation
        - Make it more comprehensive while staying on topic
        - Maintain the same language as the original text

        Text to expand: \(text)
        """
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
