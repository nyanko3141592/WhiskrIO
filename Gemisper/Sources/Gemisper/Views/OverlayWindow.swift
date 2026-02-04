import SwiftUI
import AppKit

// MARK: - Brutalist Recording Indicator

class OverlayWindow: NSWindow {
    private var containerView: NSView?
    private var waveformView: BrutalistWaveformView?
    private var recordingDot: NSView?
    weak var recordingManagerRef: RecordingManager?
    private var updateTimer: Timer?
    private let silenceThreshold: Float = -45.0  // -45dB以下は無音扱い
    private let maxLevel: Float = -15.0  // -15dB以上は最大音量扱い
    private var debugLogCounter: Int = 0
    private var currentMode: RecordingMode = .normal
    
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        
        setupUI()
    }
    
    private func setupUI() {
        // Container - brutalist black box（よりコンパクトに）
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 140, height: 36))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.layer?.borderWidth = 2
        container.layer?.borderColor = NSColor.white.cgColor
        containerView = container

        // Recording dot（点滅アニメーション付き）- 色はモードで変更
        let dot = NSView(frame: NSRect(x: 10, y: 12, width: 12, height: 12))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.red.cgColor
        dot.layer?.cornerRadius = 6
        recordingDot = dot
        container.addSubview(dot)

        // 点滅アニメーション
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.3
        animation.duration = 0.5
        animation.autoreverses = true
        animation.repeatCount = .infinity
        dot.layer?.add(animation, forKey: "blink")

        // Waveform（ラベルなしでドットの隣に配置）
        let waveform = BrutalistWaveformView(frame: NSRect(x: 28, y: 8, width: 104, height: 20))
        waveformView = waveform
        container.addSubview(waveform)

        self.contentView = container

        // ウィンドウサイズを調整
        self.setContentSize(NSSize(width: 140, height: 36))
    }
    
    func show(mode: RecordingMode = .normal) {
        let shouldShow = SettingsManager.shared.settings.showOverlay
        guard shouldShow else { return }

        // モードを保存
        currentMode = mode

        // 波形の状態をリセット
        waveformView?.reset()

        // モードに応じてドットの色を変更
        updateDotColor(for: mode)

        // Position at bottom center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowWidth: CGFloat = 140
            let windowHeight: CGFloat = 36
            let x = screenFrame.midX - windowWidth / 2
            let y: CGFloat = 60
            self.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
        }

        self.orderFrontRegardless()

        // Start waveform animation
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateWaveform()
        }
    }

    /// モードに応じてドットの色を更新
    private func updateDotColor(for mode: RecordingMode) {
        switch mode {
        case .normal:
            // 赤 = 通常の音声入力
            recordingDot?.layer?.backgroundColor = NSColor.red.cgColor
        case .selectionEdit:
            // 青 = 選択テキスト編集モード
            recordingDot?.layer?.backgroundColor = NSColor.systemBlue.cgColor
        }
    }
    
    func hide() {
        updateTimer?.invalidate()
        updateTimer = nil
        self.orderOut(nil)
    }
    
    func showProcessing() {
        // Processing中は波形アニメーションで表現
        waveformView?.isProcessing = true
    }
    
    private func updateWaveform() {
        guard let waveformView = waveformView else { return }

        // recordingManagerRefがnilの場合は無音
        guard let recordingManager = recordingManagerRef else {
            waveformView.addLevel(0.0)
            return
        }

        let rawLevel = recordingManager.getAudioLevel()

        // デバッグログ（20回に1回出力）
        debugLogCounter += 1
        if debugLogCounter % 20 == 0 {
            print("[Waveform] rawLevel: \(rawLevel) dB, threshold: \(silenceThreshold), max: \(maxLevel)")
        }

        // 音量レベルを 0.0 ~ 1.0 の範囲にマッピング
        let normalizedLevel: CGFloat
        if rawLevel <= silenceThreshold {
            normalizedLevel = 0.0  // 無音時は完全にフラット
        } else if rawLevel >= maxLevel {
            normalizedLevel = 1.0
        } else {
            let range = maxLevel - silenceThreshold
            let normalized = (rawLevel - silenceThreshold) / range
            normalizedLevel = CGFloat(normalized)
        }

        waveformView.addLevel(normalizedLevel)
    }
}

// MARK: - Brutalist Waveform

class BrutalistWaveformView: NSView {
    var levels: [CGFloat] = []
    let maxBars = 20
    var isProcessing = false
    private var processingOffset: CGFloat = 0
    private let minBarHeight: CGFloat = 2  // 無音時の最小バー高さ

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        levels = Array(repeating: 0.0, count: maxBars)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        levels = Array(repeating: 0.0, count: maxBars)
    }

    /// 状態をリセット（録音開始時に呼び出す）
    func reset() {
        isProcessing = false
        processingOffset = 0
        levels = Array(repeating: 0.0, count: maxBars)
        needsDisplay = true
    }

    func addLevel(_ level: CGFloat) {
        let clampedLevel = max(0.0, min(1.0, level))
        levels.removeFirst()
        levels.append(clampedLevel)
        needsDisplay = true

        if isProcessing {
            processingOffset += 0.1
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let barWidth: CGFloat = 4
        let gap: CGFloat = 1
        let maxBarHeight: CGFloat = bounds.height - 4

        context.setFillColor(NSColor.white.cgColor)

        if isProcessing {
            // Processing animation - simple moving bar
            for i in 0..<maxBars {
                let x = CGFloat(i) * (barWidth + gap)
                let intensity = abs(sin(processingOffset + CGFloat(i) * 0.3))
                let barHeight = max(minBarHeight, maxBarHeight * intensity)
                let y = (bounds.height - barHeight) / 2

                context.fill(CGRect(x: x, y: y, width: barWidth, height: barHeight))
            }
        } else {
            // Recording waveform - 無音時は細いラインのみ
            for (i, level) in levels.enumerated() {
                let x = CGFloat(i) * (barWidth + gap)
                let barHeight = level > 0 ? max(minBarHeight, maxBarHeight * level) : minBarHeight
                let y = (bounds.height - barHeight) / 2

                context.fill(CGRect(x: x, y: y, width: barWidth, height: barHeight))
            }
        }
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
        self.layer?.backgroundColor = NSColor.black.cgColor
        
        // Red dot
        let dot = NSView(frame: NSRect(x: 8, y: 6, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.red.cgColor
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
        
        // Stop button (X)
        let stopBtn = NSButton(frame: NSRect(x: 75, y: 0, width: 20, height: 20))
        stopBtn.title = "■"
        stopBtn.font = NSFont.systemFont(ofSize: 10)
        stopBtn.target = self
        stopBtn.action = #selector(stopRecording)
        stopBtn.bezelStyle = .inline
        stopBtn.setButtonType(.momentaryPushIn)
        stopBtn.contentTintColor = .red
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
}
