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
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var flagsChangedMonitor: Any?
    private var isPushToTalkKeyPressed = false
    
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
        // キーダウン監視
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        
        // キーアップ監視（ローカルイベントも必要）
        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }
    
    private func removePushToTalkMonitoring() {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
        if let monitor = flagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
            flagsChangedMonitor = nil
        }
    }
    
    private func handleFlagsChanged(_ event: NSEvent) {
        let pushToTalkKeys = SettingsManager.shared.settings.pushToTalkKeys
        let targetFlags = pushToTalkKeys.combinedModifierFlags
        
        let currentFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        // すべてのターゲットキーが押されているかチェック
        let isKeyPressed = targetFlags.isSubset(of: currentFlags)
        
        // 状態が変化した場合のみ処理
        if isKeyPressed != isPushToTalkKeyPressed {
            isPushToTalkKeyPressed = isKeyPressed
            
            if isKeyPressed {
                // キーが押された - 録音開始
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.recordingStarted()
                }
            } else {
                // キーが離された - 録音停止
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.recordingStopped()
                }
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
