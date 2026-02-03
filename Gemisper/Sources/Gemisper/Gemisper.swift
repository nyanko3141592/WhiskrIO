import SwiftUI

// MARK: - App Entry Point
// LSUIElementアプリではWindowGroupを使わず、AppDelegateで全てを管理する
// これにより無駄なウィンドウが表示されるのを防ぐ
class GemisperApplication: NSApplication {
    override init() {
        super.init()
        // アプリを非表示（ドックに表示しない）
        self.setActivationPolicy(.accessory)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
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
    
    static func main() {
        let app = GemisperApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 設定の読み込み
        SettingsManager.shared.loadSettings()
        
        // サービスの初期化
        geminiService = GeminiService()
        recordingManager = RecordingManager()
        
        // ステータスバーとホットキーのセットアップ
        statusBarController = StatusBarController()
        hotkeyManager = HotkeyManager(delegate: self)
        
        // オーバーレイウィンドウの作成
        overlayWindow = OverlayWindow()
        
        // ホットキーの登録
        hotkeyManager?.registerHotkey()
        
        // アプリを非表示（ドックに表示しない）
        NSApp.setActivationPolicy(.accessory)
        
        // 録音タイマー（メニューバー更新用）
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, let manager = self.recordingManager, manager.isRecording else { return }
            self.statusBarController?.updateRecordingDuration(manager.recordingDuration)
        }
        
        // 設定ウィンドウを開く通知を購読
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenSettings),
            name: .openSettings,
            object: nil
        )
    }
    
    @objc private func handleOpenSettings() {
        showSettingsWindow()
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
                window.title = "Gemisper 設定"
                window.contentView = NSHostingView(rootView: contentView)
                window.isReleasedWhenClosed = false
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
        // Push to Talk: キーが押された
        guard let recordingManager = recordingManager, !recordingManager.isRecording else { return }
        
        // APIキーが設定されているか確認
        guard !SettingsManager.shared.settings.apiKey.isEmpty else {
            showAPIKeyAlert()
            return
        }
        
        // マイク権限の確認
        RecordingManager.requestMicrophonePermission { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.recordingManager?.startRecording()
                    self?.overlayWindow?.show()
                    self?.statusBarController?.updateRecordingState(true)
                }
            }
        }
    }
    
    func recordingStopped() {
        // Push to Talk: キーが離された
        guard let recordingManager = recordingManager, recordingManager.isRecording else { return }
        
        stopRecording()
    }
    
    private func startRecording() {
        // APIキーが設定されているか確認
        guard !SettingsManager.shared.settings.apiKey.isEmpty else {
            showAPIKeyAlert()
            return
        }
        
        // マイク権限の確認
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
    
    private func transcribeAudio(url: URL) {
        overlayWindow?.showProcessing()
        
        Task {
            do {
                let text = try await geminiService?.transcribe(audioURL: url)
                
                DispatchQueue.main.async { [weak self] in
                    self?.overlayWindow?.hide()
                    
                    if let transcribedText = text, !transcribedText.isEmpty {
                        self?.insertText(transcribedText)
                    }
                }
            } catch let error as GeminiError {
                DispatchQueue.main.async { [weak self] in
                    self?.overlayWindow?.hide()
                    if case .noAPIKey = error {
                        self?.showAPIKeyAlert()
                    } else {
                        self?.showError(error)
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.overlayWindow?.hide()
                    self?.showError(error)
                }
            }
        }
    }
    
    private func insertText(_ text: String) {
        // 現在のアクティブアプリにテキストを入力
        TextInjector.shared.insertText(text)
    }
    
    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "マイクへのアクセスが必要です"
        alert.informativeText = "システム設定でマイクへのアクセスを許可してください。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "設定を開く")
        alert.addButton(withTitle: "キャンセル")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "エラーが発生しました"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func showAPIKeyAlert() {
        let alert = NSAlert()
        alert.messageText = "Gemini APIキーが必要です"
        alert.informativeText = "設定画面でGemini APIキーを入力してください。\n\nGoogle AI Studioで無料で取得できます。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "設定を開く")
        alert.addButton(withTitle: "後で")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            showSettingsWindow()
        }
    }
}
