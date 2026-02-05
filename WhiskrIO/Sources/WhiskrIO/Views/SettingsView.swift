import SwiftUI

struct SettingsView: View {
    @StateObject private var settingsManager = SettingsManager.shared
    @StateObject private var historyManager = TranscriptionHistoryManager.shared
    @State private var isValidatingKey = false
    @State private var keyStatus: KeyStatus = .unknown
    
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
            VStack(alignment: .leading, spacing: 20) {
                // Gemini API
                VStack(alignment: .leading, spacing: 12) {
                    Text("Gemini API")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
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
                        
                        Text("Gemini APIキーは [Google AI Studio](https://aistudio.google.com/app/apikey) から取得できます。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                    .padding(.leading, 4)
                }
                
                Divider()
                
                // モデル設定
                VStack(alignment: .leading, spacing: 12) {
                    Text("モデル設定")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 8) {
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
                    .padding(.leading, 4)
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
    }
    
    // MARK: - Input Settings (Hotkey + Push to Talk)

    private var inputSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 録音時間の上限
                VStack(alignment: .leading, spacing: 12) {
                    Text("録音時間の上限")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Picker("上限", selection: $settingsManager.settings.maxRecordingDuration) {
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
                        }

                        Text("設定した時間に達すると自動的に録音が停止します")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 4)
                }

                Divider()

                // 入力モード
                VStack(alignment: .leading, spacing: 12) {
                    Text("入力モード")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
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
                    .padding(.leading, 4)
                }
                
                if settingsManager.settings.pushToTalkMode {
                    Divider()
                    
                    // Push to Talk キー
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Push to Talk キー（複数選択可）")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
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
                        .padding(.leading, 4)
                    }
                } else {
                    Divider()
                    
                    // トグルホットキー
                    VStack(alignment: .leading, spacing: 12) {
                        Text("トグルホットキー")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
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
                        .padding(.leading, 4)
                    }
                    
                    Divider()
                    
                    // プリセット
                    VStack(alignment: .leading, spacing: 12) {
                        Text("プリセット")
                            .font(.headline)
                        
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
                        .padding(.leading, 4)
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            VStack(alignment: .leading, spacing: 20) {
                // 文字起こしプロンプト
                VStack(alignment: .leading, spacing: 12) {
                    Text("文字起こしプロンプト")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("音声を文字起こしする際にGeminiに送信するプロンプトです")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextEditor(text: Binding(
                            get: {
                                settingsManager.settings.customPrompt ?? GeminiService.defaultTranscriptionPrompt
                            },
                            set: { newValue in
                                // デフォルトと同じ場合はnilに
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
                    .padding(.leading, 4)
                }

                Divider()

                // デバッグ
                VStack(alignment: .leading, spacing: 12) {
                    Text("デバッグ")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("ログを有効化", isOn: .constant(false))
                            .disabled(true)

                        Button("キャッシュをクリア") {
                            clearCache()
                        }
                    }
                    .padding(.leading, 4)
                }

                Divider()

                // アプリ情報
                VStack(alignment: .leading, spacing: 12) {
                    Text("アプリ情報")
                        .font(.headline)

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
                    }
                    .padding(.leading, 4)
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
    
    private func clearCache() {
        let tempDir = FileManager.default.temporaryDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix("recording_") {
                try? FileManager.default.removeItem(at: file)
            }
        }
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
