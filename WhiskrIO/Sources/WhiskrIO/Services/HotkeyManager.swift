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
    private static var sharedManager: HotkeyManager?

    // CGEventTap
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Push to Talk 状態管理
    private var isPushToTalkKeyPressed = false
    private var recordingStartTime: Date?
    private var isWaitingForRecordingStart = false
    private var keyReleaseWorkItem: DispatchWorkItem?
    private var safetyTimer: Timer?

    // トグルモード: keyDownリピート抑止
    private var lastToggleTime: Date?

    init(delegate: HotkeyDelegate) {
        self.delegate = delegate
        HotkeyManager.sharedManager = self
    }

    // MARK: - Public

    func registerHotkey() {
        setupEventTap()
    }

    func unregisterHotkey() {
        removeEventTap()
        safetyTimer?.invalidate()
        safetyTimer = nil
        keyReleaseWorkItem?.cancel()
        keyReleaseWorkItem = nil
        isPushToTalkKeyPressed = false
        isWaitingForRecordingStart = false
        recordingStartTime = nil
        lastToggleTime = nil
    }

    func updateHotkey() {
        unregisterHotkey()
        registerHotkey()
    }

    /// 録音が実際に開始されたことを通知（AppDelegateから呼び出す）
    func notifyRecordingActuallyStarted() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isWaitingForRecordingStart = false
            self.recordingStartTime = Date()
            print("[HotkeyManager] Recording actually started")
        }
    }

    // MARK: - CGEventTap

    private func setupEventTap() {
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[HotkeyManager] ERROR: Failed to create CGEventTap. Check Accessibility permissions.")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // 安全タイマー: キーリリースイベントが失われた場合のフェイルセーフ
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.checkKeyState()
        }

        print("[HotkeyManager] CGEventTap registered successfully")
    }

    private func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            // Note: CFMachPort is managed by ARC via the reference
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Event Handling

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // タップが無効化された場合は再有効化
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        let settings = SettingsManager.shared.settings
        let shortcut = settings.pushToTalkShortcut
        let isPushToTalk = settings.pushToTalkMode

        let flags = CGEventFlags(rawValue: event.flags.rawValue & CGEventFlags.maskNonCoalesced.rawValue.byteSwapped == 0
            ? event.flags.rawValue : event.flags.rawValue)
        let nsFlags = nsModifierFlags(from: event.flags)
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        if let kc = shortcut.keyCode {
            // キーコードありのショートカット（例: Ctrl+Space, F13）
            return handleKeyCodeShortcut(
                type: type, keyCode: keyCode, nsFlags: nsFlags,
                targetKeyCode: kc, targetFlags: NSEvent.ModifierFlags(rawValue: shortcut.modifierFlags),
                isPushToTalk: isPushToTalk, event: event
            )
        } else {
            // モディファイアのみのショートカット（例: ⌥⌘）
            return handleModifierOnlyShortcut(
                type: type, nsFlags: nsFlags,
                targetFlags: NSEvent.ModifierFlags(rawValue: shortcut.modifierFlags),
                isPushToTalk: isPushToTalk, event: event
            )
        }
    }

    /// キーコード付きショートカット（Ctrl+Space, F13等）
    private func handleKeyCodeShortcut(
        type: CGEventType,
        keyCode: UInt16,
        nsFlags: NSEvent.ModifierFlags,
        targetKeyCode: UInt16,
        targetFlags: NSEvent.ModifierFlags,
        isPushToTalk: Bool,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // キーコードが一致し、必要なモディファイアが押されているか
        guard keyCode == targetKeyCode else {
            return Unmanaged.passRetained(event)
        }

        let modifiersMatch = targetFlags.rawValue == 0 || targetFlags.isSubset(of: nsFlags)
        guard modifiersMatch else {
            return Unmanaged.passRetained(event)
        }

        if isPushToTalk {
            if type == .keyDown {
                if !isPushToTalkKeyPressed {
                    startPushToTalk()
                }
                // キーイベントを消費（他アプリに伝搬しない）
                return nil
            } else if type == .keyUp {
                stopPushToTalk()
                return nil
            }
        } else {
            // トグルモード
            if type == .keyDown {
                // リピート防止
                if let last = lastToggleTime, Date().timeIntervalSince(last) < 0.3 {
                    return nil
                }
                lastToggleTime = Date()
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.hotkeyTriggered()
                }
                return nil
            } else if type == .keyUp {
                return nil
            }
        }

        return Unmanaged.passRetained(event)
    }

    /// モディファイアのみのショートカット（⌥⌘等）
    private func handleModifierOnlyShortcut(
        type: CGEventType,
        nsFlags: NSEvent.ModifierFlags,
        targetFlags: NSEvent.ModifierFlags,
        isPushToTalk: Bool,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        guard type == .flagsChanged else {
            return Unmanaged.passRetained(event)
        }

        let isPressed = targetFlags.isSubset(of: nsFlags)

        if isPushToTalk {
            if isPressed && !isPushToTalkKeyPressed {
                startPushToTalk()
            } else if !isPressed && isPushToTalkKeyPressed {
                stopPushToTalk()
            }
        } else {
            // トグルモード: 全キーが揃った瞬間にトグル
            if isPressed {
                if let last = lastToggleTime, Date().timeIntervalSince(last) < 0.3 {
                    return Unmanaged.passRetained(event)
                }
                lastToggleTime = Date()
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.hotkeyTriggered()
                }
            }
        }

        // flagsChangedイベントは消費しない（他アプリのモディファイア処理に影響するため）
        return Unmanaged.passRetained(event)
    }

    // MARK: - Push to Talk Control

    private func startPushToTalk() {
        keyReleaseWorkItem?.cancel()
        keyReleaseWorkItem = nil
        isPushToTalkKeyPressed = true
        isWaitingForRecordingStart = true
        recordingStartTime = nil
        print("[HotkeyManager] -> Recording START requested")
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.recordingStarted()
        }
    }

    private func stopPushToTalk() {
        // 録音開始待ち中は無視
        if isWaitingForRecordingStart {
            print("[HotkeyManager] -> Stop IGNORED (waiting for recording start)")
            return
        }

        // 最低0.5秒経過チェック
        let minDuration: TimeInterval = 0.5
        if let startTime = recordingStartTime,
           Date().timeIntervalSince(startTime) < minDuration {
            print("[HotkeyManager] -> Stop IGNORED (too soon)")
            return
        }

        // デバウンス0.2秒
        print("[HotkeyManager] -> Scheduling stop (debounce 0.2s)")
        keyReleaseWorkItem?.cancel()
        keyReleaseWorkItem = DispatchWorkItem { [weak self] in
            self?.confirmAndStop()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: keyReleaseWorkItem!)
    }

    private func confirmAndStop() {
        if isWaitingForRecordingStart { return }

        // キーコード付きの場合はデバウンス時点で確定（keyUpが来た時点で離されている）
        // モディファイアのみの場合は現在のフラグを再チェック
        let settings = SettingsManager.shared.settings
        let shortcut = settings.pushToTalkShortcut

        if shortcut.keyCode == nil {
            // モディファイアのみ: 現在の状態を再確認
            let currentFlags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let targetFlags = NSEvent.ModifierFlags(rawValue: shortcut.modifierFlags)
            if targetFlags.isSubset(of: currentFlags) {
                print("[HotkeyManager] -> Stop CANCELLED (key still pressed)")
                return
            }
        }

        guard isPushToTalkKeyPressed else { return }
        isPushToTalkKeyPressed = false
        isWaitingForRecordingStart = false
        recordingStartTime = nil
        print("[HotkeyManager] -> Recording STOPPED (confirmed)")
        delegate?.recordingStopped()
    }

    /// 安全タイマー: キーリリースイベントが失われた場合のフェイルセーフ
    private func checkKeyState() {
        guard isPushToTalkKeyPressed, !isWaitingForRecordingStart else { return }

        if let startTime = recordingStartTime,
           Date().timeIntervalSince(startTime) < 0.5 { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isPushToTalkKeyPressed else { return }

            let settings = SettingsManager.shared.settings
            let shortcut = settings.pushToTalkShortcut
            let targetFlags = NSEvent.ModifierFlags(rawValue: shortcut.modifierFlags)

            // モディファイアの状態をチェック
            let currentFlags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)

            let shouldStop: Bool
            if shortcut.keyCode != nil {
                // キーコード付き: モディファイアが外れていれば停止
                // (keyUpイベントが失われた場合のフォールバック)
                shouldStop = targetFlags.rawValue != 0 && !targetFlags.isSubset(of: currentFlags)
            } else {
                // モディファイアのみ: 全て離されていれば停止
                shouldStop = !targetFlags.isSubset(of: currentFlags)
            }

            if shouldStop {
                self.isPushToTalkKeyPressed = false
                self.recordingStartTime = nil
                print("[HotkeyManager] -> Recording STOPPED (safety timer)")
                self.delegate?.recordingStopped()
            }
        }
    }

    // MARK: - Helpers

    /// CGEventFlagsをNSEvent.ModifierFlagsに変換
    private func nsModifierFlags(from cgFlags: CGEventFlags) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if cgFlags.contains(.maskCommand) { flags.insert(.command) }
        if cgFlags.contains(.maskAlternate) { flags.insert(.option) }
        if cgFlags.contains(.maskShift) { flags.insert(.shift) }
        if cgFlags.contains(.maskControl) { flags.insert(.control) }
        if cgFlags.contains(.maskSecondaryFn) { flags.insert(.function) }
        return flags
    }
}

// MARK: - KeyCode Helper

struct KeyCodeHelper {
    static func keyCodeForString(_ string: String) -> Int {
        let keyMap: [String: Int] = [
            "F1": 122, "F2": 120, "F3": 99, "F4": 118,
            "F5": 96, "F6": 97, "F7": 98, "F8": 100,
            "F9": 101, "F10": 109, "F11": 103, "F12": 111,
            "Space": 49, "Return": 36, "Tab": 48, "Esc": 53
        ]
        return keyMap[string] ?? 99
    }

    static func stringForKeyCode(_ keyCode: Int) -> String {
        let keyMap: [Int: String] = [
            122: "F1", 120: "F2", 99: "F3", 118: "F4",
            96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
            49: "Space", 36: "Return", 48: "Tab", 53: "Esc"
        ]
        return keyMap[keyCode] ?? "F3"
    }
}
