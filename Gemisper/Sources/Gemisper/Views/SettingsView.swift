import SwiftUI

struct SettingsView: View {
    @StateObject private var settingsManager = SettingsManager.shared
    @State private var isValidatingKey = false
    @State private var keyStatus: KeyStatus = .unknown
    
    enum KeyStatus {
        case unknown
        case valid
        case invalid
    }
    
    var body: some View {
        TabView {
            // 一般設定
            generalSettings
                .tabItem {
                    Label("一般", systemImage: "gear")
                }
            
            // API設定
            apiSettings
                .tabItem {
                    Label("API", systemImage: "key")
                }
            
            // ホットキー設定
            hotkeySettings
                .tabItem {
                    Label("ホットキー", systemImage: "keyboard")
                }
            
            // プロンプト設定
            promptSettings
                .tabItem {
                    Label("プロンプト", systemImage: "text.quote")
                }
            
            // 高度な設定
            advancedSettings
                .tabItem {
                    Label("詳細", systemImage: "slider.horizontal.3")
                }
            
            // ルール設定
            rulesSettings
                .tabItem {
                    Label("ルール", systemImage: "doc.text")
                }
        }
        .frame(width: 550, height: 500)
        .padding()
    }
    
    // MARK: - General Settings
    
    private var generalSettings: some View {
        Form {
            Section {
                Toggle("フィラーワードを除去", isOn: $settingsManager.settings.removeFillerWords)
                Toggle("自動で句読点を追加", isOn: $settingsManager.settings.addPunctuation)
                Picker("文体スタイル", selection: $settingsManager.settings.style) {
                    ForEach(TranscriptionStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                Picker("言語", selection: $settingsManager.settings.language) {
                    Text("日本語").tag("ja")
                    Text("英語").tag("en")
                    Text("自動検出").tag("auto")
                }
            } header: {
                Text("文字起こしオプション")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            Section {
                Toggle("録音インジケーターを表示", isOn: $settingsManager.settings.showOverlay)
                    .help("画面下部に小さく録音中のインジケーターを表示します")
                Toggle("効果音を再生", isOn: $settingsManager.settings.playSoundEffects)
            } header: {
                Text("インターフェース")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settingsManager.settings) { _ in
            settingsManager.saveSettings()
        }
    }
    
    // MARK: - API Settings
    
    @State private var showAPIKey = false
    
    private var apiSettings: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("APIキー")
                        .font(.headline)
                    
                    HStack {
                        // SecureFieldはペーストに問題があるためTextFieldを使用
                        // 表示/非表示切り替えで対応
                        if showAPIKey {
                            TextField("APIキーを入力", text: $settingsManager.settings.apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("APIキーを入力", text: $settingsManager.settings.apiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        // 表示/非表示切り替えボタン
                        Button(action: { showAPIKey.toggle() }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(showAPIKey ? "隠す" : "表示")
                        
                        // ペーストボタン
                        Button(action: pasteFromClipboard) {
                            Image(systemName: "doc.on.clipboard")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("クリップボードから貼り付け")
                        
                        Button(action: validateAPIKey) {
                            if isValidatingKey {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("検証")
                            }
                        }
                        .disabled(settingsManager.settings.apiKey.isEmpty || isValidatingKey)
                    }
                    
                    HStack {
                        switch keyStatus {
                        case .valid:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("APIキーは有効です")
                                .foregroundColor(.green)
                        case .invalid:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("APIキーが無効です")
                                .foregroundColor(.red)
                        case .unknown:
                            EmptyView()
                        }
                    }
                    .font(.caption)
                }
                
                Text("Gemini APIキーは [Google AI Studio](https://aistudio.google.com/app/apikey) から取得できます。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            } header: {
                Text("Gemini API")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            Section {
                Picker("モデル", selection: $settingsManager.settings.selectedModel) {
                    ForEach(GeminiModel.allCases.filter { $0.isRecommended }, id: \.self) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                
                // 選択中のモデルの説明
                VStack(alignment: .leading, spacing: 4) {
                    Text(settingsManager.settings.selectedModel.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("料金: \(settingsManager.settings.selectedModel.pricingDescription)")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        
                        if settingsManager.settings.selectedModel.hasFreeTier {
                            Text("無料枠あり")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        }
                    }
                }
                .padding(.top, 4)
            } header: {
                Text("モデル設定")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settingsManager.settings.apiKey) { _ in
            settingsManager.saveSettings()
            keyStatus = .unknown
        }
        .onChange(of: settingsManager.settings.selectedModel) { _ in
            settingsManager.saveSettings()
        }
    }
    
    // MARK: - Hotkey Settings
    
    private var hotkeySettings: some View {
        Form {
            Section("入力モード") {
                Picker("モード", selection: $settingsManager.settings.pushToTalkMode) {
                    Text("Push to Talk").tag(true)
                    Text("トグルモード").tag(false)
                }
                .pickerStyle(.segmented)
                .onChange(of: settingsManager.settings.pushToTalkMode) { _ in
                    settingsManager.saveSettings()
                    NotificationCenter.default.post(name: .updateHotkey, object: nil)
                }
                
                if settingsManager.settings.pushToTalkMode {
                    Text("キーを押している間だけ録音します")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("ホットキーで録音の開始/停止を切り替えます")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if settingsManager.settings.pushToTalkMode {
                Section("Push to Talk キー（複数選択可）") {
                    // 複合キー選択
                    HStack(spacing: 8) {
                        ForEach(PushToTalkKey.allCases, id: \.self) { key in
                            Toggle(key.shortDisplayName, isOn: Binding(
                                get: {
                                    settingsManager.settings.pushToTalkKeys.contains(key)
                                },
                                set: { isSelected in
                                    if isSelected {
                                        settingsManager.settings.pushToTalkKeys.append(key)
                                    } else {
                                        settingsManager.settings.pushToTalkKeys.removeAll { $0 == key }
                                    }
                                    // 最低1つは選択されていることを保証
                                    if settingsManager.settings.pushToTalkKeys.isEmpty {
                                        settingsManager.settings.pushToTalkKeys = [.option]
                                    }
                                    settingsManager.saveSettings()
                                    NotificationCenter.default.post(name: .updateHotkey, object: nil)
                                }
                            ))
                            .toggleStyle(.button)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    HStack {
                        Text("現在の設定:")
                        Spacer()
                        Text("\(settingsManager.settings.pushToTalkKeys.combinedDisplayName) を押して話す")
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
            } else {
                Section("トグルホットキー") {
                    Text("現在のホットキー: \(hotkeyDescription)")
                        .font(.headline)
                    
                    Text("新しいホットキーを設定:")
                        .padding(.top, 8)
                    
                    HotkeyRecorderView { modifierFlags, keyCode in
                        settingsManager.settings.hotkeyModifier = Int(modifierFlags.rawValue)
                        settingsManager.settings.hotkeyKeyCode = Int(keyCode)
                        settingsManager.saveSettings()
                        
                        // ホットキーを再登録
                        NotificationCenter.default.post(name: .updateHotkey, object: nil)
                    }
                    .frame(height: 60)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Section("プリセット") {
                    HStack {
                        Button("⌘⇧F3") {
                            setHotkey(modifier: .command.union(.shift), keyCode: 99)
                        }
                        
                        Button("⌥Space") {
                            setHotkey(modifier: .option, keyCode: 49)
                        }
                        
                        Button("Fn F6") {
                            setHotkey(modifier: .function, keyCode: 97)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
    
    private var hotkeyDescription: String {
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(settingsManager.settings.hotkeyModifier))
        var description = ""
        
        if modifiers.contains(.command) { description += "⌘" }
        if modifiers.contains(.option) { description += "⌥" }
        if modifiers.contains(.control) { description += "⌃" }
        if modifiers.contains(.shift) { description += "⇧" }
        
        let keyCode = settingsManager.settings.hotkeyKeyCode
        description += KeyCodeHelper.stringForKeyCode(keyCode)
        
        return description
    }
    
    private func setHotkey(modifier: NSEvent.ModifierFlags, keyCode: Int) {
        settingsManager.settings.hotkeyModifier = Int(modifier.rawValue)
        settingsManager.settings.hotkeyKeyCode = keyCode
        settingsManager.saveSettings()
        NotificationCenter.default.post(name: .updateHotkey, object: nil)
    }
    
    // MARK: - Prompt Settings
    
    private var promptSettings: some View {
        Form {
            Section("文字起こしプロンプト") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("カスタムプロンプト")
                        .font(.headline)
                    
                    Text("空欄の場合はデフォルトプロンプトを使用します")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: Binding(
                        get: { settingsManager.settings.customPrompt ?? "" },
                        set: { newValue in
                            settingsManager.settings.customPrompt = newValue.isEmpty ? nil : newValue
                            settingsManager.saveSettings()
                        }
                    ))
                    .frame(height: 120)
                    .font(.system(.body, design: .monospaced))
                    .border(Color.gray.opacity(0.3), width: 1)
                    
                    HStack {
                        Button("デフォルトに戻す") {
                            settingsManager.settings.customPrompt = nil
                            settingsManager.saveSettings()
                        }
                        .disabled(settingsManager.settings.customPrompt == nil)
                        
                        Spacer()
                        
                        Button("クリア") {
                            settingsManager.settings.customPrompt = ""
                            settingsManager.saveSettings()
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("デフォルトプロンプト:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Transcribe the following audio to text. Remove filler words like \"um\", \"uh\", \"like\", \"you know\". Add appropriate punctuation. Format as clean, readable text.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)
                }
                .padding(.top, 8)
            }
            
            Section("コマンドモード") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("トリガーワード")
                        .font(.headline)
                    
                    Text("音声入力の先頭にこれらのワードがある場合、zshコマンドとして解釈されます")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // トリガーワードリスト
                    FlowLayout(spacing: 8) {
                        ForEach(settingsManager.settings.commandModeTriggers, id: \.self) { trigger in
                            HStack(spacing: 4) {
                                Text(trigger)
                                    .font(.system(.body, design: .monospaced))
                                
                                Button(action: {
                                    settingsManager.settings.commandModeTriggers.removeAll { $0 == trigger }
                                    settingsManager.saveSettings()
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                        }
                    }
                    
                    // 新しいトリガー追加
                    HStack {
                        TextField("新しいトリガー", text: $newTriggerInput)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("追加") {
                            let trimmed = newTriggerInput.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty && !settingsManager.settings.commandModeTriggers.contains(trimmed) {
                                settingsManager.settings.commandModeTriggers.append(trimmed)
                                settingsManager.saveSettings()
                                newTriggerInput = ""
                            }
                        }
                        .disabled(newTriggerInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.top, 8)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("使用例:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\"コマンド ホームディレクトリのファイル一覧\" → ls ~")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)
                }
                .padding(.top, 8)
            }
        }
        .formStyle(.grouped)
    }
    
    @State private var newTriggerInput: String = ""
    
    // MARK: - Rules Settings States
    @State private var rulesValidationError: String? = nil
    @State private var isRulesValid: Bool = true
    @State private var showRulesResetConfirmation: Bool = false
    
    // MARK: - Advanced Settings
    
    private var advancedSettings: some View {
        Form {
            Section("デバッグ") {
                Toggle("ログを有効化", isOn: .constant(false))
                    .disabled(true)
                
                Button("キャッシュをクリア") {
                    clearCache()
                }
            }
            
            Section("アプリ情報") {
                HStack {
                    Text("バージョン")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("ビルド")
                    Spacer()
                    Text("2025.02.03")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
    
    private func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        if let string = pasteboard.string(forType: .string) {
            settingsManager.settings.apiKey = string
            settingsManager.saveSettings()
        }
    }
    
    private func validateAPIKey() {
        isValidatingKey = true
        
        Task {
            let service = GeminiService()
            let isValid = await service.validateAPIKey()
            
            DispatchQueue.main.async {
                self.keyStatus = isValid ? .valid : .invalid
                self.isValidatingKey = false
            }
        }
    }
    
    private func clearCache() {
        let tempDir = FileManager.default.temporaryDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix("recording_") {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
    
    // MARK: - Rules Settings
    
    private var rulesSettings: some View {
        Form {
            Section {
                Toggle("ルールシステムを有効化", isOn: $settingsManager.settings.rulesEnabled)
                    .onChange(of: settingsManager.settings.rulesEnabled) { _ in
                        settingsManager.saveSettings()
                    }
                
                Text("音声入力の先頭にキーワードを検出し、自動で処理を切り替えます")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("ルール設定ファイル") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("~/.config/gemisper/rules.yaml")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("フォルダを開く") {
                            openRulesDirectory()
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                    
                    // YAMLエディタ
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $settingsManager.rulesYAMLContent)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 200, maxHeight: .infinity)
                            .border(validationBorderColor, width: 1)
                            .onChange(of: settingsManager.rulesYAMLContent) { newValue in
                                validateRulesContent(newValue)
                            }
                        
                        if settingsManager.rulesYAMLContent.isEmpty {
                            Text("YAML形式でルールを定義...")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
                    
                    // 検証結果
                    if let error = rulesValidationError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding(.vertical, 4)
                    } else if !settingsManager.rulesYAMLContent.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("有効なYAMLです")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    HStack {
                        Button("デフォルトに戻す") {
                            showRulesResetConfirmation = true
                        }
                        .alert("ルールをリセット", isPresented: $showRulesResetConfirmation) {
                            Button("キャンセル", role: .cancel) {}
                            Button("リセット", role: .destructive) {
                                resetRulesToDefault()
                            }
                        } message: {
                            Text("ルール設定をデフォルトに戻しますか？現在の設定は失われます。")
                        }
                        
                        Spacer()
                        
                        Button("保存") {
                            saveRules()
                        }
                        .disabled(!isRulesValid)
                        .keyboardShortcut("s", modifiers: .command)
                    }
                }
            }
            
            Section("トリガールール一覧") {
                let config = parseCurrentConfig()
                if config.triggers.isEmpty {
                    Text("定義されたトリガーがありません")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(config.triggers) { rule in
                            RulePreviewRow(rule: rule)
                        }
                    }
                }
            }
            
            Section("使用例") {
                VStack(alignment: .leading, spacing: 8) {
                    ExampleRow(
                        trigger: "コマンド",
                        input: "ホームディレクトリのファイル一覧を表示",
                        output: "ls ~"
                    )
                    ExampleRow(
                        trigger: "英語",
                        input: "Hello, how are you today?",
                        output: "こんにちは、今日はお元気ですか？"
                    )
                    ExampleRow(
                        trigger: "markdown",
                        input: "タイトルと箇条書きを含むテキスト",
                        output: "整形されたMarkdown形式"
                    )
                }
            }
        }
        .formStyle(.grouped)
    }
    
    private var validationBorderColor: Color {
        if let _ = rulesValidationError {
            return .orange
        }
        return Color.gray.opacity(0.3)
    }
    
    private func validateRulesContent(_ content: String) {
        let result = settingsManager.validateYAMLRules(content)
        isRulesValid = result.isValid
        rulesValidationError = result.error
    }
    
    private func saveRules() {
        do {
            try settingsManager.saveYAMLRules(settingsManager.rulesYAMLContent)
            // 成功通知
            rulesValidationError = nil
        } catch {
            rulesValidationError = "保存に失敗しました: \(error.localizedDescription)"
        }
    }
    
    private func resetRulesToDefault() {
        do {
            try settingsManager.resetYAMLRulesToDefault()
            rulesValidationError = nil
        } catch {
            rulesValidationError = "リセットに失敗しました: \(error.localizedDescription)"
        }
    }
    
    private func openRulesDirectory() {
        let path = settingsManager.getYAMLRulesFilePath()
        let directory = (path as NSString).deletingLastPathComponent
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: directory)])
    }
    
    private func parseCurrentConfig() -> RuleConfig {
        do {
            return try RuleConfig.fromYAML(settingsManager.rulesYAMLContent)
        } catch {
            return RuleConfig.default
        }
    }
}

// MARK: - Rule Preview Row

struct RulePreviewRow: View {
    let rule: TriggerRule
    
    var body: some View {
        HStack(spacing: 12) {
            // アイコン
            Image(systemName: rule.action.icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name)
                    .font(.system(.body, weight: .medium))
                
                // キーワード
                HStack(spacing: 4) {
                    ForEach(rule.keywords, id: \.self) { keyword in
                        Text(keyword)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                }
                
                // アクション
                Text(rule.action.displayName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Example Row

struct ExampleRow: View {
    let trigger: String
    let input: String
    let output: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(trigger)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .cornerRadius(4)
                
                Text(input)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(output)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .italic()
            }
            .padding(.leading, 8)
        }
        .padding(.vertical, 2)
    }
}


// MARK: - Hotkey Recorder View

struct HotkeyRecorderView: NSViewRepresentable {
    let onRecord: (NSEvent.ModifierFlags, UInt16) -> Void
    
    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.onRecord = onRecord
        return view
    }
    
    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {}
}

class HotkeyRecorderNSView: NSView {
    var onRecord: ((NSEvent.ModifierFlags, UInt16) -> Void)?
    private var isRecording = false
    private var label: NSTextField?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        let textField = NSTextField(labelWithString: "クリックしてホットキーを入力")
        textField.alignment = .center
        textField.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)
        label = textField
        
        NSLayoutConstraint.activate([
            textField.centerXAnchor.constraint(equalTo: centerXAnchor),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    override func mouseDown(with event: NSEvent) {
        isRecording = !isRecording
        
        if isRecording {
            label?.stringValue = "キーを押してください..."
            window?.makeFirstResponder(self)
        } else {
            label?.stringValue = "クリックしてホットキーを入力"
        }
    }
    
    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }
        
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode
        
        // 修飾キーのみは無視
        let modifierKeyCodes: [UInt16] = [54, 55, 56, 58, 59, 60, 61, 62] // Cmd, Opt, Ctrl, Shift
        guard !modifierKeyCodes.contains(keyCode) else { return }
        
        onRecord?(modifiers, keyCode)
        
        isRecording = false
        label?.stringValue = "クリックしてホットキーを入力"
    }
    
    override var acceptsFirstResponder: Bool { true }
}

extension Notification.Name {
    static let updateHotkey = Notification.Name("updateHotkey")
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: result.positions[index].x + bounds.minX, 
                                      y: result.positions[index].y + bounds.minY), 
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var positions: [CGPoint] = []
        var size: CGSize = .zero
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}
