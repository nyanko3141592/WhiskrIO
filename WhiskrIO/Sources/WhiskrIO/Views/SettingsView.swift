import SwiftUI
import AVFoundation
import ApplicationServices

struct SettingsView: View {
    @StateObject private var settingsManager = SettingsManager.shared
    @StateObject private var historyManager = TranscriptionHistoryManager.shared
    @StateObject private var recordingManager = RecordingManager()
    @StateObject private var voxtralServerManager = VoxtralServerManager.shared
    @State private var isValidatingKey = false
    @State private var keyStatus: KeyStatus = .unknown
    @State private var isTestingVoxtral = false
    @State private var voxtralTestResult: VoxtralTestResult = .none

    enum VoxtralTestResult {
        case none
        case success
        case failure(String)
    }
    
    enum KeyStatus {
        case unknown
        case valid
        case invalid
    }
    
    var body: some View {
        TabView {
            // 入力設定（メイン - ホットキー + Push to Talk）
            inputSettings
                .tabItem {
                    Label("入力", systemImage: "pawprint.fill")
                }

            // API設定
            apiSettings
                .tabItem {
                    Label("API", systemImage: "fish.fill")
                }

            // ルール設定
            rulesSettings
                .tabItem {
                    Label("ルール", systemImage: "list.bullet.rectangle.fill")
                }

            // 履歴
            historySettings
                .tabItem {
                    Label("履歴", systemImage: "clock.arrow.circlepath")
                }

            // 詳細設定（プロンプト+デバッグ+アプリ情報）
            advancedSettings
                .tabItem {
                    Label("詳細", systemImage: "cat.fill")
                }
        }
        .frame(width: 600, height: 500)
        .padding()
        .tabViewStyle(.automatic)
        .tint(Color.whiskrAccent)
    }
    
    // MARK: - API Settings
    
    @State private var showAPIKey = false
    
    private var apiSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Gemini API
                GroupBox(label: Label("Gemini API", systemImage: "key.fill")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            if showAPIKey {
                                TextField("APIキーを入力", text: $settingsManager.settings.apiKey)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("APIキーを入力", text: $settingsManager.settings.apiKey)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button(action: { showAPIKey.toggle() }) {
                                Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(showAPIKey ? "隠す" : "表示")

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

                        Text("Gemini APIキーは [Google AI Studio](https://aistudio.google.com/app/apikey) から取得できます。")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Divider()

                        Picker("モデル", selection: $settingsManager.settings.selectedModel) {
                            ForEach(GeminiModel.allCases.filter { $0.isRecommended }, id: \.self) { model in
                                Text(model.displayName).tag(model)
                            }
                        }

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
                    }
                    .padding(.vertical, 4)
                }

                // 選択テキスト編集
                GroupBox(label: Label("テキスト編集", systemImage: "pencil.line")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Apple Intelligence で書き直す", isOn: $settingsManager.settings.useAppleIntelligenceForEdit)

                        Text("テキスト選択時にPush to Talkすると、Apple Intelligenceの作文ツールを起動します。OFFの場合は音声指示+Geminiで編集します。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // ローカル文字起こし（Voxtral）
                GroupBox(label: Label(L10n.Voxtral.localTranscription, systemImage: "desktopcomputer")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(L10n.Voxtral.useLocalModel, isOn: $settingsManager.settings.useLocalTranscription)

                        if settingsManager.settings.useLocalTranscription {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L10n.Voxtral.serverSettings)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                HStack {
                                    Text(L10n.Voxtral.host)
                                        .frame(width: 50, alignment: .trailing)
                                    TextField("127.0.0.1", text: $settingsManager.settings.voxtralHost)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 150)

                                    Text(L10n.Voxtral.port)
                                        .frame(width: 40, alignment: .trailing)
                                    TextField("8000", value: $settingsManager.settings.voxtralPort, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                }

                                HStack(spacing: 12) {
                                    if voxtralServerManager.status.isRunning {
                                        Button(action: { VoxtralServerManager.shared.stopServer() }) {
                                            Text("Stop Server")
                                        }
                                    } else {
                                        Button(action: { VoxtralServerManager.shared.startServer() }) {
                                            Text("Start Server")
                                        }
                                    }

                                    HStack(spacing: 4) {
                                        switch voxtralServerManager.status {
                                        case .stopped:
                                            Circle()
                                                .fill(Color.gray)
                                                .frame(width: 8, height: 8)
                                            Text("Stopped")
                                                .foregroundColor(.secondary)
                                        case .starting:
                                            ProgressView()
                                                .controlSize(.small)
                                            Text("Starting...")
                                                .foregroundColor(.orange)
                                        case .loadingModel:
                                            ProgressView()
                                                .controlSize(.small)
                                            Text("Loading model...")
                                                .foregroundColor(.orange)
                                        case .ready:
                                            Circle()
                                                .fill(Color.green)
                                                .frame(width: 8, height: 8)
                                            Text("Ready")
                                                .foregroundColor(.green)
                                        case .error(let msg):
                                            Circle()
                                                .fill(Color.red)
                                                .frame(width: 8, height: 8)
                                            Text(msg)
                                                .foregroundColor(.red)
                                                .lineLimit(1)
                                        }
                                    }
                                    .font(.caption)
                                }

                                HStack {
                                    Button(action: testVoxtralConnection) {
                                        if isTestingVoxtral {
                                            HStack(spacing: 4) {
                                                ProgressView()
                                                    .controlSize(.small)
                                                Text(L10n.Voxtral.testing)
                                            }
                                        } else {
                                            Text(L10n.Voxtral.testConnection)
                                        }
                                    }
                                    .disabled(isTestingVoxtral || voxtralServerManager.status != .ready)

                                    switch voxtralTestResult {
                                    case .success:
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                            Text(L10n.Voxtral.connectionSuccess)
                                                .foregroundColor(.green)
                                        }
                                        .font(.caption)
                                    case .failure(let msg):
                                        HStack(spacing: 4) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                            Text("\(L10n.Voxtral.connectionFailed): \(msg)")
                                                .foregroundColor(.red)
                                                .lineLimit(2)
                                        }
                                        .font(.caption)
                                    case .none:
                                        EmptyView()
                                    }
                                }
                            }
                            .padding(.leading, 20)

                            Text(L10n.Voxtral.geminiRequired)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: settingsManager.settings.apiKey) { _ in
            settingsManager.saveSettings()
            keyStatus = .unknown
        }
        .onChange(of: settingsManager.settings.selectedModel) { _ in
            settingsManager.saveSettings()
        }
        .onChange(of: settingsManager.settings.useLocalTranscription) { _ in
            settingsManager.saveSettings()
            NotificationCenter.default.post(name: .localTranscriptionToggled, object: nil)
        }
        .onChange(of: settingsManager.settings.voxtralHost) { _ in
            settingsManager.saveSettings()
        }
        .onChange(of: settingsManager.settings.voxtralPort) { _ in
            settingsManager.saveSettings()
        }
        .onChange(of: settingsManager.settings.useAppleIntelligenceForEdit) { _ in
            settingsManager.saveSettings()
        }
    }

    // MARK: - Input Settings (Hotkey + Push to Talk)

    @State private var isRecordingShortcut = false

    private var inputSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // マイク
                GroupBox(label: Label("マイク", systemImage: "mic.fill")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Picker("入力デバイス", selection: Binding(
                                get: { settingsManager.settings.selectedMicrophoneID ?? "" },
                                set: { newValue in
                                    settingsManager.settings.selectedMicrophoneID = newValue.isEmpty ? nil : newValue
                                    settingsManager.saveSettings()
                                }
                            )) {
                                Text("システムデフォルト").tag("")
                                ForEach(recordingManager.availableMicrophones) { mic in
                                    Text(mic.name + (mic.isDefault ? " (デフォルト)" : "")).tag(mic.id)
                                }
                            }

                            Button(action: { recordingManager.refreshMicrophoneList() }) {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.plain)
                            .help("マイク一覧を更新")
                        }
                    }
                    .padding(.vertical, 4)
                }

                // 入力モード + ショートカット
                GroupBox(label: Label("入力モード", systemImage: "keyboard")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("モード", selection: $settingsManager.settings.pushToTalkMode) {
                            Text("Push to Talk").tag(true)
                            Text("トグル").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: settingsManager.settings.pushToTalkMode) { _ in
                            settingsManager.saveSettings()
                            NotificationCenter.default.post(name: .updateHotkey, object: nil)
                        }

                        Text(settingsManager.settings.pushToTalkMode
                            ? "キーを押している間だけ録音します"
                            : "ショートカットで録音の開始/停止を切り替えます")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Divider()

                        // ショートカット表示 + レコーダー
                        HStack {
                            Text("ショートカット")
                                .font(.subheadline)

                            Spacer()

                            // 現在のショートカット表示
                            Text(settingsManager.settings.pushToTalkShortcut.displayName)
                                .font(.system(.body, design: .monospaced, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(isRecordingShortcut ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: isRecordingShortcut ? 2 : 1)
                                )

                            Button(isRecordingShortcut ? "キャンセル" : "変更...") {
                                isRecordingShortcut.toggle()
                            }
                            .controlSize(.small)
                        }

                        if isRecordingShortcut {
                            ShortcutRecorderView(
                                onRecord: { shortcut in
                                    settingsManager.settings.pushToTalkShortcut = shortcut
                                    settingsManager.saveSettings()
                                    NotificationCenter.default.post(name: .updateHotkey, object: nil)
                                    isRecordingShortcut = false
                                },
                                onCancel: {
                                    isRecordingShortcut = false
                                }
                            )
                            .frame(height: 44)
                            .background(Color.accentColor.opacity(0.08))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                            )
                        }

                        // プリセット
                        HStack(spacing: 8) {
                            Text("プリセット")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button("⌥ + ⌘") {
                                setShortcut(PushToTalkShortcut(modifierFlags: NSEvent.ModifierFlags([.option, .command]).rawValue, keyCode: nil))
                            }
                            .controlSize(.small)

                            Button("⌃ + Space") {
                                setShortcut(PushToTalkShortcut(modifierFlags: NSEvent.ModifierFlags([.control]).rawValue, keyCode: 49))
                            }
                            .controlSize(.small)

                            Button("F13") {
                                setShortcut(PushToTalkShortcut(modifierFlags: 0, keyCode: 105))
                            }
                            .controlSize(.small)

                            Button("⌘ + ⇧ + F3") {
                                setShortcut(PushToTalkShortcut(modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue, keyCode: 99))
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // 録音設定
                GroupBox(label: Label("録音設定", systemImage: "waveform")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("文字起こし言語", selection: $settingsManager.settings.speechLanguage) {
                            ForEach(SpeechLanguage.allCases, id: \.self) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .onChange(of: settingsManager.settings.speechLanguage) { _ in
                            settingsManager.saveSettings()
                        }

                        Text("「自動検出」では英語と誤認識されることがあります")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Divider()

                        Picker("録音時間の上限", selection: $settingsManager.settings.maxRecordingDuration) {
                            Text("30秒").tag(30)
                            Text("1分").tag(60)
                            Text("2分").tag(120)
                            Text("3分").tag(180)
                            Text("5分").tag(300)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: settingsManager.settings.maxRecordingDuration) { _ in
                            settingsManager.saveSettings()
                        }

                        Divider()

                        Toggle("画面のスクリーンショットを送信", isOn: $settingsManager.settings.captureScreenshot)
                            .onChange(of: settingsManager.settings.captureScreenshot) { newValue in
                                settingsManager.saveSettings()
                                if newValue && !ScreenshotManager.shared.hasScreenRecordingPermission() {
                                    ScreenshotManager.shared.requestScreenRecordingPermission()
                                }
                            }

                        if settingsManager.settings.captureScreenshot {
                            Picker("キャプチャ範囲", selection: $settingsManager.settings.captureSize) {
                                ForEach(CaptureSize.allCases, id: \.self) { size in
                                    Text(size.displayName).tag(size)
                                }
                            }
                            .onChange(of: settingsManager.settings.captureSize) { _ in
                                settingsManager.saveSettings()
                            }
                            .padding(.leading, 20)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // 表示
                GroupBox(label: Label("表示", systemImage: "display")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("キャラクターの位置", selection: $settingsManager.settings.overlayPosition) {
                            ForEach(OverlayPosition.allCases, id: \.self) { position in
                                Label(position.displayName, systemImage: position.icon).tag(position)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: settingsManager.settings.overlayPosition) { _ in
                            settingsManager.saveSettings()
                            NotificationCenter.default.post(name: .updateOverlayPosition, object: nil)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func setShortcut(_ shortcut: PushToTalkShortcut) {
        settingsManager.settings.pushToTalkShortcut = shortcut
        settingsManager.saveSettings()
        NotificationCenter.default.post(name: .updateHotkey, object: nil)
        isRecordingShortcut = false
    }
    
    // MARK: - Rules Settings States
    @State private var rulesValidationError: String? = nil
    @State private var isRulesValid: Bool = true
    @State private var showRulesResetConfirmation: Bool = false
    @State private var showRuleEditor: Bool = false
    @State private var editingRule: TriggerRule? = nil
    @State private var showYAMLEditor: Bool = false
    @State private var ruleToDelete: TriggerRule? = nil
    @State private var showDeleteConfirmation: Bool = false
    @State private var currentRules: [TriggerRule] = []
    @State private var showAdvancedYAML: Bool = false

    // MARK: - History Settings States
    @State private var showHistoryClearConfirmation: Bool = false
    
    // MARK: - Advanced Settings

    private var advancedSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 権限
                GroupBox(label: Label("権限", systemImage: "lock.shield")) {
                    VStack(alignment: .leading, spacing: 12) {
                        PermissionRow(
                            icon: "mic.fill",
                            title: "マイク",
                            description: "音声入力に必要です",
                            isGranted: checkMicrophonePermission(),
                            onRequest: requestMicrophonePermission
                        )

                        PermissionRow(
                            icon: "keyboard",
                            title: "アクセシビリティ",
                            description: "テキスト入力に必要です",
                            isGranted: checkAccessibilityPermission(),
                            onRequest: requestAccessibilityPermission
                        )

                        PermissionRow(
                            icon: "rectangle.dashed.and.paperclip",
                            title: "画面収録",
                            description: "スクリーンショット送信に必要です",
                            isGranted: ScreenshotManager.shared.hasScreenRecordingPermission(),
                            onRequest: { ScreenshotManager.shared.requestScreenRecordingPermission() }
                        )
                    }
                    .padding(.vertical, 4)
                }

                // 文字起こしプロンプト
                GroupBox(label: Label("文字起こしプロンプト", systemImage: "text.bubble")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("音声を文字起こしする際にGeminiに送信するプロンプトです")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextEditor(text: Binding(
                            get: {
                                settingsManager.settings.customPrompt ?? GeminiService.defaultTranscriptionPrompt
                            },
                            set: { newValue in
                                if newValue.trimmingCharacters(in: .whitespacesAndNewlines) == GeminiService.defaultTranscriptionPrompt.trimmingCharacters(in: .whitespacesAndNewlines) {
                                    settingsManager.settings.customPrompt = nil
                                } else {
                                    settingsManager.settings.customPrompt = newValue
                                }
                                settingsManager.saveSettings()
                            }
                        ))
                        .frame(height: 120)
                        .font(.system(.body, design: .monospaced))
                        .border(Color.gray.opacity(0.3), width: 1)

                        HStack {
                            Button("デフォルトにリセット") {
                                settingsManager.settings.customPrompt = nil
                                settingsManager.saveSettings()
                            }
                            .disabled(settingsManager.settings.customPrompt == nil)

                            Spacer()

                            if settingsManager.settings.customPrompt != nil {
                                Text("カスタム")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            } else {
                                Text("デフォルト")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // アプリ情報
                GroupBox(label: Label("アプリ情報", systemImage: "info.circle")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("バージョン")
                            Spacer()
                            Text("1.0.0")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("ビルド")
                            Spacer()
                            Text("2025.02.04")
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        Button("キャッシュをクリア") {
                            clearCache()
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func testVoxtralConnection() {
        isTestingVoxtral = true
        voxtralTestResult = .none

        Task {
            let service = VoxtralService()
            let result = await service.testConnection()

            DispatchQueue.main.async {
                self.isTestingVoxtral = false
                if result.success {
                    self.voxtralTestResult = .success
                } else {
                    self.voxtralTestResult = .failure(result.message)
                }
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

    // MARK: - Permission Helpers

    private func checkMicrophonePermission() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        case .denied, .restricted:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }

    private func checkAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    private func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - History Settings

    private var historySettings: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Text("文字起こし履歴")
                    .font(.headline)

                Spacer()

                Text("\(historyManager.items.count) 件")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: {
                    showHistoryClearConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .disabled(historyManager.items.isEmpty)
                .help("すべての履歴を削除")
                .alert("履歴をクリア", isPresented: $showHistoryClearConfirmation) {
                    Button("キャンセル", role: .cancel) {}
                    Button("クリア", role: .destructive) {
                        historyManager.clearAll()
                    }
                } message: {
                    Text("すべての履歴を削除しますか？この操作は取り消せません。")
                }
            }
            .padding()

            Divider()

            if historyManager.items.isEmpty {
                // 履歴が空の場合
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("履歴がありません")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("音声入力の結果がここに表示されます")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // シンプルな履歴リスト
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(historyManager.items) { item in
                            HistoryItemCard(item: item, onDelete: {
                                historyManager.deleteItem(id: item.id)
                            }, onCopy: {
                                copyToClipboard(item.text)
                            })
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            historyManager.loadHistory()
        }
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Rules Settings

    private var rulesSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // ルールシステム有効化
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("ルールシステムを有効化", isOn: $settingsManager.settings.rulesEnabled)
                        .onChange(of: settingsManager.settings.rulesEnabled) { _ in
                            settingsManager.saveSettings()
                        }

                    Text("音声入力の先頭にキーワードを検出し、自動で処理を切り替えます")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // GUIルールリスト
                RulesListView(
                    rules: $currentRules,
                    onAdd: {
                        editingRule = nil
                        showRuleEditor = true
                    },
                    onEdit: { rule in
                        editingRule = rule
                        showRuleEditor = true
                    },
                    onDelete: { rule in
                        ruleToDelete = rule
                        showDeleteConfirmation = true
                    },
                    onReorder: { source, destination in
                        currentRules.move(fromOffsets: source, toOffset: destination)
                        saveCurrentRulesToYAML()
                    }
                )

                Divider()

                // 使用例
                VStack(alignment: .leading, spacing: 12) {
                    Text("使用例")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        ExampleRow(
                            trigger: "コマンド",
                            input: "ホームディレクトリのファイル一覧を表示",
                            output: "ls ~"
                        )
                        ExampleRow(
                            trigger: "ビジネスメール",
                            input: "明日の会議に参加します",
                            output: "お世話になっております。明日の会議に参加させていただきます。"
                        )
                        ExampleRow(
                            trigger: "要約",
                            input: "長いテキスト...",
                            output: "簡潔な要約文"
                        )
                    }
                    .padding(.leading, 4)
                }

                Divider()

                // 詳細設定（YAML直接編集）
                DisclosureGroup("詳細設定（YAML直接編集）", isExpanded: $showAdvancedYAML) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("~/.config/whiskrio/rules.yaml")
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
                                .frame(minHeight: 150, maxHeight: 200)
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
                                    loadRulesFromYAML()
                                }
                            } message: {
                                Text("ルール設定をデフォルトに戻しますか？現在の設定は失われます。")
                            }

                            Spacer()

                            Button("YAMLから読み込み") {
                                loadRulesFromYAML()
                            }

                            Button("保存") {
                                saveRules()
                                loadRulesFromYAML()
                            }
                            .disabled(!isRulesValid)
                            .keyboardShortcut("s", modifiers: .command)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadRulesFromYAML()
        }
        .sheet(isPresented: $showRuleEditor) {
            RuleEditorView(existingRule: editingRule) { rule in
                if let index = currentRules.firstIndex(where: { $0.id == rule.id }) {
                    currentRules[index] = rule
                } else {
                    currentRules.append(rule)
                }
                saveCurrentRulesToYAML()
            }
        }
        .alert("ルールを削除", isPresented: $showDeleteConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                if let rule = ruleToDelete {
                    currentRules.removeAll { $0.id == rule.id }
                    saveCurrentRulesToYAML()
                }
                ruleToDelete = nil
            }
        } message: {
            if let rule = ruleToDelete {
                Text("「\(rule.name)」を削除しますか？この操作は取り消せません。")
            }
        }
    }

    private func loadRulesFromYAML() {
        let config = parseCurrentConfig()
        currentRules = config.triggers
    }

    private func saveCurrentRulesToYAML() {
        do {
            var config = parseCurrentConfig()
            config.triggers = currentRules
            let yaml = try config.toYAML()
            try settingsManager.saveYAMLRules(yaml)
            settingsManager.rulesYAMLContent = yaml
            RuleEngine.shared.loadConfig()
        } catch {
            rulesValidationError = "保存に失敗しました: \(error.localizedDescription)"
        }
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


// MARK: - Shortcut Recorder View

struct ShortcutRecorderView: NSViewRepresentable {
    let onRecord: (PushToTalkShortcut) -> Void
    var onCancel: (() -> Void)?

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onRecord = onRecord
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {}
}

class ShortcutRecorderNSView: NSView {
    var onRecord: ((PushToTalkShortcut) -> Void)?
    var onCancel: (() -> Void)?
    private var label: NSTextField?
    private var localMonitor: Any?
    private var peakModifiers: NSEvent.ModifierFlags = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        let textField = NSTextField(labelWithString: "キーを入力してください... (ESCでキャンセル)")
        textField.alignment = .center
        textField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        textField.textColor = .secondaryLabelColor
        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)
        label = textField

        NSLayoutConstraint.activate([
            textField.centerXAnchor.constraint(equalTo: centerXAnchor),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        startMonitoring()
    }

    private func startMonitoring() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }
            return self.handleEvent(event)
        }
    }

    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyDown {
            if event.keyCode == 53 { // ESC
                stopMonitoring()
                DispatchQueue.main.async { [weak self] in
                    self?.onCancel?()
                }
                return nil
            }

            // 通常キー → モディファイア + キーコードとしてキャプチャ
            if !PushToTalkShortcut.isModifierKeyCode(event.keyCode) {
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let shortcut = PushToTalkShortcut(
                    modifierFlags: modifiers.rawValue,
                    keyCode: event.keyCode
                )
                stopMonitoring()
                DispatchQueue.main.async { [weak self] in
                    self?.onRecord?(shortcut)
                }
                return nil
            }
        } else if event.type == .flagsChanged {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if modifiers.isEmpty && !peakModifiers.isEmpty {
                // 全モディファイア解放 → モディファイアのみショートカットとしてキャプチャ
                let shortcut = PushToTalkShortcut(
                    modifierFlags: peakModifiers.rawValue,
                    keyCode: nil
                )
                peakModifiers = []
                stopMonitoring()
                DispatchQueue.main.async { [weak self] in
                    self?.onRecord?(shortcut)
                }
                return nil
            } else if !modifiers.isEmpty {
                // モディファイアが増えた場合のみピークを更新
                if modifiers.isSuperset(of: peakModifiers) || peakModifiers.isEmpty {
                    peakModifiers = modifiers
                }
                updateLabel(peakModifiers)
            }
        }

        return nil // レコーディング中は全イベントを消費
    }

    private func updateLabel(_ modifiers: NSEvent.ModifierFlags) {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        if modifiers.contains(.function) { parts.append("Fn") }
        label?.stringValue = parts.joined(separator: " + ") + " + ..."
    }

    private func stopMonitoring() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    override var acceptsFirstResponder: Bool { true }

    deinit {
        stopMonitoring()
    }
}

extension Notification.Name {
    static let updateHotkey = Notification.Name("updateHotkey")
    static let updateOverlayPosition = Notification.Name("updateOverlayPosition")
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

// MARK: - History Item Card

struct HistoryItemCard: View {
    let item: TranscriptionHistoryItem
    let onDelete: () -> Void
    let onCopy: () -> Void
    @State private var showCopiedFeedback = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // タイムスタンプとアクション
            HStack {
                Text(item.formattedTimestamp)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                // コピーボタン
                Button(action: {
                    onCopy()
                    showCopiedFeedback = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopiedFeedback = false
                    }
                }) {
                    Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                        .foregroundColor(showCopiedFeedback ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("コピー")

                // 削除ボタン
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("削除")
            }

            // テキスト本文
            Text(item.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }
}

// MARK: - TranscriptionHistoryItem Hashable

extension TranscriptionHistoryItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TranscriptionHistoryItem, rhs: TranscriptionHistoryItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Permission Row

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let onRequest: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(isGranted ? .green : .orange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, weight: .medium))

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isGranted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("許可済み")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            } else {
                Button("許可をリクエスト") {
                    onRequest()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
