import Foundation
import Yams

// MARK: - Rule Config (YAML Structure)

struct RuleConfig: Codable {
    var version: String
    var triggers: [TriggerRule]
    var defaults: DefaultSettings
    var templates: [String: String]
    
    init(
        version: String = "1.0",
        triggers: [TriggerRule] = [],
        defaults: DefaultSettings = DefaultSettings(),
        templates: [String: String] = [:]
    ) {
        self.version = version
        self.triggers = triggers
        self.defaults = defaults
        self.templates = templates
    }
    
    static let `default` = RuleConfig(
        version: "1.0",
        triggers: TriggerRule.defaultRules,
        defaults: DefaultSettings(),
        templates: [
            "command": "# {description}\n{command}",
            "translate": "【原文】\n{original}\n\n【訳】\n{translated}",
            "format": "{content}"
        ]
    )
}

// MARK: - Trigger Rule

struct TriggerRule: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var keywords: [String]
    var action: ActionType
    var parameters: [String: String]
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case keywords
        case action
        case parameters
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        keywords: [String],
        action: ActionType,
        parameters: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.keywords = keywords
        self.action = action
        self.parameters = parameters
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.keywords = try container.decode([String].self, forKey: .keywords)
        let actionString = try container.decode(String.self, forKey: .action)
        self.action = ActionType(rawValue: actionString) ?? .custom
        self.parameters = try container.decodeIfPresent([String: String].self, forKey: .parameters) ?? [:]
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(keywords, forKey: .keywords)
        try container.encode(action.rawValue, forKey: .action)
        if !parameters.isEmpty {
            try container.encode(parameters, forKey: .parameters)
        }
    }
    
    enum ActionType: String, Codable, CaseIterable {
        case generateCommand = "generate_command"
        case translate = "translate"
        case format = "format"
        case custom = "custom"
        
        var displayName: String {
            switch self {
            case .generateCommand:
                return "コマンド生成"
            case .translate:
                return "翻訳"
            case .format:
                return "整形"
            case .custom:
                return "カスタム"
            }
        }
        
        var icon: String {
            switch self {
            case .generateCommand:
                return "terminal"
            case .translate:
                return "globe"
            case .format:
                return "textformat"
            case .custom:
                return "gearshape"
            }
        }
    }
    
    // マッチング（大文字小文字を無視）
    func matches(text: String) -> Bool {
        let lowercasedText = text.lowercased()
        let trimmedText = lowercasedText.trimmingCharacters(in: .whitespaces)
        
        for keyword in keywords {
            let lowercasedKeyword = keyword.lowercased()
            if trimmedText.hasPrefix(lowercasedKeyword) {
                return true
            }
        }
        return false
    }
    
    // トリガー部分を除去したクリーンなテキストを取得
    func cleanText(_ text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        let lowercasedText = trimmedText.lowercased()
        
        for keyword in keywords {
            let lowercasedKeyword = keyword.lowercased()
            if lowercasedText.hasPrefix(lowercasedKeyword) {
                let startIndex = trimmedText.index(trimmedText.startIndex, offsetBy: keyword.count)
                return String(trimmedText[startIndex...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return text
    }
    
    // デフォルトルール
    static let defaultRules: [TriggerRule] = [
        TriggerRule(
            name: "zshコマンド",
            keywords: ["コマンド", "command", "cmd"],
            action: .generateCommand,
            parameters: ["shell": "zsh"]
        ),
        TriggerRule(
            name: "日本語訳",
            keywords: ["英語", "english", "en"],
            action: .translate,
            parameters: ["target_lang": "ja", "source_lang": "en"]
        ),
        TriggerRule(
            name: "英語訳",
            keywords: ["日本語", "japanese", "jp", "訳して"],
            action: .translate,
            parameters: ["target_lang": "en", "source_lang": "ja"]
        ),
        TriggerRule(
            name: "Markdown整形",
            keywords: ["markdown", "md"],
            action: .format,
            parameters: ["format": "markdown"]
        ),
        TriggerRule(
            name: "JSON整形",
            keywords: ["json"],
            action: .format,
            parameters: ["format": "json"]
        )
    ]
}

// MARK: - Default Settings

struct DefaultSettings: Codable, Equatable {
    var prompt: String
    var language: String
    var style: String
    
    init(
        prompt: String = DefaultSettings.defaultPrompt,
        language: String = "auto",
        style: String = "natural"
    ) {
        self.prompt = prompt
        self.language = language
        self.style = style
    }
    
    static let defaultPrompt = """
Transcribe the audio to text.
Remove filler words.
Add punctuation.
"""
}

// MARK: - Rule Processing Result

struct RuleProcessingResult {
    let matchedRule: TriggerRule?
    let action: TriggerRule.ActionType
    let cleanedText: String
    let template: String?
    let parameters: [String: String]
    let isDefault: Bool
    
    static let `default` = RuleProcessingResult(
        matchedRule: nil,
        action: .custom,
        cleanedText: "",
        template: nil,
        parameters: [:],
        isDefault: true
    )
}

// MARK: - YAML Helper

extension RuleConfig {
    /// YAML文字列に変換
    func toYAML() throws -> String {
        let encoder = YAMLEncoder()
        encoder.options.sortKeys = false
        return try encoder.encode(self)
    }
    
    /// YAML文字列からパース
    static func fromYAML(_ yaml: String) throws -> RuleConfig {
        let decoder = YAMLDecoder()
        return try decoder.decode(RuleConfig.self, from: yaml)
    }
    
    /// デフォルトのYAML文字列を取得
    static var defaultYAML: String {
        let config = RuleConfig.default
        let encoder = YAMLEncoder()
        encoder.options.sortKeys = false
        do {
            return try encoder.encode(config)
        } catch {
            return defaultYAMLString
        }
    }
    
    static let defaultYAMLString = """
version: "1.0"

# トリガールール
triggers:
  - name: "zshコマンド"
    keywords:
      - "コマンド"
      - "command"
      - "cmd"
    action: "generate_command"
    parameters:
      shell: "zsh"

  - name: "日本語訳"
    keywords:
      - "英語"
      - "english"
      - "en"
    action: "translate"
    parameters:
      target_lang: "ja"
      source_lang: "en"

  - name: "英語訳"
    keywords:
      - "日本語"
      - "japanese"
      - "jp"
      - "訳して"
    action: "translate"
    parameters:
      target_lang: "en"
      source_lang: "ja"

  - name: "Markdown整形"
    keywords:
      - "markdown"
      - "md"
    action: "format"
    parameters:
      format: "markdown"

  - name: "JSON整形"
    keywords:
      - "json"
    action: "format"
    parameters:
      format: "json"

# デフォルト設定
defaults:
  prompt: |
    Transcribe the audio to text.
    Remove filler words.
    Add punctuation.
  language: "auto"
  style: "natural"

# 出力テンプレート
templates:
  command: |
    # {description}
    {command}
  translate: |
    【原文】
    {original}

    【訳】
    {translated}
  format: |
    {content}
"""
}
