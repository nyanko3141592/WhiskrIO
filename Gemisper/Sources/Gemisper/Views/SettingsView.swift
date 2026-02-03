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
            
            // 高度な設定
            advancedSettings
                .tabItem {
                    Label("詳細", systemImage: "slider.horizontal.3")
                }
        }
        .frame(width: 500, height: 450)
        .padding()
    }
    
    // MARK: - General Settings
    
    private var generalSettings: some View {
        Form {
            Section("文字起こしオプション") {
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
            }
            
            Section("インターフェース") {
                Toggle("録音インジケーターを表示", isOn: $settingsManager.settings.showOverlay)
                    .help("画面下部に小さく録音中のインジケーターを表示します")
                
                Toggle("効果音を再生", isOn: $settingsManager.settings.playSoundEffects)
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
            Section("Gemini API") {
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
            }
            
            Section("モデル設定") {
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
