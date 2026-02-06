import Foundation
import Carbon
import Cocoa

protocol HotkeyDelegate: AnyObject {
    func hotkeyTriggered()
    func recordingStarted()
    func recordingStopped()
}

class HotkeyManager {
    weak var delegate: HotkeyDelegate?
    private var eventHotKey: EventHotKeyRef?
    private var hotKeyID = EventHotKeyID()
    private var eventHandlerUPP: EventHandlerUPP?
    private static var sharedManager: HotkeyManager?
    
    // Push to Talk
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var isPushToTalkKeyPressed = false
    private var lastFlagsChangeTime: Date?
    private var safetyTimer: Timer?
    private var keyReleaseWorkItem: DispatchWorkItem?
    
    init(delegate: HotkeyDelegate) {
        self.delegate = delegate
        HotkeyManager.sharedManager = self
    }
    
    func registerHotkey() {
        // Push to Talkモードが有効な場合はNSEvent監視を使用
        if SettingsManager.shared.settings.pushToTalkMode {
            setupPushToTalkMonitoring()
        } else {
            // 従来のホットキーモード
            setupTraditionalHotkey()
        }
    }
    
    func unregisterHotkey() {
        // Carbonホットキーの解除
        if let hotKey = eventHotKey {
            UnregisterEventHotKey(hotKey)
            eventHotKey = nil
        }
        
        // NSEventモニタリングの解除
        removePushToTalkMonitoring()
    }
    
    func updateHotkey() {
        unregisterHotkey()
        registerHotkey()
    }
    
    // MARK: - Push to Talk
    
    private func setupPushToTalkMonitoring() {
        // グローバル監視（アプリが非アクティブ時）
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event, source: "global")
        }

        // ローカル監視（アプリがアクティブ時）
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event, source: "local")
            return event
        }

        // 安全タイマー: キーリリースイベントが失われた場合の保険
        // 0.5秒ごとに現在のモディファイアキー状態をチェック（より積極的に同期）
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkModifierKeysState()
        }
    }
    
    private func removePushToTalkMonitoring() {
        if let monitor = globalFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            globalFlagsMonitor = nil
        }
        if let monitor = localFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            localFlagsMonitor = nil
        }
        safetyTimer?.invalidate()
        safetyTimer = nil
        keyReleaseWorkItem?.cancel()
        keyReleaseWorkItem = nil
        isPushToTalkKeyPressed = false
    }
    
    private func handleFlagsChanged(_ event: NSEvent, source: String) {
        lastFlagsChangeTime = Date()

        let pushToTalkKeys = SettingsManager.shared.settings.pushToTalkKeys
        let targetFlags = pushToTalkKeys.combinedModifierFlags

        let currentFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // すべてのターゲットキーが押されているかチェック
        let isKeyPressed = targetFlags.isSubset(of: currentFlags)

        // 状態が変化した場合のみ処理
        if isKeyPressed != isPushToTalkKeyPressed {
            if isKeyPressed {
                // キーが押された - 即座に録音開始
                keyReleaseWorkItem?.cancel()
                keyReleaseWorkItem = nil
                isPushToTalkKeyPressed = true
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.recordingStarted()
                }
            } else {
                // キーが離された - デバウンス処理で確認後に録音停止
                // システムショートカットの一瞬の干渉を吸収
                keyReleaseWorkItem?.cancel()
                keyReleaseWorkItem = DispatchWorkItem { [weak self] in
                    self?.confirmAndStopRecording()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: keyReleaseWorkItem!)
            }
        }
    }

    /// キーリリースの確認と録音停止
    /// デバウンス後に実際のキー状態を再確認してから停止
    private func confirmAndStopRecording() {
        let currentFlags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let pushToTalkKeys = SettingsManager.shared.settings.pushToTalkKeys
        let targetFlags = pushToTalkKeys.combinedModifierFlags

        let isActuallyPressed = targetFlags.isSubset(of: currentFlags)

        // 実際にキーが離されている場合のみ停止
        if !isActuallyPressed && isPushToTalkKeyPressed {
            isPushToTalkKeyPressed = false
            delegate?.recordingStopped()
        }
    }

    /// 安全タイマーからの定期チェック
    /// キーリリースイベントが失われた場合のフェイルセーフ
    private func checkModifierKeysState() {
        guard isPushToTalkKeyPressed else { return }

        // 最後のフラグ変更から十分な時間が経過していない場合はスキップ
        // （イベントが正常に受信されている間は介入しない）
        // 0.2秒に短縮してより積極的にリカバリー
        if let lastChange = lastFlagsChangeTime,
           Date().timeIntervalSince(lastChange) < 0.2 {
            return
        }

        // 現在のモディファイアキー状態を直接取得
        // 注意: メインスレッドで取得することが重要
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isPushToTalkKeyPressed else { return }

            let currentFlags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let pushToTalkKeys = SettingsManager.shared.settings.pushToTalkKeys
            let targetFlags = pushToTalkKeys.combinedModifierFlags

            let isKeyPressed = targetFlags.isSubset(of: currentFlags)

            // キーが離されているのに、まだ録音中の場合は停止
            if !isKeyPressed && self.isPushToTalkKeyPressed {
                self.isPushToTalkKeyPressed = false
                self.delegate?.recordingStopped()
            }
        }
    }
    
    // MARK: - Traditional Hotkey
    
    private func setupTraditionalHotkey() {
        let settings = SettingsManager.shared.settings
        
        // イベントハンドラの設定
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)
        
        // コールバック関数
        eventHandlerUPP = { handlerCallRef, event, userData -> OSStatus in
            guard let manager = HotkeyManager.sharedManager else {
                return OSStatus(eventNotHandledErr)
            }
            
            var hotKeyID = EventHotKeyID()
            let error = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            
            if error == noErr && hotKeyID.id == 1 {
                DispatchQueue.main.async {
                    manager.delegate?.hotkeyTriggered()
                }
                return noErr
            }
            
            return OSStatus(eventNotHandledErr)
        }
        
        // イベントハンドラのインストール
        InstallEventHandler(
            GetApplicationEventTarget(),
            eventHandlerUPP,
            1,
            &eventType,
            nil,
            nil
        )
        
        // ホットキーの登録
        hotKeyID.signature = OSType(0x474D5350) // "GMSP"
        hotKeyID.id = 1
        
        let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(settings.hotkeyModifier))
        let carbonModifiers = carbonModifiersFromNSEvent(modifierFlags)
        
        RegisterEventHotKey(
            UInt32(settings.hotkeyKeyCode),
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &eventHotKey
        )
    }
    
    private func carbonModifiersFromNSEvent(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbonModifiers: UInt32 = 0
        
        if flags.contains(.command) {
            carbonModifiers |= UInt32(cmdKey)
        }
        if flags.contains(.option) {
            carbonModifiers |= UInt32(optionKey)
        }
        if flags.contains(.control) {
            carbonModifiers |= UInt32(controlKey)
        }
        if flags.contains(.shift) {
            carbonModifiers |= UInt32(shiftKey)
        }
        
        return carbonModifiers
    }
}

// MARK: - KeyCode Helper

struct KeyCodeHelper {
    static func keyCodeForString(_ string: String) -> Int {
        // 主要なキーコードのマッピング
        let keyMap: [String: Int] = [
            "F1": 122,
            "F2": 120,
            "F3": 99,
            "F4": 118,
            "F5": 96,
            "F6": 97,
            "F7": 98,
            "F8": 100,
            "F9": 101,
            "F10": 109,
            "F11": 103,
            "F12": 111,
            "Space": 49,
            "Return": 36,
            "Tab": 48,
            "Esc": 53
        ]
        return keyMap[string] ?? 99 // デフォルトはF3
    }
    
    static func stringForKeyCode(_ keyCode: Int) -> String {
        let keyMap: [Int: String] = [
            122: "F1",
            120: "F2",
            99: "F3",
            118: "F4",
            96: "F5",
            97: "F6",
            98: "F7",
            100: "F8",
            101: "F9",
            109: "F10",
            103: "F11",
            111: "F12",
            49: "Space",
            36: "Return",
            48: "Tab",
            53: "Esc"
        ]
        return keyMap[keyCode] ?? "F3"
    }
}
