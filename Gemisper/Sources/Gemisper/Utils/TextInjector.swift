import Foundation
import ApplicationServices
import Cocoa
import Carbon.HIToolbox

class TextInjector {
    static let shared = TextInjector()

    // Virtual key codes (amical準拠)
    private let VK_V: CGKeyCode = 9
    private let VK_COMMAND: CGKeyCode = 55

    // Clipboard restore delay - 長めに設定（ペーストが確実に完了するまで待つ）
    private let PASTE_RESTORE_DELAY_SECONDS: TimeInterval = 0.5

    // ペースト前の遅延（フォーカス復帰待ち）
    private let PRE_PASTE_DELAY_SECONDS: TimeInterval = 0.1

    // 録音開始前にフォーカスされていたアプリを記録
    private var previousApp: NSRunningApplication?

    private init() {}

    /// 録音開始前に呼び出し、現在のフロントアプリを記録
    func saveFocusedApp() {
        previousApp = NSWorkspace.shared.frontmostApplication
        if let app = previousApp {
            print("[TextInjector] Saved focused app: \(app.localizedName ?? "Unknown") (bundleId: \(app.bundleIdentifier ?? "unknown"))")
        }
    }

    /// 現在のアクティブなアプリケーションにテキストを入力
    func insertText(_ text: String) {
        print("[TextInjector] insertText called with text length: \(text.count)")

        // 保存したアプリにフォーカスを戻す
        if let app = previousApp {
            print("[TextInjector] Activating previous app: \(app.localizedName ?? "Unknown")")
            app.activate(options: [.activateIgnoringOtherApps])
        } else {
            print("[TextInjector] WARNING: No previous app saved!")
        }

        // フォーカスが戻るのを少し待ってからペースト
        DispatchQueue.main.asyncAfter(deadline: .now() + PRE_PASTE_DELAY_SECONDS) {
            self.performPaste(text)
        }
    }

    private func performPaste(_ text: String) {
        print("[TextInjector] performPaste called")

        let pasteboard = NSPasteboard.general

        // 元のクリップボード内容を保存（amicalと同じ方法）
        let originalItems = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let newItem = NSPasteboardItem()
            var hasData = false
            for type in item.types {
                if let data = item.data(forType: type) {
                    newItem.setData(data, forType: type)
                    hasData = true
                }
            }
            return hasData ? newItem : nil
        } ?? []
        let originalChangeCount = pasteboard.changeCount
        print("[TextInjector] Original pasteboard changeCount: \(originalChangeCount), items: \(originalItems.count)")

        // クリップボードにテキストを設定
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)

        if !success {
            print("[TextInjector] ERROR: Failed to set string on pasteboard")
            return
        }

        // 確認用ログ
        let verifyText = pasteboard.string(forType: .string)
        print("[TextInjector] Pasteboard set success. Verify: \(verifyText?.prefix(50) ?? "nil")...")
        print("[TextInjector] New changeCount: \(pasteboard.changeCount)")

        // 即座にペーストを実行
        simulatePaste()

        // 元のクリップボード内容を復元（デバッグ用に一時的に無効化）
        // ペースト問題のデバッグのため、復元をスキップ
        print("[TextInjector] Skipping pasteboard restore for debugging")
        // let capturedOriginalItems = originalItems
        // let capturedChangeCount = originalChangeCount
        // DispatchQueue.main.asyncAfter(deadline: .now() + PASTE_RESTORE_DELAY_SECONDS) {
        //     self.restorePasteboard(
        //         pasteboard: pasteboard,
        //         originalItems: capturedOriginalItems,
        //         originalChangeCount: capturedChangeCount
        //     )
        // }
    }

    /// Cmd+Vキーイベントをシミュレートしてペースト
    private func simulatePaste() {
        print("[TextInjector] simulatePaste called")

        // CGEventSource: .hidSystemState（amicalと同じ）
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            print("[TextInjector] ERROR: Failed to create CGEventSource")
            return
        }

        // イベント作成
        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: VK_COMMAND, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: VK_V, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: VK_V, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: VK_COMMAND, keyDown: false) else {
            print("[TextInjector] ERROR: Failed to create CGEvent")
            return
        }

        // フラグ設定（amicalと同じ）
        cmdDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        // cmdUpにはflagsを設定しない（amicalと同じ）

        // 重要: .cgSessionEventTap を使用（amicalと同じ）
        let tapLocation: CGEventTapLocation = .cgSessionEventTap

        // イベント送信
        print("[TextInjector] Posting keyboard events...")
        cmdDown.post(tap: tapLocation)
        vDown.post(tap: tapLocation)
        vUp.post(tap: tapLocation)
        cmdUp.post(tap: tapLocation)

        print("[TextInjector] Paste events posted successfully")
    }

    /// 元のクリップボード内容を復元（amicalと同じロジック）
    private func restorePasteboard(
        pasteboard: NSPasteboard,
        originalItems: [NSPasteboardItem],
        originalChangeCount: Int
    ) {
        let currentCount = pasteboard.changeCount
        print("[TextInjector] restorePasteboard: originalChangeCount=\(originalChangeCount), currentCount=\(currentCount)")

        // changeCountが1だけ増加している場合のみ復元
        guard currentCount == originalChangeCount + 1 else {
            print("[TextInjector] Pasteboard was modified externally (expected \(originalChangeCount + 1), got \(currentCount)), skipping restore")
            return
        }

        guard !originalItems.isEmpty else {
            print("[TextInjector] No original items to restore")
            return
        }

        pasteboard.clearContents()
        pasteboard.writeObjects(originalItems)
        print("[TextInjector] Original pasteboard content restored (\(originalItems.count) items)")
    }
}
