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
    weak var recordingManagerRef: RecordingManager?
    private var updateTimer: Timer?
    private let silenceThreshold: Float = -45.0
    private let maxLevel: Float = -15.0
    private var debugLogCounter: Int = 0
    private var currentMode: RecordingMode = .normal

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 30),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        setupUI()
    }

    private func setupUI() {
        // Container with cyan background
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 30))
        container.wantsLayer = true
        container.layer?.cornerRadius = 15
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor.catFaceColor.cgColor
        containerView = container

        // Cat face view (mouth + whiskers)
        let catFace = CatFaceView(frame: NSRect(x: 0, y: 0, width: 120, height: 30))
        catFaceView = catFace
        container.addSubview(catFace)

        self.contentView = container
        self.setContentSize(NSSize(width: 120, height: 30))
    }

    func show(mode: RecordingMode = .normal) {
        let shouldShow = SettingsManager.shared.settings.showOverlay
        guard shouldShow else { return }

        currentMode = mode
        catFaceView?.reset()
        updateModeColor(for: mode)

        // Position at bottom center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowWidth: CGFloat = 120
            let windowHeight: CGFloat = 30
            let x = screenFrame.midX - windowWidth / 2
            let y: CGFloat = 60
            self.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
        }

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

    func hide() {
        updateTimer?.invalidate()
        updateTimer = nil
        self.orderOut(nil)
    }

    func showProcessing() {
        catFaceView?.isProcessing = true
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

        // アニメーション更新
        animationPhase += 0.15
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
            let level = levels[min(levelIndex, levels.count - 1)]

            // 髭の長さ（音量で変化）
            let whiskerLength = baseLength + level * 10

            // 髭の角度（上下10度ずつ傾ける + 音量があるときだけ波打ち）
            let baseAngle: CGFloat = isLeft ? CGFloat.pi : 0
            let degrees10: CGFloat = 10 * .pi / 180  // 10度をラジアンに
            let spreadAngle = (i == 0 ? -degrees10 : degrees10) * (isLeft ? -1 : 1)
            let waveAngle = level > 0.05 ? sin(animationPhase + CGFloat(i) * 0.8) * 0.1 * level : 0

            let angle = baseAngle + spreadAngle + waveAngle

            // 髭の終点
            let endX = whiskerStartX + cos(angle) * whiskerLength
            let endY = startY + sin(angle) * whiskerLength * 0.25

            // 波打つ制御点（音量があるときだけ）
            let waveOffset = level > 0.05 ? sin(animationPhase * 1.5 + CGFloat(i) * 1.2) * level * 5 : 0
            let ctrlX = (whiskerStartX + endX) / 2
            let ctrlY = startY + waveOffset

            // 色（黒、処理中は少しグレーに変化）
            let color: NSColor
            if isProcessing {
                let phase = (animationPhase + CGFloat(i) * 0.5).truncatingRemainder(dividingBy: 3.0)
                let gray = 0.1 + phase * 0.1
                color = NSColor(white: gray, alpha: 0.9)
            } else {
                let intensity = 0.7 + level * 0.3
                color = NSColor.black.withAlphaComponent(intensity)
            }

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
        // 固定サイズ（アニメーションなし）
        let pulseX: CGFloat = 1.0

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
}

