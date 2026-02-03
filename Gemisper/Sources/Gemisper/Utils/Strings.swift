import Foundation
import SwiftUI

// MARK: - App Language
enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case english = "en"
    case japanese = "ja"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .japanese:
            return "日本語"
        }
    }
}

// MARK: - Localization Keys
enum L10n {
    // MARK: - Common
    enum Common {
        static let ok = LocalizedString("common.ok")
        static let cancel = LocalizedString("common.cancel")
        static let save = LocalizedString("common.save")
        static let delete = LocalizedString("common.delete")
        static let edit = LocalizedString("common.edit")
        static let add = LocalizedString("common.add")
        static let close = LocalizedString("common.close")
        static let settings = LocalizedString("common.settings")
        static let quit = LocalizedString("common.quit")
        static let version = LocalizedString("common.version")
        static let build = LocalizedString("common.build")
        static let search = LocalizedString("common.search")
    }
    
    // MARK: - Menu Bar
    enum MenuBar {
        static let startRecording = LocalizedString("menubar.start_recording")
        static let stopRecording = LocalizedString("menubar.stop_recording")
        static let pushToTalk = LocalizedString("menubar.push_to_talk")
        static let customDictionary = LocalizedString("menubar.custom_dictionary")
        static let snippets = LocalizedString("menubar.snippets")
        static let usage = LocalizedString("menubar.usage")
        static let recent = LocalizedString("menubar.recent")
        static let todayTotal = LocalizedString("menubar.today_total")
        static let todayEstimated = LocalizedString("menubar.today_estimated")
        static let monthlyTotal = LocalizedString("menubar.monthly_total")
        static let monthlyEstimated = LocalizedString("menubar.monthly_estimated")
        static let noData = LocalizedString("menubar.no_data")
        static let quitApp = LocalizedString("menubar.quit_app")
    }
    
    // MARK: - Settings - Tabs
    enum SettingsTab {
        static let general = LocalizedString("settings_tab.general")
        static let api = LocalizedString("settings_tab.api")
        static let hotkey = LocalizedString("settings_tab.hotkey")
        static let prompt = LocalizedString("settings_tab.prompt")
        static let advanced = LocalizedString("settings_tab.advanced")
    }
    
    // MARK: - Settings - General
    enum SettingsGeneral {
        static let transcriptionOptions = LocalizedString("settings_general.transcription_options")
        static let removeFillerWords = LocalizedString("settings_general.remove_filler_words")
        static let addPunctuation = LocalizedString("settings_general.add_punctuation")
        static let style = LocalizedString("settings_general.style")
        static let language = LocalizedString("settings_general.language")
        static let interface = LocalizedString("settings_general.interface")
        static let showOverlay = LocalizedString("settings_general.show_overlay")
        static let showOverlayHelp = LocalizedString("settings_general.show_overlay_help")
        static let playSoundEffects = LocalizedString("settings_general.play_sound_effects")
        static let appLanguage = LocalizedString("settings_general.app_language")
    }
    
    // MARK: - Settings - API
    enum SettingsAPI {
        static let geminiAPI = LocalizedString("settings_api.gemini_api")
        static let apiKey = LocalizedString("settings_api.api_key")
        static let apiKeyPlaceholder = LocalizedString("settings_api.api_key_placeholder")
        static let hide = LocalizedString("settings_api.hide")
        static let show = LocalizedString("settings_api.show")
        static let paste = LocalizedString("settings_api.paste")
        static let validate = LocalizedString("settings_api.validate")
        static let apiKeyValid = LocalizedString("settings_api.api_key_valid")
        static let apiKeyInvalid = LocalizedString("settings_api.api_key_invalid")
        static let getAPIKey = LocalizedString("settings_api.get_api_key")
        static let modelSettings = LocalizedString("settings_api.model_settings")
        static let model = LocalizedString("settings_api.model")
        static let pricing = LocalizedString("settings_api.pricing")
        static let freeTier = LocalizedString("settings_api.free_tier")
    }
    
    // MARK: - Settings - Hotkey
    enum SettingsHotkey {
        static let inputMode = LocalizedString("settings_hotkey.input_mode")
        static let mode = LocalizedString("settings_hotkey.mode")
        static let pushToTalkMode = LocalizedString("settings_hotkey.push_to_talk_mode")
        static let toggleMode = LocalizedString("settings_hotkey.toggle_mode")
        static let pushToTalkDescription = LocalizedString("settings_hotkey.push_to_talk_description")
        static let toggleDescription = LocalizedString("settings_hotkey.toggle_description")
        static let pushToTalkKeys = LocalizedString("settings_hotkey.push_to_talk_keys")
        static let currentSetting = LocalizedString("settings_hotkey.current_setting")
        static let pressToTalk = LocalizedString("settings_hotkey.press_to_talk")
        static let toggleHotkey = LocalizedString("settings_hotkey.toggle_hotkey")
        static let currentHotkey = LocalizedString("settings_hotkey.current_hotkey")
        static let setNewHotkey = LocalizedString("settings_hotkey.set_new_hotkey")
        static let clickToRecordHotkey = LocalizedString("settings_hotkey.click_to_record_hotkey")
        static let pressKey = LocalizedString("settings_hotkey.press_key")
        static let presets = LocalizedString("settings_hotkey.presets")
    }
    
    // MARK: - Settings - Prompt
    enum SettingsPrompt {
        static let systemPrompt = LocalizedString("settings_prompt.system_prompt")
        static let customPrompt = LocalizedString("settings_prompt.custom_prompt")
        static let useCustomPrompt = LocalizedString("settings_prompt.use_custom_prompt")
        static let defaultPromptDescription = LocalizedString("settings_prompt.default_prompt_description")
        static let customPromptPlaceholder = LocalizedString("settings_prompt.custom_prompt_placeholder")
    }
    
    // MARK: - Settings - Advanced
    enum SettingsAdvanced {
        static let debug = LocalizedString("settings_advanced.debug")
        static let enableLogging = LocalizedString("settings_advanced.enable_logging")
        static let clearCache = LocalizedString("settings_advanced.clear_cache")
        static let appInfo = LocalizedString("settings_advanced.app_info")
    }
    
    // MARK: - Alerts
    enum Alert {
        static let microphoneAccessRequired = LocalizedString("alert.microphone_access_required")
        static let microphoneAccessMessage = LocalizedString("alert.microphone_access_message")
        static let openSettings = LocalizedString("alert.open_settings")
        static let errorOccurred = LocalizedString("alert.error_occurred")
        static let apiKeyRequired = LocalizedString("alert.api_key_required")
        static let apiKeyRequiredMessage = LocalizedString("alert.api_key_required_message")
        static let apiKeyRequiredDetail = LocalizedString("alert.api_key_required_detail")
        static let later = LocalizedString("alert.later")
    }
    
    // MARK: - Styles
    enum Style {
        static let natural = LocalizedString("style.natural")
        static let formal = LocalizedString("style.formal")
        static let casual = LocalizedString("style.casual")
        static let concise = LocalizedString("style.concise")
    }
    
    // MARK: - Transcription Language
    enum TranscriptionLanguage {
        static let japanese = LocalizedString("transcription_language.japanese")
        static let english = LocalizedString("transcription_language.english")
        static let auto = LocalizedString("transcription_language.auto")
    }
    
    // MARK: - Overlay
    enum Overlay {
        static let listening = LocalizedString("overlay.listening")
        static let processing = LocalizedString("overlay.processing")
    }
    
    // MARK: - Dictionary
    enum Dictionary {
        static let title = LocalizedString("dictionary.title")
        static let from = LocalizedString("dictionary.from")
        static let to = LocalizedString("dictionary.to")
        static let addEntry = LocalizedString("dictionary.add_entry")
        static let noEntries = LocalizedString("dictionary.no_entries")
        static let description = LocalizedString("dictionary.description")
    }
    
    // MARK: - Snippets
    enum Snippets {
        static let title = LocalizedString("snippets.title")
        static let trigger = LocalizedString("snippets.trigger")
        static let expansion = LocalizedString("snippets.expansion")
        static let addSnippet = LocalizedString("snippets.add_snippet")
        static let noSnippets = LocalizedString("snippets.no_snippets")
        static let description = LocalizedString("snippets.description")
    }
}

// MARK: - LocalizedString Function
func LocalizedString(_ key: String) -> String {
    return LocalizationManager.shared.localizedString(for: key)
}

// MARK: - Localization Manager
class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    
    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "app_language")
            NotificationCenter.default.post(name: .languageChanged, object: nil)
        }
    }
    
    private init() {
        let savedLanguage = UserDefaults.standard.string(forKey: "app_language") ?? "en"
        self.currentLanguage = AppLanguage(rawValue: savedLanguage) ?? .english
    }
    
    func localizedString(for key: String) -> String {
        return localizedStrings[currentLanguage]?[key] ?? localizedStrings[.english]?[key] ?? key
    }
    
    func setLanguage(_ language: AppLanguage) {
        currentLanguage = language
    }
}

// MARK: - Notification Name
extension Notification.Name {
    static let languageChanged = Notification.Name("languageChanged")
}

// MARK: - Localized Strings Dictionary
private let localizedStrings: [AppLanguage: [String: String]] = [
    .english: [
        // Common
        "common.ok": "OK",
        "common.cancel": "Cancel",
        "common.save": "Save",
        "common.delete": "Delete",
        "common.edit": "Edit",
        "common.add": "Add",
        "common.close": "Close",
        "common.settings": "Settings...",
        "common.quit": "Quit Gemisper",
        "common.version": "Version",
        "common.build": "Build",
        "common.search": "Search",
        
        // Menu Bar
        "menubar.start_recording": "Start Recording (⌘⇧F3)",
        "menubar.stop_recording": "Stop Recording",
        "menubar.push_to_talk": "Push to Talk (%@)",
        "menubar.custom_dictionary": "Custom Dictionary...",
        "menubar.snippets": "Snippets...",
        "menubar.usage": "Usage",
        "menubar.recent": "  Recent: %@ tokens",
        "menubar.today_total": "  Today: %@ tokens",
        "menubar.today_estimated": "  Today Est: $%.4f (¥%.2f)",
        "menubar.monthly_total": "  Monthly: %@ tokens",
        "menubar.monthly_estimated": "  Monthly Est: $%.4f (¥%.2f)",
        "menubar.no_data": "  Recent: No data",
        "menubar.quit_app": "Quit Gemisper",
        
        // Settings Tabs
        "settings_tab.general": "General",
        "settings_tab.api": "API",
        "settings_tab.hotkey": "Hotkey",
        "settings_tab.prompt": "Prompt",
        "settings_tab.advanced": "Advanced",
        
        // Settings General
        "settings_general.transcription_options": "Transcription Options",
        "settings_general.remove_filler_words": "Remove filler words",
        "settings_general.add_punctuation": "Auto-add punctuation",
        "settings_general.style": "Style",
        "settings_general.language": "Language",
        "settings_general.interface": "Interface",
        "settings_general.show_overlay": "Show recording indicator",
        "settings_general.show_overlay_help": "Show a small recording indicator at the bottom of the screen",
        "settings_general.play_sound_effects": "Play sound effects",
        "settings_general.app_language": "App Language",
        
        // Settings API
        "settings_api.gemini_api": "Gemini API",
        "settings_api.api_key": "API Key",
        "settings_api.api_key_placeholder": "Enter API key",
        "settings_api.hide": "Hide",
        "settings_api.show": "Show",
        "settings_api.paste": "Paste from clipboard",
        "settings_api.validate": "Validate",
        "settings_api.api_key_valid": "API key is valid",
        "settings_api.api_key_invalid": "API key is invalid",
        "settings_api.get_api_key": "Get API key from Google AI Studio",
        "settings_api.model_settings": "Model Settings",
        "settings_api.model": "Model",
        "settings_api.pricing": "Pricing: %@",
        "settings_api.free_tier": "Free tier available",
        
        // Settings Hotkey
        "settings_hotkey.input_mode": "Input Mode",
        "settings_hotkey.mode": "Mode",
        "settings_hotkey.push_to_talk_mode": "Push to Talk",
        "settings_hotkey.toggle_mode": "Toggle Mode",
        "settings_hotkey.push_to_talk_description": "Record while holding the key",
        "settings_hotkey.toggle_description": "Toggle recording on/off with hotkey",
        "settings_hotkey.push_to_talk_keys": "Push to Talk Keys (multi-select)",
        "settings_hotkey.current_setting": "Current:",
        "settings_hotkey.press_to_talk": "%@ to talk",
        "settings_hotkey.toggle_hotkey": "Toggle Hotkey",
        "settings_hotkey.current_hotkey": "Current hotkey: %@",
        "settings_hotkey.set_new_hotkey": "Set new hotkey:",
        "settings_hotkey.click_to_record_hotkey": "Click to record hotkey",
        "settings_hotkey.press_key": "Press key...",
        "settings_hotkey.presets": "Presets",
        
        // Settings Prompt
        "settings_prompt.system_prompt": "System Prompt",
        "settings_prompt.custom_prompt": "Custom Prompt",
        "settings_prompt.use_custom_prompt": "Use custom prompt",
        "settings_prompt.default_prompt_description": "Default: Transcribe audio with filler words removed and punctuation added",
        "settings_prompt.custom_prompt_placeholder": "Enter custom prompt...",
        
        // Settings Advanced
        "settings_advanced.debug": "Debug",
        "settings_advanced.enable_logging": "Enable logging",
        "settings_advanced.clear_cache": "Clear Cache",
        "settings_advanced.app_info": "App Information",
        
        // Alerts
        "alert.microphone_access_required": "Microphone Access Required",
        "alert.microphone_access_message": "Please allow microphone access in System Settings.",
        "alert.open_settings": "Open Settings",
        "alert.error_occurred": "An error occurred",
        "alert.api_key_required": "Gemini API Key Required",
        "alert.api_key_required_message": "Please enter your Gemini API key in Settings.",
        "alert.api_key_required_detail": "You can get a free API key from Google AI Studio.",
        "alert.later": "Later",
        
        // Styles
        "style.natural": "Natural",
        "style.formal": "Formal",
        "style.casual": "Casual",
        "style.concise": "Concise",
        
        // Transcription Language
        "transcription_language.japanese": "Japanese",
        "transcription_language.english": "English",
        "transcription_language.auto": "Auto-detect",
        
        // Overlay
        "overlay.listening": "Listening...",
        "overlay.processing": "Processing...",
        
        // Dictionary
        "dictionary.title": "Custom Dictionary",
        "dictionary.from": "From",
        "dictionary.to": "To",
        "dictionary.add_entry": "Add Entry",
        "dictionary.no_entries": "No entries",
        "dictionary.description": "Define custom replacements for transcription",
        
        // Snippets
        "snippets.title": "Snippets",
        "snippets.trigger": "Trigger",
        "snippets.expansion": "Expansion",
        "snippets.add_snippet": "Add Snippet",
        "snippets.no_snippets": "No snippets",
        "snippets.description": "Define shortcuts that expand to full text"
    ],
    
    .japanese: [
        // Common
        "common.ok": "OK",
        "common.cancel": "キャンセル",
        "common.save": "保存",
        "common.delete": "削除",
        "common.edit": "編集",
        "common.add": "追加",
        "common.close": "閉じる",
        "common.settings": "設定...",
        "common.quit": "Gemisperを終了",
        "common.version": "バージョン",
        "common.build": "ビルド",
        "common.search": "検索",
        
        // Menu Bar
        "menubar.start_recording": "録音開始 (⌘⇧F3)",
        "menubar.stop_recording": "録音停止",
        "menubar.push_to_talk": "Push to Talk (%@)",
        "menubar.custom_dictionary": "カスタム辞書...",
        "menubar.snippets": "スニペット...",
        "menubar.usage": "使用量",
        "menubar.recent": "  直近: %@ tokens",
        "menubar.today_total": "  今日の累計: %@ tokens",
        "menubar.today_estimated": "  今日の概算: $%.4f (¥%.2f)",
        "menubar.monthly_total": "  今月の累計: %@ tokens",
        "menubar.monthly_estimated": "  今月の概算: $%.4f (¥%.2f)",
        "menubar.no_data": "  直近: データなし",
        "menubar.quit_app": "Gemisperを終了",
        
        // Settings Tabs
        "settings_tab.general": "一般",
        "settings_tab.api": "API",
        "settings_tab.hotkey": "ホットキー",
        "settings_tab.prompt": "プロンプト",
        "settings_tab.advanced": "詳細",
        
        // Settings General
        "settings_general.transcription_options": "文字起こしオプション",
        "settings_general.remove_filler_words": "フィラーワードを除去",
        "settings_general.add_punctuation": "自動で句読点を追加",
        "settings_general.style": "文体スタイル",
        "settings_general.language": "言語",
        "settings_general.interface": "インターフェース",
        "settings_general.show_overlay": "録音インジケーターを表示",
        "settings_general.show_overlay_help": "画面下部に小さく録音中のインジケーターを表示します",
        "settings_general.play_sound_effects": "効果音を再生",
        "settings_general.app_language": "アプリの言語",
        
        // Settings API
        "settings_api.gemini_api": "Gemini API",
        "settings_api.api_key": "APIキー",
        "settings_api.api_key_placeholder": "APIキーを入力",
        "settings_api.hide": "隠す",
        "settings_api.show": "表示",
        "settings_api.paste": "クリップボードから貼り付け",
        "settings_api.validate": "検証",
        "settings_api.api_key_valid": "APIキーは有効です",
        "settings_api.api_key_invalid": "APIキーが無効です",
        "settings_api.get_api_key": "Gemini APIキーは Google AI Studio から取得できます",
        "settings_api.model_settings": "モデル設定",
        "settings_api.model": "モデル",
        "settings_api.pricing": "料金: %@",
        "settings_api.free_tier": "無料枠あり",
        
        // Settings Hotkey
        "settings_hotkey.input_mode": "入力モード",
        "settings_hotkey.mode": "モード",
        "settings_hotkey.push_to_talk_mode": "Push to Talk",
        "settings_hotkey.toggle_mode": "トグルモード",
        "settings_hotkey.push_to_talk_description": "キーを押している間だけ録音します",
        "settings_hotkey.toggle_description": "ホットキーで録音の開始/停止を切り替えます",
        "settings_hotkey.push_to_talk_keys": "Push to Talk キー（複数選択可）",
        "settings_hotkey.current_setting": "現在の設定:",
        "settings_hotkey.press_to_talk": "%@ を押して話す",
        "settings_hotkey.toggle_hotkey": "トグルホットキー",
        "settings_hotkey.current_hotkey": "現在のホットキー: %@",
        "settings_hotkey.set_new_hotkey": "新しいホットキーを設定:",
        "settings_hotkey.click_to_record_hotkey": "クリックしてホットキーを入力",
        "settings_hotkey.press_key": "キーを押してください...",
        "settings_hotkey.presets": "プリセット",
        
        // Settings Prompt
        "settings_prompt.system_prompt": "システムプロンプト",
        "settings_prompt.custom_prompt": "カスタムプロンプト",
        "settings_prompt.use_custom_prompt": "カスタムプロンプトを使用",
        "settings_prompt.default_prompt_description": "デフォルト: フィラーワードを除去し句読点を追加して文字起こし",
        "settings_prompt.custom_prompt_placeholder": "カスタムプロンプトを入力...",
        
        // Settings Advanced
        "settings_advanced.debug": "デバッグ",
        "settings_advanced.enable_logging": "ログを有効化",
        "settings_advanced.clear_cache": "キャッシュをクリア",
        "settings_advanced.app_info": "アプリ情報",
        
        // Alerts
        "alert.microphone_access_required": "マイクへのアクセスが必要です",
        "alert.microphone_access_message": "システム設定でマイクへのアクセスを許可してください。",
        "alert.open_settings": "設定を開く",
        "alert.error_occurred": "エラーが発生しました",
        "alert.api_key_required": "Gemini APIキーが必要です",
        "alert.api_key_required_message": "設定画面でGemini APIキーを入力してください。",
        "alert.api_key_required_detail": "Google AI Studioで無料で取得できます。",
        "alert.later": "後で",
        
        // Styles
        "style.natural": "自然",
        "style.formal": "フォーマル",
        "style.casual": "カジュアル",
        "style.concise": "簡潔",
        
        // Transcription Language
        "transcription_language.japanese": "日本語",
        "transcription_language.english": "英語",
        "transcription_language.auto": "自動検出",
        
        // Overlay
        "overlay.listening": "録音中...",
        "overlay.processing": "処理中...",
        
        // Dictionary
        "dictionary.title": "カスタム辞書",
        "dictionary.from": "変換前",
        "dictionary.to": "変換後",
        "dictionary.add_entry": "エントリを追加",
        "dictionary.no_entries": "エントリがありません",
        "dictionary.description": "文字起こし時のカスタム置換を定義",
        
        // Snippets
        "snippets.title": "スニペット",
        "snippets.trigger": "トリガー",
        "snippets.expansion": "展開テキスト",
        "snippets.add_snippet": "スニペットを追加",
        "snippets.no_snippets": "スニペットがありません",
        "snippets.description": "ショートカットから全文に展開する定義"
    ]
]

// MARK: - String Extension for Formatting
extension L10n {
    static func format(_ localizedString: String, _ args: CVarArg...) -> String {
        return String(format: localizedString, arguments: args)
    }
}
