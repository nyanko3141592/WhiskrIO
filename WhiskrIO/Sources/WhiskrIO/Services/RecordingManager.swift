import Foundation
import AVFoundation
import AppKit

class RecordingManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var recordingStartTime: Date?
    private var currentRecordingURL: URL?
    
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
        guard let recorder = audioRecorder, recorder.isRecording else {
            return -160.0 // 無音レベル
        }
        recorder.updateMeters()
        let level = recorder.averagePower(forChannel: 0)
        // averagePowerは -160dB（無音）〜 0dB（最大）の範囲
        return level
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
