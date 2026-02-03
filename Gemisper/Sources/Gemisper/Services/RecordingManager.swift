import Foundation
import AVFoundation

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
                guard let startTime = self?.recordingStartTime else { return }
                self?.recordingDuration = Date().timeIntervalSince(startTime)
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
        guard let recorder = audioRecorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        return recorder.averagePower(forChannel: 0)
    }
}

extension RecordingManager: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("録音が正常に完了しませんでした")
        }
    }
}

// MARK: - Sound Manager
class SoundManager {
    static let shared = SoundManager()
    
    private var player: AVAudioPlayer?
    
    func playStartSound() {
        // システムサウンドを使用
        AudioServicesPlaySystemSound(1113) // Tock
    }
    
    func playStopSound() {
        AudioServicesPlaySystemSound(1114) // Tock
    }
    
    func playSuccessSound() {
        AudioServicesPlaySystemSound(4095) // 成功音
    }
}

import AudioToolbox
