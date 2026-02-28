import SwiftUI
import AppKit

// MARK: - WhiskrIO Brand Color

extension NSColor {
    /// WhiskrIO 猫モードカラー（オレンジ）
    static let whiskrAccent = NSColor(red: 255/255, green: 165/255, blue: 0/255, alpha: 1.0)
    /// 猫顔の色（シアン #2CD8F6）
    static let catFaceColor = NSColor(red: 0x2C/255, green: 0xD8/255, blue: 0xF6/255, alpha: 1.0)
    /// 猫鼻の色（ピンク #EA808C）
    static let catNoseColor = NSColor(red: 0xEA/255, green: 0x80/255, blue: 0x8C/255, alpha: 1.0)
}

extension Color {
    /// WhiskrIO 猫モードカラー（オレンジ）
    static let whiskrAccent = Color(red: 255/255, green: 165/255, blue: 0/255)
    /// 猫顔の色（シアン #2CD8F6）
    static let catFaceColor = Color(red: 0x2C/255, green: 0xD8/255, blue: 0xF6/255)
}

// MARK: - Modern Recording Indicator

class OverlayWindow: NSWindow {
    private var containerView: NSView?
    private var catFaceView: CatFaceView?
    private var idleCatView: IdleCatView?
    weak var recordingManagerRef: RecordingManager?
    private var updateTimer: Timer?
    private let silenceThreshold: Float = -45.0
    private let maxLevel: Float = -15.0
    private var debugLogCounter: Int = 0
    private var currentMode: RecordingMode = .normal
    private var isIdle: Bool = true

    // マウスアップ検出用モニター
    private var mouseUpMonitor: Any?
    private var isRecordingFromClick: Bool = false

    // リアルタイムテキスト表示用
    private var transcriptWindow: NSWindow?
    private var transcriptTextField: NSTextField?

    // ミニダッシュボード（ホバー時表示）
    private var dashboardWindow: NSWindow?
    private var dashboardShowTimer: Timer?
    private var dashboardHideTimer: Timer?
    private var statusDotView: NSView?
    private var statusLabel: NSTextField?
    private var transcriptionPreviewLabel: NSTextField?
    private var timestampLabel: NSTextField?
    private var usageLabel: NSTextField?

    // マルチモニター追従用
    private var screenTrackingTimer: Timer?
    private var lastScreenFrame: NSRect = .zero

    // サイズ定数（SVG比率 1005:757 ≈ 1.33:1 + ジャンプ余白）
    private let idleWidth: CGFloat = 50
    private let idleHeight: CGFloat = 42  // 上に余白を確保
    private let recordingWidth: CGFloat = 120
    private let recordingHeight: CGFloat = 30

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 50, height: 42),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.ignoresMouseEvents = false  // マウスイベントを受け付ける
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        setupIdleUI()
    }

    /// クリックによる録音開始時にグローバルマウスモニターを設定
    func startMouseUpMonitoring() {
        isRecordingFromClick = true
        // 既存のモニターを解除
        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
        }
        // グローバルマウスアップモニターを設定
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.handleGlobalMouseUp()
        }
    }

    private func handleGlobalMouseUp() {
        guard isRecordingFromClick else { return }
        isRecordingFromClick = false

        // モニター解除
        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            mouseUpMonitor = nil
        }

        // 録音停止通知
        NotificationCenter.default.post(name: .recordingStoppedFromOverlay, object: nil)
    }

    /// モニター解除（クリーンアップ用）
    func stopMouseUpMonitoring() {
        isRecordingFromClick = false
        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            mouseUpMonitor = nil
        }
    }

    private func setupIdleUI() {
        // アイドル用のミニキャラクター
        let catView = IdleCatView(frame: NSRect(x: 0, y: 0, width: idleWidth, height: idleHeight))
        idleCatView = catView
        self.contentView = catView
        self.setContentSize(NSSize(width: idleWidth, height: idleHeight))
    }

    private func setupRecordingUI() {
        // Container with cyan background
        let container = NSView(frame: NSRect(x: 0, y: 0, width: recordingWidth, height: recordingHeight))
        container.wantsLayer = true
        container.layer?.cornerRadius = 15
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor.catFaceColor.cgColor
        containerView = container

        // Cat face view (mouth + whiskers)
        let catFace = CatFaceView(frame: NSRect(x: 0, y: 0, width: recordingWidth, height: recordingHeight))
        catFaceView = catFace
        container.addSubview(catFace)

        self.contentView = container
        self.setContentSize(NSSize(width: recordingWidth, height: recordingHeight))
    }

    /// アイドル状態を表示（常駐ミニキャラクター）
    func showIdle() {
        isIdle = true
        updateTimer?.invalidate()
        updateTimer = nil

        // ダッシュボードを非表示
        hideDashboardImmediately()

        // マウスモニター解除
        stopMouseUpMonitoring()

        // アイドルUIに切り替え（アニメーション停止）
        setupIdleUI()
        idleCatView?.stopBouncing()
        self.ignoresMouseEvents = false

        // 設定に応じた位置に配置
        let size = NSSize(width: idleWidth, height: idleHeight)
        let position = calculatePosition(for: size)
        self.setFrame(NSRect(origin: position, size: size), display: true)

        self.orderFrontRegardless()

        // マルチモニター追従を開始
        startScreenTracking()
    }

    func show(mode: RecordingMode = .normal) {
        let shouldShow = SettingsManager.shared.settings.showOverlay
        guard shouldShow else { return }

        isIdle = false
        currentMode = mode

        // ダッシュボードを即座に非表示
        hideDashboardImmediately()

        // クリック録音でない場合（キーボードPush to Talk）はモニター解除
        // クリック録音の場合は startMouseUpMonitoring() で設定済み
        if !isRecordingFromClick {
            stopMouseUpMonitoring()
        }

        // 録音UIに切り替え
        setupRecordingUI()
        catFaceView?.reset()
        updateModeColor(for: mode)
        self.ignoresMouseEvents = true  // 録音中はマウスイベント無視

        // 設定に応じた位置に配置
        let size = NSSize(width: recordingWidth, height: recordingHeight)
        let position = calculatePosition(for: size)
        self.setFrame(NSRect(origin: position, size: size), display: true)

        self.orderFrontRegardless()

        // Start waveform animation
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            self?.updateWaveform()
        }
    }

    private func updateModeColor(for mode: RecordingMode) {
        switch mode {
        case .normal:
            catFaceView?.mouthColor = .whiskrAccent
        case .selectionEdit:
            catFaceView?.mouthColor = .systemBlue
        }
    }

    /// マウスカーソルがあるスクリーンを取得（マルチモニター対応）
    private func screenForMouseCursor() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                return screen
            }
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    /// オーバーレイの位置を計算（マウスカーソルのあるスクリーンに配置）
    private func calculatePosition(for size: NSSize) -> NSPoint {
        let screen = screenForMouseCursor()
        let screenFrame = screen.visibleFrame
        let position = SettingsManager.shared.settings.overlayPosition
        let margin: CGFloat = 30  // 画面端からの余白

        let y = screenFrame.minY + 60

        switch position {
        case .bottomCenter:
            return NSPoint(x: screenFrame.midX - size.width / 2, y: y)
        case .bottomLeft:
            return NSPoint(x: screenFrame.minX + margin, y: y)
        case .bottomRight:
            return NSPoint(x: screenFrame.maxX - size.width - margin, y: y)
        }
    }

    /// マルチモニター間のスクリーン変更を検出して再配置
    private func startScreenTracking() {
        screenTrackingTimer?.invalidate()
        lastScreenFrame = screenForMouseCursor().frame
        screenTrackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isIdle else { return }
            let currentFrame = self.screenForMouseCursor().frame
            if currentFrame != self.lastScreenFrame {
                self.lastScreenFrame = currentFrame
                self.repositionOverlay()
            }
        }
    }

    private func stopScreenTracking() {
        screenTrackingTimer?.invalidate()
        screenTrackingTimer = nil
    }

    /// 現在の状態を維持したまま位置を再計算
    private func repositionOverlay() {
        let size: NSSize
        if isIdle {
            size = NSSize(width: idleWidth, height: idleHeight)
        } else {
            size = NSSize(width: recordingWidth, height: recordingHeight)
        }
        let position = calculatePosition(for: size)
        self.setFrame(NSRect(origin: position, size: size), display: true)

        // 付随ウィンドウも再配置
        if transcriptWindow?.isVisible == true {
            positionTranscriptWindow()
        }
        if dashboardWindow?.isVisible == true {
            positionDashboardWindow()
        }
    }

    /// 録音/処理完了後、アイドル状態に戻る
    func hide() {
        updateTimer?.invalidate()
        updateTimer = nil
        hideTranscriptWindow()
        showIdle()
    }

    // MARK: - Realtime Transcript Display

    func updatePartialTranscript(_ text: String) {
        guard !text.isEmpty else {
            hideTranscriptWindow()
            return
        }

        if transcriptWindow == nil {
            createTranscriptWindow()
        }

        // テキストを最大3行に制限
        let lines = text.components(separatedBy: "\n")
        let displayText: String
        if lines.count > 3 {
            displayText = lines.suffix(3).joined(separator: "\n")
        } else {
            displayText = text
        }
        // 長すぎる場合は末尾だけ表示
        let maxChars = 120
        if displayText.count > maxChars {
            transcriptTextField?.stringValue = "..." + String(displayText.suffix(maxChars))
        } else {
            transcriptTextField?.stringValue = displayText
        }

        positionTranscriptWindow()
        transcriptWindow?.orderFrontRegardless()
    }

    private func createTranscriptWindow() {
        let width: CGFloat = 400
        let height: CGFloat = 60

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        // 角丸黒背景のコンテナ
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        container.layer?.cornerRadius = 10

        // テキストフィールド
        let textField = NSTextField(frame: NSRect(x: 12, y: 8, width: width - 24, height: height - 16))
        textField.isEditable = false
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.textColor = .white
        textField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        textField.alignment = .center
        textField.maximumNumberOfLines = 3
        textField.lineBreakMode = .byTruncatingHead
        textField.cell?.wraps = true

        container.addSubview(textField)
        window.contentView = container

        transcriptWindow = window
        transcriptTextField = textField
    }

    private func positionTranscriptWindow() {
        guard let window = transcriptWindow else { return }

        let overlayFrame = self.frame
        let transcriptSize = window.frame.size
        let y = overlayFrame.maxY + 8

        let position = SettingsManager.shared.settings.overlayPosition
        let x: CGFloat
        switch position {
        case .bottomRight:
            // 右下: 吹き出しの右端をオーバーレイの右端に揃える
            x = overlayFrame.maxX - transcriptSize.width
        case .bottomLeft:
            // 左下: 吹き出しの左端をオーバーレイの左端に揃える
            x = overlayFrame.minX
        case .bottomCenter:
            // 中央: オーバーレイの中央に揃える
            x = overlayFrame.midX - transcriptSize.width / 2
        }

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func hideTranscriptWindow() {
        transcriptWindow?.orderOut(nil)
        transcriptTextField?.stringValue = ""
    }

    // MARK: - Hover Dashboard

    func handleMouseEntered() {
        guard isIdle else { return }

        // 非表示タイマーをキャンセル
        dashboardHideTimer?.invalidate()
        dashboardHideTimer = nil

        // 既に表示中ならそのまま
        if dashboardWindow?.isVisible == true { return }

        // 0.3秒後に表示（ディバウンス）
        dashboardShowTimer?.invalidate()
        dashboardShowTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.showDashboard()
        }
    }

    func handleMouseExited() {
        // 表示タイマーをキャンセル
        dashboardShowTimer?.invalidate()
        dashboardShowTimer = nil

        // 0.2秒後に非表示（ディバウンス）
        dashboardHideTimer?.invalidate()
        dashboardHideTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            self?.hideDashboard()
        }
    }

    private func showDashboard() {
        if dashboardWindow == nil {
            createDashboardWindow()
        }
        updateDashboardContent()
        positionDashboardWindow()
        dashboardWindow?.orderFrontRegardless()
    }

    private func hideDashboard() {
        dashboardWindow?.orderOut(nil)
    }

    private func hideDashboardImmediately() {
        dashboardShowTimer?.invalidate()
        dashboardShowTimer = nil
        dashboardHideTimer?.invalidate()
        dashboardHideTimer = nil
        hideDashboard()
    }

    private func createDashboardWindow() {
        let width: CGFloat = 220
        let height: CGFloat = 96

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        container.layer?.cornerRadius = 10

        var yOffset: CGFloat = height - 8

        // --- ステータス行 ---
        yOffset -= 16
        let dotSize: CGFloat = 8
        let dot = NSView(frame: NSRect(x: 12, y: yOffset + 4, width: dotSize, height: dotSize))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = dotSize / 2
        container.addSubview(dot)
        statusDotView = dot

        let sTF = NSTextField(frame: NSRect(x: 26, y: yOffset, width: width - 38, height: 16))
        sTF.isEditable = false
        sTF.isBordered = false
        sTF.backgroundColor = .clear
        sTF.textColor = .white
        sTF.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        sTF.lineBreakMode = .byTruncatingTail
        container.addSubview(sTF)
        statusLabel = sTF

        // --- セパレータ 1 ---
        yOffset -= 9
        let sep1 = NSView(frame: NSRect(x: 12, y: yOffset, width: width - 24, height: 1))
        sep1.wantsLayer = true
        sep1.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        container.addSubview(sep1)

        // --- 文字起こしプレビュー ---
        yOffset -= 18
        let tTF = NSTextField(frame: NSRect(x: 12, y: yOffset, width: width - 24, height: 16))
        tTF.isEditable = false
        tTF.isBordered = false
        tTF.backgroundColor = .clear
        tTF.textColor = .white
        tTF.font = NSFont.systemFont(ofSize: 11)
        tTF.lineBreakMode = .byTruncatingTail
        container.addSubview(tTF)
        transcriptionPreviewLabel = tTF

        yOffset -= 14
        let tsTF = NSTextField(frame: NSRect(x: 12, y: yOffset, width: width - 24, height: 12))
        tsTF.isEditable = false
        tsTF.isBordered = false
        tsTF.backgroundColor = .clear
        tsTF.textColor = NSColor.white.withAlphaComponent(0.5)
        tsTF.font = NSFont.systemFont(ofSize: 9)
        container.addSubview(tsTF)
        timestampLabel = tsTF

        // --- セパレータ 2 ---
        yOffset -= 7
        let sep2 = NSView(frame: NSRect(x: 12, y: yOffset, width: width - 24, height: 1))
        sep2.wantsLayer = true
        sep2.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        container.addSubview(sep2)

        // --- 今日の使用量 ---
        yOffset -= 16
        let uTF = NSTextField(frame: NSRect(x: 12, y: yOffset, width: width - 24, height: 14))
        uTF.isEditable = false
        uTF.isBordered = false
        uTF.backgroundColor = .clear
        uTF.textColor = NSColor.white.withAlphaComponent(0.8)
        uTF.font = NSFont.systemFont(ofSize: 10)
        container.addSubview(uTF)
        usageLabel = uTF

        window.contentView = container
        dashboardWindow = window
    }

    private func updateDashboardContent() {
        let settings = SettingsManager.shared.settings

        // ステータス
        if settings.useLocalTranscription {
            let status = VoxtralServerManager.shared.status
            statusLabel?.stringValue = L10n.Overlay.localPrefix + status.displayText

            let dotColor: NSColor
            switch status {
            case .ready:        dotColor = .systemGreen
            case .starting:     dotColor = .systemYellow
            case .loadingModel: dotColor = .systemYellow
            case .stopped:      dotColor = .systemGray
            case .error:        dotColor = .systemRed
            }
            statusDotView?.layer?.backgroundColor = dotColor.cgColor
        } else {
            statusLabel?.stringValue = L10n.Overlay.cloudMode
            statusDotView?.layer?.backgroundColor = NSColor.systemBlue.cgColor
        }

        // 直近の文字起こし
        if let lastItem = TranscriptionHistoryManager.shared.items.first {
            transcriptionPreviewLabel?.stringValue = lastItem.textPreview
            timestampLabel?.stringValue = lastItem.formattedTimestamp
        } else {
            transcriptionPreviewLabel?.stringValue = L10n.Overlay.noTranscriptions
            timestampLabel?.stringValue = ""
        }

        // 今日の使用量
        let usage = SettingsManager.shared.getTodayUsage()
        usageLabel?.stringValue = L10n.format(L10n.Overlay.todayTokens, usage.tokens.formatted())
    }

    private func positionDashboardWindow() {
        guard let window = dashboardWindow else { return }

        let overlayFrame = self.frame
        let dashboardSize = window.frame.size
        let y = overlayFrame.maxY + 8

        let position = SettingsManager.shared.settings.overlayPosition
        let x: CGFloat
        switch position {
        case .bottomRight:
            x = overlayFrame.maxX - dashboardSize.width
        case .bottomLeft:
            x = overlayFrame.minX
        case .bottomCenter:
            x = overlayFrame.midX - dashboardSize.width / 2
        }

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// 完全に非表示にする（アプリ終了時など）
    func hideCompletely() {
        updateTimer?.invalidate()
        updateTimer = nil
        stopScreenTracking()
        hideTranscriptWindow()
        hideDashboardImmediately()
        self.orderOut(nil)
    }

    func showProcessing() {
        isIdle = false
        updateTimer?.invalidate()

        // ダッシュボードを即座に非表示
        hideDashboardImmediately()

        // アイドルUI（ミニキャラクター）に切り替え、アニメーション開始
        setupIdleUI()
        idleCatView?.startBouncing()
        self.ignoresMouseEvents = true  // 処理中はクリック無効

        // 設定に応じた位置に配置
        let size = NSSize(width: idleWidth, height: idleHeight)
        let position = calculatePosition(for: size)
        self.setFrame(NSRect(origin: position, size: size), display: true)

        self.orderFrontRegardless()
    }

    private func updateWaveform() {
        guard let catFaceView = catFaceView else { return }

        guard let recordingManager = recordingManagerRef else {
            catFaceView.addLevel(0.0)
            return
        }

        let rawLevel = recordingManager.getAudioLevel()

        let normalizedLevel: CGFloat
        if rawLevel <= silenceThreshold {
            normalizedLevel = 0.0
        } else if rawLevel >= maxLevel {
            normalizedLevel = 1.0
        } else {
            let range = maxLevel - silenceThreshold
            let normalized = (rawLevel - silenceThreshold) / range
            normalizedLevel = CGFloat(normalized)
        }

        catFaceView.addLevel(normalizedLevel)
    }
}

// MARK: - Idle Cat View (常駐ミニキャラクター)

class IdleCatView: NSView {
    // SVG原寸サイズ
    private let svgWidth: CGFloat = 1005
    private let svgHeight: CGFloat = 757

    // アニメーション用
    private var animationTimer: Timer?
    private var animationPhase: CGFloat = 0
    private var isBouncing: Bool = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupTrackingArea()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupTrackingArea()
    }

    private func setupTrackingArea() {
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        (window as? OverlayWindow)?.handleMouseEntered()
    }

    override func mouseExited(with event: NSEvent) {
        (window as? OverlayWindow)?.handleMouseExited()
    }

    func startBouncing() {
        isBouncing = true
        animationPhase = 0
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            self?.animationPhase += 0.15
            self?.needsDisplay = true
        }
    }

    func stopBouncing() {
        isBouncing = false
        animationTimer?.invalidate()
        animationTimer = nil
        animationPhase = 0
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 描画領域（上部に余白を確保、下寄せ）
        let drawHeight: CGFloat = 30  // 実際のキャラクターの高さ
        let drawWidth: CGFloat = 40   // 実際のキャラクターの幅

        // アスペクト比を維持してスケール
        let scaleX = drawWidth / svgWidth
        let scaleY = drawHeight / svgHeight
        let scale = min(scaleX, scaleY)

        let scaledWidth = svgWidth * scale
        let scaledHeight = svgHeight * scale

        // 下寄せ・中央配置
        var offsetX = (bounds.width - scaledWidth) / 2
        var offsetY: CGFloat = 0  // 下寄せ

        // バウンスアニメーション（左右揺れ + ジャンプ）
        if isBouncing {
            // 左右揺れ（sin波）
            let swayAmount: CGFloat = 3.0
            offsetX += sin(animationPhase) * swayAmount

            // ジャンプ（abs(sin)で常に上向き）
            let jumpAmount: CGFloat = 8.0
            let jumpPhase = animationPhase * 1.5  // ジャンプは少し速く
            offsetY += abs(sin(jumpPhase)) * jumpAmount
        }

        context.saveGState()

        // 下寄せ配置 + Y軸反転
        context.translateBy(x: offsetX, y: offsetY + scaledHeight)
        context.scaleBy(x: scale, y: -scale)

        // シアンの背景（猫の輪郭）
        let facePath = CGMutablePath()
        facePath.move(to: CGPoint(x: 990.046, y: 337.253))
        facePath.addCurve(
            to: CGPoint(x: 464.99, y: 755.938),
            control1: CGPoint(x: 1045.53, y: 610.755),
            control2: CGPoint(x: 957.145, y: 765.957)
        )
        facePath.addCurve(
            to: CGPoint(x: 40.459, y: 250.008),
            control1: CGPoint(x: -27.1647, y: 745.92),
            control2: CGPoint(x: -47.5445, y: 478.343)
        )
        facePath.addCurve(
            to: CGPoint(x: 416.48, y: 90.6564),
            control1: CGPoint(x: 128.462, y: 21.6733),
            control2: CGPoint(x: 136.113, y: -91.9074)
        )
        facePath.addCurve(
            to: CGPoint(x: 990.046, y: 337.253),
            control1: CGPoint(x: 587.464, y: -137.853),
            control2: CGPoint(x: 949.233, y: 136.064)
        )
        facePath.closeSubpath()

        context.setFillColor(NSColor.catFaceColor.cgColor)
        context.addPath(facePath)
        context.fillPath()

        // 白い口周り
        let mouthPath = CGMutablePath()
        mouthPath.move(to: CGPoint(x: 823.584, y: 519.933))
        mouthPath.addCurve(
            to: CGPoint(x: 418.698, y: 519.933),
            control1: CGPoint(x: 823.584, y: 606.938),
            control2: CGPoint(x: 624.075, y: 768.004)
        )
        mouthPath.addCurve(
            to: CGPoint(x: 107.585, y: 519.933),
            control1: CGPoint(x: 270.926, y: 687.856),
            control2: CGPoint(x: 107.585, y: 606.938)
        )
        mouthPath.addCurve(
            to: CGPoint(x: 402.27, y: 389.808),
            control1: CGPoint(x: 107.585, y: 432.927),
            control2: CGPoint(x: 212.852, y: 389.808)
        )
        mouthPath.addCurve(
            to: CGPoint(x: 823.584, y: 519.933),
            control1: CGPoint(x: 591.689, y: 389.808),
            control2: CGPoint(x: 823.584, y: 432.927)
        )
        mouthPath.closeSubpath()

        context.setFillColor(NSColor.white.cgColor)
        context.addPath(mouthPath)
        context.fillPath()

        // ピンクの鼻
        let nosePath = CGMutablePath()
        nosePath.move(to: CGPoint(x: 508.045, y: 354.633))
        nosePath.addCurve(
            to: CGPoint(x: 429.564, y: 496.858),
            control1: CGPoint(x: 563.319, y: 352.33),
            control2: CGPoint(x: 466.049, y: 496.858)
        )
        nosePath.addCurve(
            to: CGPoint(x: 346.106, y: 354.633),
            control1: CGPoint(x: 393.079, y: 496.858),
            control2: CGPoint(x: 307.663, y: 354.633)
        )
        nosePath.addCurve(
            to: CGPoint(x: 508.045, y: 354.633),
            control1: CGPoint(x: 384.548, y: 354.633),
            control2: CGPoint(x: 487.138, y: 355.504)
        )
        nosePath.closeSubpath()

        context.setFillColor(NSColor.catNoseColor.cgColor)
        context.addPath(nosePath)
        context.fillPath()

        // 髭（左上）
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(16)
        context.setLineCap(.round)

        context.move(to: CGPoint(x: 64.5731, y: 442.633))
        context.addLine(to: CGPoint(x: 134.313, y: 451.071))
        context.addLine(to: CGPoint(x: 200.741, y: 460.565))
        context.strokePath()

        // 髭（左下）
        context.move(to: CGPoint(x: 64.5731, y: 564.77))
        context.addLine(to: CGPoint(x: 139.417, y: 545.272))
        context.addLine(to: CGPoint(x: 210.707, y: 523.333))
        context.strokePath()

        // 髭（右上）
        context.move(to: CGPoint(x: 900.719, y: 422.55))
        context.addLine(to: CGPoint(x: 795.526, y: 441.45))
        context.addLine(to: CGPoint(x: 695.33, y: 462.716))
        context.strokePath()

        // 髭（右下）
        context.move(to: CGPoint(x: 915.751, y: 535.302))
        context.addLine(to: CGPoint(x: 810.558, y: 524.039))
        context.addLine(to: CGPoint(x: 710.362, y: 511.365))
        context.strokePath()

        context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        // グローバルマウスモニターを開始（ビュー切り替え後もmouseUpを検出）
        if let overlayWindow = self.window as? OverlayWindow {
            overlayWindow.startMouseUpMonitoring()
        }
        // 録音開始通知
        NotificationCenter.default.post(name: .recordingStartedFromOverlay, object: nil)
    }

    // mouseUpはグローバルモニターで処理されるので不要
}

// MARK: - Cat Face View (SVG猫顔 + 左右の髭)

class CatFaceView: NSView {
    var levels: [CGFloat] = []
    let maxLevels = 12
    var isProcessing = false
    var mouthColor: NSColor = .whiskrAccent {
        didSet { needsDisplay = true }
    }
    private var animationPhase: CGFloat = 0
    private var whiskerPadPulse: CGFloat = 0

    // SVG原寸サイズ
    private let svgWidth: CGFloat = 949
    private let svgHeight: CGFloat = 362

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        levels = Array(repeating: 0.0, count: maxLevels)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        levels = Array(repeating: 0.0, count: maxLevels)
        wantsLayer = true
    }

    func reset() {
        isProcessing = false
        animationPhase = 0
        whiskerPadPulse = 0
        levels = Array(repeating: 0.0, count: maxLevels)
        needsDisplay = true
    }

    func addLevel(_ level: CGFloat) {
        let clampedLevel = max(0.0, min(1.0, level))
        levels.removeFirst()
        levels.append(clampedLevel)

        // アニメーション更新（速度アップ: 0.15 → 0.25）
        animationPhase += 0.25
        whiskerPadPulse += 0.2

        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let centerX = bounds.midX
        let centerY = bounds.midY
        let avgLevel = levels.reduce(0, +) / CGFloat(levels.count)

        // 左の髭を描画（黒）
        drawWhiskers(context: context, centerX: centerX, centerY: centerY, isLeft: true, avgLevel: avgLevel)

        // 右の髭を描画（黒）
        drawWhiskers(context: context, centerX: centerX, centerY: centerY, isLeft: false, avgLevel: avgLevel)

        // SVG猫顔を描画
        drawCatFaceSVG(context: context, centerX: centerX, centerY: centerY, avgLevel: avgLevel)
    }

    private func drawWhiskers(context: CGContext, centerX: CGFloat, centerY: CGFloat, isLeft: Bool, avgLevel: CGFloat) {
        let whiskerCount = 2
        let whiskerSpacing: CGFloat = 5
        let baseLength: CGFloat = 37
        let whiskerStartX = isLeft ? centerX - 14 : centerX + 14

        for i in 0..<whiskerCount {
            // 髭の垂直位置（上・下）
            let verticalOffset = CGFloat(i) * whiskerSpacing - whiskerSpacing / 2
            let startY = centerY + verticalOffset - 1

            // 音量データからこの髭の波形を取得
            let levelIndex = isLeft ? (whiskerCount - 1 - i) : (maxLevels - whiskerCount + i)
            let level = isProcessing ? 0.0 : levels[min(levelIndex, levels.count - 1)]

            // 髭の長さ（音量で変化）- 揺らぎを大きく
            let whiskerLength = baseLength + level * 18

            // 髭の角度（上下10度ずつ傾ける + 音量があるときだけ波打ち）
            let baseAngle: CGFloat = isLeft ? CGFloat.pi : 0
            let degrees10: CGFloat = 10 * .pi / 180  // 10度をラジアンに
            let spreadAngle = (i == 0 ? -degrees10 : degrees10) * (isLeft ? -1 : 1)
            // 角度の揺れを大きく（0.1 → 0.3）- pondering中は静止
            let waveAngle = level > 0.05 ? sin(animationPhase + CGFloat(i) * 0.8) * 0.3 * level : 0

            let angle = baseAngle + spreadAngle + waveAngle

            // 髭の終点
            let endX = whiskerStartX + cos(angle) * whiskerLength
            let endY = startY + sin(angle) * whiskerLength * 0.35  // 上下の動きも大きく

            // 波打つ制御点（音量があるときだけ）- 波打ちを大きく（5 → 12）
            let waveOffset = level > 0.05 ? sin(animationPhase * 1.5 + CGFloat(i) * 1.2) * level * 12 : 0
            let ctrlX = (whiskerStartX + endX) / 2
            let ctrlY = startY + waveOffset

            // 色（黒）
            let intensity = 0.7 + level * 0.3
            let color = NSColor.black.withAlphaComponent(intensity)

            // 髭を描画
            context.saveGState()

            context.setStrokeColor(color.cgColor)
            context.setLineWidth(1.5 - CGFloat(abs(i - 1)) * 0.15 + level * 0.2)
            context.setLineCap(.round)

            context.move(to: CGPoint(x: whiskerStartX, y: startY))
            context.addQuadCurve(
                to: CGPoint(x: endX, y: endY),
                control: CGPoint(x: ctrlX, y: ctrlY)
            )
            context.strokePath()

            context.restoreGState()
        }
    }

    private func drawCatFaceSVG(context: CGContext, centerX: CGFloat, centerY: CGFloat, avgLevel: CGFloat) {
        // pondering中は口をx軸方向に±5%で拡大縮小
        let pulseX: CGFloat
        if isProcessing {
            // sin波で0.95〜1.05の範囲でアニメーション
            pulseX = 1.0 + sin(animationPhase * 0.8) * 0.05
        } else {
            pulseX = 1.0
        }

        // Y軸方向にはみ出ないようにスケール決定
        let maxHeight = bounds.height
        let scaleY = maxHeight / svgHeight
        let scaleX = scaleY * pulseX  // X軸のみpulse適用

        let faceWidth = svgWidth * scaleX
        let faceHeight = svgHeight * scaleY

        context.saveGState()

        // 中央に配置 + Y軸反転
        context.translateBy(x: centerX - faceWidth / 2, y: centerY + faceHeight / 2)
        context.scaleBy(x: scaleX, y: -scaleY)  // Y軸反転

        // 顔のパス（白）
        let facePath = CGMutablePath()
        facePath.move(to: CGPoint(x: 948.155, y: 232.922))
        facePath.addCurve(
            to: CGPoint(x: 474.078, y: 203.798),
            control1: CGPoint(x: 948.155, y: 353.187),
            control2: CGPoint(x: 474.078, y: 460.555)
        )
        facePath.addCurve(
            to: CGPoint(x: 0, y: 232.922),
            control1: CGPoint(x: 474.078, y: 457.853),
            control2: CGPoint(x: 0, y: 353.187)
        )
        facePath.addCurve(
            to: CGPoint(x: 474.078, y: 15.1642),
            control1: CGPoint(x: 0, y: 112.658),
            control2: CGPoint(x: 212.252, y: 15.1642)
        )
        facePath.addCurve(
            to: CGPoint(x: 948.155, y: 232.922),
            control1: CGPoint(x: 735.903, y: 15.1642),
            control2: CGPoint(x: 948.155, y: 112.658)
        )
        facePath.closeSubpath()

        context.setFillColor(NSColor.white.cgColor)
        context.addPath(facePath)
        context.fillPath()

        // 鼻のパス（ピンク #EA808C）
        let nosePath = CGMutablePath()
        nosePath.move(to: CGPoint(x: 581.237, y: 0.0376474))
        nosePath.addCurve(
            to: CGPoint(x: 472.756, y: 196.629),
            control1: CGPoint(x: 657.641, y: -3.14584),
            control2: CGPoint(x: 523.188, y: 196.629)
        )
        nosePath.addCurve(
            to: CGPoint(x: 357.395, y: 0.0376474),
            control1: CGPoint(x: 422.324, y: 196.629),
            control2: CGPoint(x: 304.257, y: 0.0376474)
        )
        nosePath.addCurve(
            to: CGPoint(x: 581.237, y: 0.0376474),
            control1: CGPoint(x: 410.533, y: 0.0376474),
            control2: CGPoint(x: 552.339, y: 1.24176)
        )
        nosePath.closeSubpath()

        context.setFillColor(NSColor.catNoseColor.cgColor)
        context.addPath(nosePath)
        context.fillPath()

        context.restoreGState()
    }
}

// MARK: - Menu Bar Controls

class MenuBarRecordingView: NSView {
    private var dotView: NSView?
    private var timeLabel: NSTextField?
    private var waveformView: NSView?
    private var stopButton: NSButton?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        self.layer?.cornerRadius = 6

        // Accent color dot
        let dot = NSView(frame: NSRect(x: 8, y: 6, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.whiskrAccent.cgColor
        dot.layer?.cornerRadius = 4
        dotView = dot
        addSubview(dot)

        // Time label
        let label = NSTextField(frame: NSRect(x: 22, y: 2, width: 50, height: 16))
        label.stringValue = "00:00"
        label.textColor = .white
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        timeLabel = label
        addSubview(label)

        // Stop button
        let stopBtn = NSButton(frame: NSRect(x: 75, y: 0, width: 20, height: 20))
        stopBtn.title = "■"
        stopBtn.font = NSFont.systemFont(ofSize: 10)
        stopBtn.target = self
        stopBtn.action = #selector(stopRecording)
        stopBtn.bezelStyle = .inline
        stopBtn.setButtonType(.momentaryPushIn)
        stopBtn.contentTintColor = .whiskrAccent
        stopButton = stopBtn
        addSubview(stopBtn)
    }

    @objc private func stopRecording() {
        NotificationCenter.default.post(name: .stopRecordingFromMenu, object: nil)
    }

    func updateTime(_ duration: TimeInterval) {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        timeLabel?.stringValue = String(format: "%02d:%02d", minutes, seconds)
    }
}

extension Notification.Name {
    static let stopRecordingFromMenu = Notification.Name("stopRecordingFromMenu")
    static let recordingStartedFromOverlay = Notification.Name("recordingStartedFromOverlay")
    static let recordingStoppedFromOverlay = Notification.Name("recordingStoppedFromOverlay")
    static let localTranscriptionToggled = Notification.Name("localTranscriptionToggled")
}

