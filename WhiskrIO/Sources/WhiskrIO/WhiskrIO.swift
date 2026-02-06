import SwiftUI

// MARK: - App Entry Point
// LSUIElement app doesn't use WindowGroup, AppDelegate manages everything
// This prevents unnecessary windows from being displayed
class WhiskrIOApplication: NSApplication {
    override init() {
        super.init()
        // Hide app from dock
        self.setActivationPolicy(.accessory)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// 録音モード
enum RecordingMode {
    case normal           // 通常の音声入力モード
    case selectionEdit    // 選択テキスト編集モード
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    var hotkeyManager: HotkeyManager?
    var recordingManager: RecordingManager?
    var overlayWindow: OverlayWindow?
    var geminiService: GeminiService?
    private var recordingTimer: Timer?

    // Settings window
    private var settingsWindow: NSWindow?

    // 選択編集モード用
    private var selectedTextForEdit: String?
    private var currentRecordingMode: RecordingMode = .normal

    // スクリーンショット用
    private var capturedScreenshot: Data?

    // API処理タスク（キャンセル用）
    private var currentTranscriptionTask: Task<Void, Never>?
    
    static func main() {
        let app = WhiskrIOApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load settings
        SettingsManager.shared.loadSettings()

        // Load transcription history
        TranscriptionHistoryManager.shared.loadHistory()
        
        // Set initial app language
        LocalizationManager.shared.setLanguage(SettingsManager.shared.settings.appLanguage)
        
        // Initialize services
        geminiService = GeminiService()
        recordingManager = RecordingManager()
        
        // Setup status bar and hotkeys
        statusBarController = StatusBarController()
        hotkeyManager = HotkeyManager(delegate: self)
        
        // Create overlay window
        overlayWindow = OverlayWindow()
        overlayWindow?.recordingManagerRef = recordingManager
        
        // Register hotkey
        hotkeyManager?.registerHotkey()
        
        // Hide app from dock
        NSApp.setActivationPolicy(.accessory)
        
        // Recording timer (for menu bar updates)
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, let manager = self.recordingManager, manager.isRecording else { return }
            self.statusBarController?.updateRecordingDuration(manager.recordingDuration)
        }
        
        // Subscribe to open settings notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenSettings),
            name: .openSettings,
            object: nil
        )
        
        // Listen for language changes to update window title
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageChanged),
            name: .languageChanged,
            object: nil
        )

        // Listen for max recording duration reached
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMaxDurationReached),
            name: .recordingMaxDurationReached,
            object: nil
        )
    }

    @objc private func handleMaxDurationReached() {
        guard let recordingManager = recordingManager, recordingManager.isRecording else { return }
        stopRecording()
    }
    
    @objc private func handleOpenSettings() {
        showSettingsWindow()
    }
    
    @objc private func languageChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.settingsWindow?.title = L10n.Common.settings
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.unregisterHotkey()
        recordingTimer?.invalidate()
    }
    
    func showSettingsWindow() {
        DispatchQueue.main.async { [weak self] in
            if self?.settingsWindow == nil {
                let contentView = SettingsView()
                    .frame(minWidth: 500, minHeight: 400)
                
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                    styleMask: [.titled, .closable, .miniaturizable],
                    backing: .buffered,
                    defer: false
                )
                window.title = L10n.Common.settings
                window.contentView = NSHostingView(rootView: contentView)
                window.isReleasedWhenClosed = false
                window.toolbarStyle = .preference
                window.center()
                
                self?.settingsWindow = window
            }
            
            self?.settingsWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - HotkeyDelegate
extension AppDelegate: HotkeyDelegate {
    func hotkeyTriggered() {
        guard let recordingManager = recordingManager else { return }
        
        if recordingManager.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    func recordingStarted() {
        // Push to Talk: key pressed
        guard let recordingManager = recordingManager, !recordingManager.isRecording else { return }

        // Check if API key is set
        guard !SettingsManager.shared.settings.apiKey.isEmpty else {
            showAPIKeyAlert()
            return
        }

        // 前のAPI処理をキャンセル
        cancelCurrentTranscription()

        // 録音開始前に現在フォーカスされているアプリを保存
        TextInjector.shared.saveFocusedApp()

        // Check microphone permission
        RecordingManager.requestMicrophonePermission { [weak self] granted in
            guard granted else { return }

            // 選択テキストを取得（非同期）
            Task { @MainActor in
                if let selected = await TextInjector.shared.getSelectedText(), !selected.isEmpty {
                    self?.selectedTextForEdit = selected
                    self?.currentRecordingMode = .selectionEdit
                    self?.capturedScreenshot = nil  // 選択編集モードではスクリーンショット不要
                    print("[AppDelegate] Selection edit mode: \(selected.prefix(50))...")
                } else {
                    self?.selectedTextForEdit = nil
                    self?.currentRecordingMode = .normal

                    // 通常モードかつ設定が有効な場合、スクリーンショットを取得
                    let settings = SettingsManager.shared.settings
                    if settings.captureScreenshot {
                        self?.capturedScreenshot = ScreenshotManager.shared.captureAroundCursor(
                            size: settings.captureSize,
                            quality: 0.7
                        )
                        if self?.capturedScreenshot != nil {
                            print("[AppDelegate] Screenshot captured")
                        } else {
                            print("[AppDelegate] Screenshot capture failed or permission denied")
                        }
                    } else {
                        self?.capturedScreenshot = nil
                    }
                    print("[AppDelegate] Normal mode (no selection)")
                }

                // 録音開始
                self?.recordingManager?.startRecording()
                self?.overlayWindow?.show(mode: self?.currentRecordingMode ?? .normal)
                self?.statusBarController?.updateRecordingState(true)
            }
        }
    }
    
    func recordingStopped() {
        // Push to Talk: key released
        guard let recordingManager = recordingManager, recordingManager.isRecording else { return }
        
        stopRecording()
    }
    
    private func startRecording() {
        // Check if API key is set
        guard !SettingsManager.shared.settings.apiKey.isEmpty else {
            showAPIKeyAlert()
            return
        }

        // 前のAPI処理をキャンセル
        cancelCurrentTranscription()

        // 録音開始前に現在フォーカスされているアプリを保存
        TextInjector.shared.saveFocusedApp()

        // Check microphone permission
        RecordingManager.requestMicrophonePermission { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.recordingManager?.startRecording()
                    self?.overlayWindow?.show()
                    self?.statusBarController?.updateRecordingState(true)
                } else {
                    self?.showPermissionAlert()
                }
            }
        }
    }
    
    private func stopRecording() {
        recordingManager?.stopRecording { [weak self] audioURL in
            DispatchQueue.main.async {
                self?.overlayWindow?.hide()
                self?.statusBarController?.updateRecordingState(false)
                
                if let url = audioURL {
                    self?.transcribeAudio(url: url)
                }
            }
        }
    }
    
    private func cancelCurrentTranscription() {
        if let task = currentTranscriptionTask {
            print("[AppDelegate] Cancelling previous transcription task")
            task.cancel()
            currentTranscriptionTask = nil
            overlayWindow?.hide()
        }
    }

    private func transcribeAudio(url: URL) {
        overlayWindow?.showProcessing()

        // 選択編集モードかどうかをキャプチャ
        let selectedText = self.selectedTextForEdit
        let mode = self.currentRecordingMode
        let screenshot = self.capturedScreenshot

        // 状態をリセット（次回の録音に備える）
        self.selectedTextForEdit = nil
        self.currentRecordingMode = .normal
        self.capturedScreenshot = nil

        // 新しいタスクを作成して保存
        currentTranscriptionTask = Task { [weak self] in
            do {
                guard let service = self?.geminiService else { return }

                // キャンセルチェック
                try Task.checkCancellation()

                let finalText: String

                if mode == .selectionEdit, let selected = selectedText {
                    // 選択編集モード: 音声を指示として解釈し、選択テキストを編集
                    print("[AppDelegate] Selection edit mode - processing...")

                    // 音声を指示として文字起こし
                    let instruction = try await service.transcribeInstruction(audioURL: url)

                    // キャンセルチェック
                    try Task.checkCancellation()

                    print("[AppDelegate] Instruction: \(instruction)")

                    // ルールエンジンでチェック（「英語」「ビジネスメール」などルール名だけ言った場合に対応）
                    let ruleResult = RuleEngine.shared.process(text: instruction)

                    if !ruleResult.isDefault {
                        // ルールにマッチ → 選択テキストにルールを適用
                        print("[AppDelegate] Rule matched: \(ruleResult.matchedRule?.name ?? "unknown")")
                        finalText = try await service.processSelectionWithRule(
                            selectedText: selected,
                            ruleResult: ruleResult
                        )
                    } else {
                        // ルールにマッチしない → 従来の自由形式指示として処理
                        finalText = try await service.processSelectionEdit(
                            selectedText: selected,
                            instruction: instruction
                        )
                    }

                    // キャンセルチェック
                    try Task.checkCancellation()

                    print("[AppDelegate] Edited result: \(finalText.prefix(50))...")
                } else {
                    // 通常モード: スクリーンショット付きで文字起こし
                    let transcribedText = try await service.transcribe(audioURL: url, screenshotData: screenshot)

                    // キャンセルチェック
                    try Task.checkCancellation()

                    // コマンドモードを検出
                    let (isCommand, cleanedText) = service.detectCommandMode(transcribedText: transcribedText)

                    if isCommand {
                        // コマンドモード: zshコマンドを生成
                        DispatchQueue.main.async { [weak self] in
                            self?.overlayWindow?.showProcessing()
                        }
                        finalText = try await service.generateZshCommand(instruction: cleanedText)

                        // キャンセルチェック
                        try Task.checkCancellation()
                    } else {
                        // 通常モード: そのまま出力
                        finalText = transcribedText
                    }
                }

                // 最終キャンセルチェック
                try Task.checkCancellation()

                DispatchQueue.main.async { [weak self] in
                    self?.currentTranscriptionTask = nil
                    self?.overlayWindow?.hide()

                    if !finalText.isEmpty {
                        self?.insertText(finalText)
                    }
                }
            } catch is CancellationError {
                print("[AppDelegate] Transcription task was cancelled")
                // キャンセルされた場合は何もしない
            } catch let error as GeminiError {
                DispatchQueue.main.async { [weak self] in
                    self?.currentTranscriptionTask = nil
                    self?.overlayWindow?.hide()
                    if case .noAPIKey = error {
                        self?.showAPIKeyAlert()
                    } else {
                        self?.showError(error)
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.currentTranscriptionTask = nil
                    self?.overlayWindow?.hide()
                    self?.showError(error)
                }
            }
        }
    }
    
    private func insertText(_ text: String) {
        // Insert text into current active app
        TextInjector.shared.insertText(text)
    }
    
    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = L10n.Alert.microphoneAccessRequired
        alert.informativeText = L10n.Alert.microphoneAccessMessage
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.Alert.openSettings)
        alert.addButton(withTitle: L10n.Common.cancel)
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L10n.Alert.errorOccurred
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.addButton(withTitle: L10n.Common.ok)
        alert.runModal()
    }
    
    private func showAPIKeyAlert() {
        let alert = NSAlert()
        alert.messageText = L10n.Alert.apiKeyRequired
        alert.informativeText = L10n.Alert.apiKeyRequiredMessage + "\n\n" + L10n.Alert.apiKeyRequiredDetail
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.Alert.openSettings)
        alert.addButton(withTitle: L10n.Alert.later)
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            showSettingsWindow()
        }
    }
}
