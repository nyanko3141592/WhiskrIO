import Foundation
import ApplicationServices
import Cocoa

class TextInjector {
    static let shared = TextInjector()
    
    private init() {}
    
    /// 現在のアクティブなアプリケーションにテキストを入力
    func insertText(_ text: String) {
        // まずクリップボードにコピー
        let pasteboard = NSPasteboard.general
        let oldContent = pasteboard.string(forType: .string)
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // 方法1: Accessibility APIを使用して直接入力
        if !insertTextViaAccessibility(text) {
            // 方法2: キーイベントシミュレーション（Cmd+V）
            simulatePaste()
        }
        
        // 元のクリップボード内容を復元（少し遅延させる）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pasteboard.clearContents()
            if let oldContent = oldContent {
                pasteboard.setString(oldContent, forType: .string)
            }
        }
    }
    
    /// Accessibility APIを使用してテキストを挿入
    private func insertTextViaAccessibility(_ text: String) -> Bool {
        // 現在のフォーカスされたUI要素を取得
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        
        guard result == .success, let element = focusedElement else {
            return false
        }
        
        // テキスト値を設定
        let setResult = AXUIElementSetAttributeValue(
            element as! AXUIElement,
            kAXValueAttribute as CFString,
            text as CFTypeRef
        )
        
        return setResult == .success
    }
    
    /// Cmd+Vキーイベントをシミュレートしてペースト
    private func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        
        // Cmd+V ダウン
        let vKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        vKeyDown?.flags = .maskCommand
        
        // Cmd+V アップ
        let vKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vKeyUp?.flags = .maskCommand
        
        // イベント送信
        vKeyDown?.post(tap: .cghidEventTap)
        vKeyUp?.post(tap: .cghidEventTap)
    }
    
    /// キーストロークを個別にシミュレート（フォールバック用）
    func simulateTyping(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        
        for char in text {
            let keyCode = keyCodeForChar(char)
            
            // キーダウン
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
            keyDown?.post(tap: .cghidEventTap)
            
            // キーアップ
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
    
    /// 文字からキーコードを取得（簡易実装）
    private func keyCodeForChar(_ char: Character) -> CGKeyCode {
        // ASCII文字のキーコードマップ
        let keyMap: [Character: CGKeyCode] = [
            "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04,
            "g": 0x05, "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09,
            "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F,
            "y": 0x10, "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
            "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18, "9": 0x19,
            "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E,
            "o": 0x1F, "u": 0x20, "[": 0x21, "i": 0x22, "p": 0x23,
            "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
            "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E,
            ".": 0x2F, "`": 0x32, " ": 0x31, "\n": 0x24,
        ]
        
        return keyMap[char] ?? 0
    }
    
    /// 日本語テキストをNSEventで入力（より信頼性が高い）
    func insertTextViaNSEvent(_ text: String) {
        // 現在のフロントアプリを取得
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        
        // クリップボードを使用した貼り付けが最も信頼性が高い
        insertText(text)
    }
}

// MARK: - Alternative: Using AppleScript

class AppleScriptTextInjector {
    static func insertText(_ text: String) {
        let escapedText = text.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "System Events"
            keystroke "\(escapedText)"
        end tell
        """
        
        var errorInfo: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&errorInfo)
        }
    }
}
