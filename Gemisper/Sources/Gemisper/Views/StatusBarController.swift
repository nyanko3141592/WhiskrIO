import SwiftUI
import AppKit

class StatusBarController {
    private var statusItem: NSStatusItem
    private var menu: NSMenu
    private var recordingView: MenuBarRecordingView?
    
    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        
        setupStatusBar()
        setupMenu()
    }
    
    private func setupStatusBar() {
        guard let button = statusItem.button else {
            print("Failed to create status bar button")
            return
        }
        
        // Use system symbol or fallback to text
        if let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Gemisper") {
            button.image = image
            button.imagePosition = .imageLeft
        } else {
            button.title = "🎙️"
        }
        
        button.action = #selector(toggleMenu)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        
        statusItem.menu = menu
    }
    
    private func setupMenu() {
        // 録音開始（モードに応じて表示変更）
        let settings = SettingsManager.shared.settings
        let toggleTitle = settings.pushToTalkMode 
            ? "Push to Talk (\(settings.pushToTalkKeys.combinedDisplayName))"
            : "録音開始 (⌘⇧F3)"
        let toggleItem = NSMenuItem(
            title: toggleTitle,
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 設定
        let settingsItem = NSMenuItem(
            title: "設定...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        // カスタム辞書
        let dictionaryItem = NSMenuItem(
            title: "カスタム辞書...",
            action: #selector(openDictionary),
            keyEquivalent: ""
        )
        dictionaryItem.target = self
        menu.addItem(dictionaryItem)
        
        // スニペット
        let snippetsItem = NSMenuItem(
            title: "スニペット...",
            action: #selector(openSnippets),
            keyEquivalent: ""
        )
        snippetsItem.target = self
        menu.addItem(snippetsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 使用量セクション
        setupUsageMenu()
        
        menu.addItem(NSMenuItem.separator())
        
        // バージョン情報
        let versionItem = NSMenuItem(
            title: "Gemisper v1.0.0",
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        
        // 終了
        let quitItem = NSMenuItem(
            title: "Gemisperを終了",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    private func setupUsageMenu() {
        print("[DEBUG] StatusBarController.setupUsageMenu() called")
        // ヘッダー
        let usageHeaderItem = NSMenuItem(
            title: "使用量",
            action: nil,
            keyEquivalent: ""
        )
        usageHeaderItem.isEnabled = false
        menu.addItem(usageHeaderItem)
        
        // 直近のリクエスト
        let recentUsages = SettingsManager.shared.getRecentUsage(limit: 1)
        print("[DEBUG] StatusBarController: recentUsages.count = \(recentUsages.count)")
        if let recent = recentUsages.first {
            let recentItem = NSMenuItem(
                title: "  直近: \(recent.totalTokens.formatted()) tokens",
                action: nil,
                keyEquivalent: ""
            )
            recentItem.isEnabled = false
            menu.addItem(recentItem)
            
            // 概算金額
            let costUSD = recent.estimatedCostUSD
            let costJPY = costUSD * 150  // 概算レート
            let costItem = NSMenuItem(
                title: String(format: "  概算: $%.4f (¥%.2f)", costUSD, costJPY),
                action: nil,
                keyEquivalent: ""
            )
            costItem.isEnabled = false
            menu.addItem(costItem)
        } else {
            let noDataItem = NSMenuItem(
                title: "  直近: データなし",
                action: nil,
                keyEquivalent: ""
            )
            noDataItem.isEnabled = false
            menu.addItem(noDataItem)
        }
        
        // 今日の累計
        let todayUsage = SettingsManager.shared.getTodayUsage()
        let todayTotalTokens = todayUsage.tokens
        let todayCostJPY = todayUsage.costJPY
        
        let todayItem = NSMenuItem(
            title: "  今日の累計: \(todayTotalTokens.formatted()) tokens",
            action: nil,
            keyEquivalent: ""
        )
        todayItem.isEnabled = false
        menu.addItem(todayItem)
        
        let todayCostItem = NSMenuItem(
            title: String(format: "  今日の概算: $%.4f (¥%.2f)", todayUsage.costUSD, todayCostJPY),
            action: nil,
            keyEquivalent: ""
        )
        todayCostItem.isEnabled = false
        menu.addItem(todayCostItem)
        
        // 今月の累計
        let monthlyUsage = SettingsManager.shared.getCurrentMonthUsage()
        let monthCostJPY = monthlyUsage.costJPY
        
        let monthItem = NSMenuItem(
            title: "  今月の累計: \(monthlyUsage.tokens.formatted()) tokens",
            action: nil,
            keyEquivalent: ""
        )
        monthItem.isEnabled = false
        menu.addItem(monthItem)
        
        let monthCostItem = NSMenuItem(
            title: String(format: "  今月の概算: $%.4f (¥%.2f)", monthlyUsage.costUSD, monthCostJPY),
            action: nil,
            keyEquivalent: ""
        )
        monthCostItem.isEnabled = false
        menu.addItem(monthCostItem)
    }
    
    func updateRecordingState(_ isRecording: Bool, duration: TimeInterval = 0) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let button = self.statusItem.button else { return }
            
            if isRecording {
                // Show recording view in menu bar
                button.image = nil
                button.title = "● \(String(format: "%02d:%02d", Int(duration) / 60, Int(duration) % 60))"
                button.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
                button.contentTintColor = .red
            } else {
                // Back to normal
                button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Gemisper")
                button.title = ""
                button.contentTintColor = nil
            }
        }
    }
    
    func updateRecordingDuration(_ duration: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let button = self.statusItem.button else { return }
            if self.recordingView != nil {
                button.title = "● \(String(format: "%02d:%02d", Int(duration) / 60, Int(duration) % 60))"
            }
        }
    }
    
    @objc private func toggleMenu(_ sender: NSStatusBarButton) {
        print("[DEBUG] StatusBarController.toggleMenu() called")
        guard let event = NSApp.currentEvent else { return }
        
        // Show menu on both left and right click
        if event.type == .leftMouseUp || event.type == .rightMouseUp {
            // メニューを最新の使用量データで更新
            updateUsageMenu()
            statusItem.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }
    
    private func updateUsageMenu() {
        print("[DEBUG] StatusBarController.updateUsageMenu() called")
        // メニューアイテムを再構築して最新データを反映
        menu.removeAllItems()
        setupMenu()
    }
    
    @objc private func toggleRecording() {
        NotificationCenter.default.post(name: .toggleRecording, object: nil)
    }
    
    @objc private func openSettings() {
        // AppDelegateに通知して設定ウィンドウを開く
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }
    
    @objc private func openDictionary() {
        DispatchQueue.main.async {
            DictionaryWindowController.shared.showWindow()
        }
    }
    
    @objc private func openSnippets() {
        DispatchQueue.main.async {
            SnippetsWindowController.shared.showWindow()
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

extension Notification.Name {
    static let toggleRecording = Notification.Name("toggleRecording")
    static let openSettings = Notification.Name("openSettings")
}
