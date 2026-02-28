import Foundation
import Combine

enum VoxtralError: Error, LocalizedError {
    case connectionFailed(String)
    case serverNotRunning
    case sessionTimeout
    case unexpectedMessage(String)
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let detail):
            return "Voxtral connection failed: \(detail)"
        case .serverNotRunning:
            return "Voxtral server is not running. Please start voxmlx-serve."
        case .sessionTimeout:
            return "Voxtral session creation timed out."
        case .unexpectedMessage(let msg):
            return "Unexpected message from Voxtral: \(msg)"
        case .transcriptionFailed(let detail):
            return "Transcription failed: \(detail)"
        }
    }
}

class VoxtralService: ObservableObject {
    @Published var partialTranscript: String = ""
    @Published var isConnected: Bool = false

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var sessionCreatedContinuation: CheckedContinuation<Void, Error>?
    private var finalTranscriptContinuation: CheckedContinuation<String, Error>?
    private var accumulatedTranscript: String = ""  // 現在のセグメント内のテキスト
    private var fullTranscript: String = ""  // セグメントをまたいで蓄積されるテキスト
    private var isWaitingForFinal: Bool = false
    private let receiveQueue = DispatchQueue(label: "io.whiskr.voxtral.receive")

    private var host: String {
        SettingsManager.shared.settings.voxtralHost
    }
    private var port: Int {
        SettingsManager.shared.settings.voxtralPort
    }

    // MARK: - Connection

    func connect() async throws {
        disconnect()

        let urlString = "ws://\(host):\(port)/v1/realtime"
        guard let url = URL(string: urlString) else {
            throw VoxtralError.connectionFailed("Invalid URL: \(urlString)")
        }

        // リトライ付き接続（サーバー起動直後はまだ受付開始していない場合がある）
        let maxRetries = 10
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                try await connectOnce(url: url)
                DispatchQueue.main.async {
                    self.isConnected = true
                }
                print("[VoxtralService] Connected to \(urlString) (attempt \(attempt))")
                return
            } catch {
                lastError = error
                print("[VoxtralService] Connection attempt \(attempt)/\(maxRetries) failed: \(error.localizedDescription)")

                if attempt < maxRetries {
                    // 次のリトライまで待機（0.5秒 → 1秒 → 1.5秒 ...）
                    let delay = UInt64(attempt) * 500_000_000
                    try? await Task.sleep(nanoseconds: delay)

                    // 再接続前にクリーンアップ
                    webSocketTask?.cancel(with: .abnormalClosure, reason: nil)
                    webSocketTask = nil
                    urlSession?.invalidateAndCancel()
                    urlSession = nil
                    sessionCreatedContinuation = nil
                }
            }
        }

        throw lastError ?? VoxtralError.connectionFailed("Failed after \(maxRetries) attempts")
    }

    private func connectOnce(url: URL) async throws {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: config)
        urlSession = session
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        // Wait for session.created (タイムアウト付き)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    self.sessionCreatedContinuation = continuation
                    self.startReceiving()
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5秒タイムアウト
                throw VoxtralError.sessionTimeout
            }
            // 先に完了した方を採用
            try await group.next()
            group.cancelAll()
        }
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        DispatchQueue.main.async {
            self.isConnected = false
            self.partialTranscript = ""
        }
        accumulatedTranscript = ""
        fullTranscript = ""
        isWaitingForFinal = false
        sessionCreatedContinuation = nil
        finalTranscriptContinuation = nil
    }

    // MARK: - Audio Sending

    func sendAudioChunk(_ pcmData: Data) {
        guard let task = webSocketTask else { return }

        let base64Audio = pcmData.base64EncodedString()
        let message: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64Audio
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        task.send(.string(jsonString)) { error in
            if let error = error {
                print("[VoxtralService] Send audio chunk error: \(error)")
            }
        }
    }

    func commitBuffer(isFinal: Bool) {
        guard let task = webSocketTask else { return }

        var message: [String: Any] = [
            "type": "input_audio_buffer.commit"
        ]
        if isFinal {
            message["final"] = true
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        task.send(.string(jsonString)) { error in
            if let error = error {
                print("[VoxtralService] Commit buffer error: \(error)")
            }
        }
    }

    // MARK: - Final Transcript

    func waitForFinalTranscript() async throws -> String {
        isWaitingForFinal = true
        commitBuffer(isFinal: true)

        return try await withCheckedThrowingContinuation { continuation in
            self.finalTranscriptContinuation = continuation
        }
    }

    // MARK: - WebSocket Receiving

    private func startReceiving() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                // Continue receiving
                self.startReceiving()

            case .failure(let error):
                print("[VoxtralService] Receive error: \(error)")
                // Resolve pending continuations on error
                if let continuation = self.sessionCreatedContinuation {
                    self.sessionCreatedContinuation = nil
                    continuation.resume(throwing: VoxtralError.connectionFailed(error.localizedDescription))
                }
                if let continuation = self.finalTranscriptContinuation {
                    self.finalTranscriptContinuation = nil
                    continuation.resume(throwing: VoxtralError.transcriptionFailed(error.localizedDescription))
                }
                DispatchQueue.main.async {
                    self.isConnected = false
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "session.created":
            print("[VoxtralService] Session created")
            if let continuation = sessionCreatedContinuation {
                sessionCreatedContinuation = nil
                continuation.resume()
            }

        case "response.audio_transcript.delta":
            if let delta = json["delta"] as? String {
                accumulatedTranscript += delta
                let displayText = fullTranscript + accumulatedTranscript
                DispatchQueue.main.async {
                    self.partialTranscript = displayText
                }
            }

        case "response.audio_transcript.done":
            let segmentTranscript = (json["transcript"] as? String) ?? accumulatedTranscript
            print("[VoxtralService] Transcript done: \(segmentTranscript.prefix(50))...")

            // セグメントのテキストをfullTranscriptに蓄積
            fullTranscript += segmentTranscript
            accumulatedTranscript = ""

            if isWaitingForFinal {
                if let continuation = finalTranscriptContinuation {
                    finalTranscriptContinuation = nil
                    isWaitingForFinal = false
                    continuation.resume(returning: fullTranscript)
                }
            } else {
                // 最終でない場合、fullTranscriptを表示に反映
                let displayText = fullTranscript
                DispatchQueue.main.async {
                    self.partialTranscript = displayText
                }
            }

        case "response.done":
            // Response cycle complete
            print("[VoxtralService] Response done")

        case "error":
            let errorMsg = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
            print("[VoxtralService] Server error: \(errorMsg)")
            if let continuation = finalTranscriptContinuation {
                finalTranscriptContinuation = nil
                isWaitingForFinal = false
                continuation.resume(throwing: VoxtralError.transcriptionFailed(errorMsg))
            }

        default:
            break
        }
    }

    // MARK: - Connection Test

    func testConnection() async -> (success: Bool, message: String) {
        do {
            try await connect()
            disconnect()
            return (true, "Connection successful")
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
