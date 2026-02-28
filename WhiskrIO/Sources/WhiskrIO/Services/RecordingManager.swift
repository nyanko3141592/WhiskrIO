import Foundation
import AVFoundation
import AppKit
import CoreAudio

// MARK: - Microphone Info
struct MicrophoneInfo: Identifiable, Hashable {
    let id: String  // uniqueID
    let name: String
    let isDefault: Bool
}

class RecordingManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var availableMicrophones: [MicrophoneInfo] = []

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var recordingStartTime: Date?
    private var currentRecordingURL: URL?

    // Streaming mode (for Voxtral)
    private var audioEngine: AVAudioEngine?
    private var audioChunkBuffer = Data()
    private let chunkBufferLock = NSLock()
    private(set) var isStreaming: Bool = false
    private var streamingAudioLevel: Float = -160.0

    override init() {
        super.init()
        refreshMicrophoneList()
    }

    // MARK: - Microphone List

    func refreshMicrophoneList() {
        var mics: [MicrophoneInfo] = []
        let defaultUID = getDefaultInputDeviceUID()

        // CoreAudioを使用してデバイス一覧を取得
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )

        guard status == noErr else {
            print("[RecordingManager] Failed to get device list size: \(status)")
            return
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else {
            print("[RecordingManager] Failed to get device list: \(status)")
            return
        }

        for deviceID in deviceIDs {
            // 入力チャンネル数を確認（入力デバイスかどうか）
            var inputStreamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var streamDataSize: UInt32 = 0
            status = AudioObjectGetPropertyDataSize(deviceID, &inputStreamAddress, 0, nil, &streamDataSize)

            guard status == noErr, streamDataSize > 0 else { continue }

            // デバイス名を取得
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var deviceName: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            status = AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &deviceName)

            guard status == noErr else { continue }

            // デバイスUIDを取得
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var deviceUID: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            status = AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &deviceUID)

            guard status == noErr else { continue }

            let uid = deviceUID as String
            let name = deviceName as String
            let isDefault = (uid == defaultUID)

            mics.append(MicrophoneInfo(id: uid, name: name, isDefault: isDefault))
        }

        // デフォルトを先頭に、その他は名前順
        mics.sort { mic1, mic2 in
            if mic1.isDefault { return true }
            if mic2.isDefault { return false }
            return mic1.name < mic2.name
        }

        DispatchQueue.main.async {
            self.availableMicrophones = mics
        }
    }

    private func getDefaultInputDeviceUID() -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var defaultDeviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &defaultDeviceID
        )

        guard status == noErr else { return nil }

        // UIDを取得
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceUID: CFString = "" as CFString
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        let uidStatus = AudioObjectGetPropertyData(defaultDeviceID, &uidAddress, 0, nil, &uidSize, &deviceUID)

        guard uidStatus == noErr else { return nil }

        return deviceUID as String
    }

    func getSelectedMicrophone() -> MicrophoneInfo? {
        let selectedID = SettingsManager.shared.settings.selectedMicrophoneID

        if let selectedID = selectedID {
            return availableMicrophones.first { $0.id == selectedID }
        }

        // 選択がない場合はデフォルトデバイス
        return availableMicrophones.first { $0.isDefault }
    }
    
    static func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                completion(granted)
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
    
    func startRecording() {
        // 選択したマイクを設定
        configureSelectedMicrophone()

        // 録音設定 - 高品質でGemini APIに最適化
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let fileName = "recording_\(Date().timeIntervalSince1970).m4a"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        currentRecordingURL = url

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()

            isRecording = true
            recordingStartTime = Date()

            // 録音時間の更新タイマー
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)

                // 録音時間上限のチェック
                let maxDuration = TimeInterval(SettingsManager.shared.settings.maxRecordingDuration)
                if self.recordingDuration >= maxDuration {
                    NotificationCenter.default.post(name: .recordingMaxDurationReached, object: nil)
                }
            }

            // 録音開始音
            if SettingsManager.shared.settings.playSoundEffects {
                SoundManager.shared.playStartSound()
            }

        } catch {
            print("録音開始エラー: \(error)")
            isRecording = false
        }
    }

    private func configureSelectedMicrophone() {
        guard let selectedID = SettingsManager.shared.settings.selectedMicrophoneID else {
            // nilの場合はシステムデフォルトを使用
            return
        }

        // 選択したマイクのAudioDeviceIDを取得
        guard let deviceID = getAudioDeviceID(forUID: selectedID) else {
            print("[RecordingManager] Selected microphone not found: \(selectedID)")
            return
        }

        // システムのデフォルト入力デバイスを一時的に変更
        // 注意: これはシステム全体に影響するため、録音終了後に元に戻すべき
        setDefaultInputDevice(deviceID: deviceID)
    }

    private func getAudioDeviceID(forUID uid: String) -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )

        guard status == noErr else { return nil }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else { return nil }

        for deviceID in deviceIDs {
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var deviceUID: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            let uidStatus = AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &deviceUID)

            if uidStatus == noErr && (deviceUID as String) == uid {
                return deviceID
            }
        }

        return nil
    }

    private func setDefaultInputDevice(deviceID: AudioDeviceID) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var mutableDeviceID = deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &mutableDeviceID
        )

        if status != noErr {
            print("[RecordingManager] Failed to set default input device: \(status)")
        } else {
            print("[RecordingManager] Set default input device to: \(deviceID)")
        }
    }
    
    func stopRecording(completion: @escaping (URL?) -> Void) {
        guard let recorder = audioRecorder, recorder.isRecording else {
            completion(nil)
            return
        }

        recorder.stop()

        // 録音停止音
        if SettingsManager.shared.settings.playSoundEffects {
            SoundManager.shared.playStopSound()
        }

        timer?.invalidate()
        timer = nil
        isRecording = false
        recordingDuration = 0

        completion(currentRecordingURL)
    }
    
    func cancelRecording() {
        audioRecorder?.stop()
        audioRecorder?.deleteRecording()

        timer?.invalidate()
        timer = nil
        isRecording = false
        recordingDuration = 0
    }
    
    func getAudioLevel() -> Float {
        // ストリーミング時はPCMバッファから計算したレベルを返す
        if isStreaming {
            return streamingAudioLevel
        }

        guard let recorder = audioRecorder, recorder.isRecording else {
            return -160.0 // 無音レベル
        }
        recorder.updateMeters()
        let level = recorder.averagePower(forChannel: 0)
        // averagePowerは -160dB（無音）〜 0dB（最大）の範囲
        return level
    }

    // MARK: - Streaming Mode (for Voxtral)

    func startStreaming() {
        // 選択したマイクを設定
        configureSelectedMicrophone()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)

        // 目標フォーマット: 16kHz, PCM16, mono
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            print("[RecordingManager] Failed to create target audio format")
            return
        }

        // コンバーターを作成
        guard let converter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
            print("[RecordingManager] Failed to create audio converter")
            return
        }

        // tapでPCMデータを取得
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            // フレーム数を計算
            let ratio = targetFormat.sampleRate / nativeFormat.sampleRate
            let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard outputFrameCapacity > 0 else { return }

            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
                return
            }

            var error: NSError?
            var inputConsumed = false
            let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, error == nil else {
                print("[RecordingManager] Audio conversion error: \(error?.localizedDescription ?? "unknown")")
                return
            }

            // RMSレベルを計算
            if let channelData = outputBuffer.int16ChannelData {
                let frameLength = Int(outputBuffer.frameLength)
                if frameLength > 0 {
                    var sum: Float = 0
                    let data = channelData[0]
                    for i in 0..<frameLength {
                        let sample = Float(data[i]) / Float(Int16.max)
                        sum += sample * sample
                    }
                    let rms = sqrt(sum / Float(frameLength))
                    let db = rms > 0 ? 20 * log10(rms) : -160.0
                    self.streamingAudioLevel = db
                }
            }

            // PCM16データをバッファに追加
            let byteCount = Int(outputBuffer.frameLength) * 2  // Int16 = 2 bytes
            if let rawData = outputBuffer.int16ChannelData {
                let data = Data(bytes: rawData[0], count: byteCount)
                self.chunkBufferLock.lock()
                self.audioChunkBuffer.append(data)
                self.chunkBufferLock.unlock()
            }
        }

        do {
            try engine.start()
            audioEngine = engine
            isStreaming = true
            isRecording = true
            recordingStartTime = Date()

            // 録音時間の更新タイマー（ストリーミング時は時間制限なし）
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }

            // 録音開始音
            if SettingsManager.shared.settings.playSoundEffects {
                SoundManager.shared.playStartSound()
            }

            print("[RecordingManager] Streaming started (16kHz PCM16 mono, no time limit)")
        } catch {
            print("[RecordingManager] Failed to start audio engine: \(error)")
            isStreaming = false
        }
    }

    func flushAudioChunk() -> Data? {
        chunkBufferLock.lock()
        defer { chunkBufferLock.unlock() }

        guard !audioChunkBuffer.isEmpty else { return nil }
        let data = audioChunkBuffer
        audioChunkBuffer = Data()
        return data
    }

    func stopStreaming() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        // 録音停止音
        if SettingsManager.shared.settings.playSoundEffects {
            SoundManager.shared.playStopSound()
        }

        timer?.invalidate()
        timer = nil
        isStreaming = false
        isRecording = false
        recordingDuration = 0
        streamingAudioLevel = -160.0

        chunkBufferLock.lock()
        audioChunkBuffer = Data()
        chunkBufferLock.unlock()

        print("[RecordingManager] Streaming stopped")
    }
}

extension RecordingManager: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("録音が正常に完了しませんでした")
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let recordingMaxDurationReached = Notification.Name("recordingMaxDurationReached")
}

// MARK: - Sound Manager (Cat Mode)
class SoundManager {
    static let shared = SoundManager()

    private var startPlayer: AVAudioPlayer?
    private var stopPlayer: AVAudioPlayer?
    private var successPlayer: AVAudioPlayer?

    init() {
        // 猫音声ファイルをプリロード
        loadSounds()
    }

    private func loadSounds() {
        // アプリバンドル内のSoundsディレクトリから読み込み
        if let bundle = Bundle.main.resourcePath {
            let soundsPath = (bundle as NSString).appendingPathComponent("Sounds")

            // 録音開始音（猫の鳴き声）
            let startPath = (soundsPath as NSString).appendingPathComponent("cat_start.m4a")
            if FileManager.default.fileExists(atPath: startPath) {
                startPlayer = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: startPath))
                startPlayer?.prepareToPlay()
            }

            // 録音停止音（短い鳴き声）
            let stopPath = (soundsPath as NSString).appendingPathComponent("cat_stop.m4a")
            if FileManager.default.fileExists(atPath: stopPath) {
                stopPlayer = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: stopPath))
                stopPlayer?.prepareToPlay()
            }

            // 成功音（ゴロゴロ）
            let successPath = (soundsPath as NSString).appendingPathComponent("cat_success.m4a")
            if FileManager.default.fileExists(atPath: successPath) {
                successPlayer = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: successPath))
                successPlayer?.prepareToPlay()
            }
        }
    }

    func playStartSound() {
        if let player = startPlayer {
            player.currentTime = 0
            player.play()
        } else {
            // フォールバック: システムサウンド
            AudioServicesPlaySystemSound(1113)
        }
    }

    func playStopSound() {
        if let player = stopPlayer {
            player.currentTime = 0
            player.play()
        } else {
            // フォールバック: システムサウンド
            AudioServicesPlaySystemSound(1114)
        }
    }

    func playSuccessSound() {
        if let player = successPlayer {
            player.currentTime = 0
            player.play()
        } else {
            // フォールバック: システムサウンド
            AudioServicesPlaySystemSound(4095)
        }
    }
}

import AudioToolbox
