import SwiftUI
import AppKit

// MARK: - Brutalist Recording Indicator

class OverlayWindow: NSWindow {
    private var containerView: NSView?
    private var waveformView: BrutalistWaveformView?
    private var statusLabel: NSTextField?
    private var recordingManager: RecordingManager?
    private var updateTimer: Timer?
    
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
        // Container - brutalist black box
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.layer?.borderWidth = 2
        container.layer?.borderColor = NSColor.white.cgColor
        containerView = container
        
        // Red recording dot
        let dot = NSView(frame: NSRect(x: 10, y: 14, width: 12, height: 12))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.red.cgColor
        dot.layer?.cornerRadius = 6
        container.addSubview(dot)
        
        // Status text
        let label = NSTextField(frame: NSRect(x: 30, y: 10, width: 60, height: 20))
        label.stringValue = "REC"
        label.textColor = .white
        label.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.alignment = .left
        statusLabel = label
        container.addSubview(label)
        
        // Waveform
        let waveform = BrutalistWaveformView(frame: NSRect(x: 90, y: 10, width: 100, height: 20))
        waveformView = waveform
        container.addSubview(waveform)
        
        self.contentView = container
    }
    
    func show() {
        // Always show - check settings inside the method for debugging
        let shouldShow = SettingsManager.shared.settings.showOverlay
        print("OverlayWindow show() called. showOverlay setting: \(shouldShow)")
        guard shouldShow else { return }
        
        // Position at bottom center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowWidth: CGFloat = 200
            let windowHeight: CGFloat = 40
            let x = screenFrame.midX - windowWidth / 2
            let y: CGFloat = 60 // 60px from bottom
            self.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
        }
        
        self.orderFrontRegardless()
        
        // Start waveform animation
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateWaveform()
        }
    }
    
    func hide() {
        updateTimer?.invalidate()
        updateTimer = nil
        self.orderOut(nil)
    }
    
    func showProcessing() {
        statusLabel?.stringValue = "..."
        waveformView?.isProcessing = true
    }
    
    private func updateWaveform() {
        guard let waveformView = waveformView else { return }
        
        // Get audio level
        let recordingManager = RecordingManager()
        let level = abs(recordingManager.getAudioLevel()) / 100.0
        
        waveformView.addLevel(CGFloat(level))
    }
}

// MARK: - Brutalist Waveform

class BrutalistWaveformView: NSView {
    var levels: [CGFloat] = []
    let maxBars = 20
    var isProcessing = false
    private var processingOffset: CGFloat = 0
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        levels = Array(repeating: 0.1, count: maxBars)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        levels = Array(repeating: 0.1, count: maxBars)
    }
    
    func addLevel(_ level: CGFloat) {
        let clampedLevel = max(0.1, min(1.0, level))
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
                let barHeight = maxBarHeight * intensity
                let y = (bounds.height - barHeight) / 2
                
                context.fill(CGRect(x: x, y: y, width: barWidth, height: barHeight))
            }
        } else {
            // Recording waveform
            for (i, level) in levels.enumerated() {
                let x = CGFloat(i) * (barWidth + gap)
                let barHeight = maxBarHeight * level
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
