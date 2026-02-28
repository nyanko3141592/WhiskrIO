import Foundation
import Combine

/// voxmlx サーバーのライフサイクルを管理する
class VoxtralServerManager: ObservableObject {
    static let shared = VoxtralServerManager()

    enum ServerStatus: Equatable {
        case stopped
        case starting          // uvx起動中
        case loadingModel      // モデルロード中
        case ready             // WebSocket接続受付中
        case error(String)

        var displayText: String {
            switch self {
            case .stopped: return "Stopped"
            case .starting: return "Starting..."
            case .loadingModel: return "Loading model..."
            case .ready: return "Ready"
            case .error(let msg): return "Error: \(msg)"
            }
        }

        var isRunning: Bool {
            switch self {
            case .starting, .loadingModel, .ready: return true
            default: return false
            }
        }
    }

    @Published var status: ServerStatus = .stopped

    private var serverProcess: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var recentOutput: String = ""
    private var stoppingIntentionally: Bool = false

    private init() {}

    // MARK: - Server Lifecycle

    func startServer() {
        guard !status.isRunning else {
            print("[VoxtralServerManager] Server already running")
            return
        }

        let settings = SettingsManager.shared.settings
        let port = settings.voxtralPort

        // uvxのパスを探す
        guard let uvxPath = findUvxPath() else {
            DispatchQueue.main.async {
                self.status = .error("uvx not found. Install uv: curl -LsSf https://astral.sh/uv/install.sh | sh")
            }
            return
        }

        // ポートが使用中なら先に解放
        killProcessOnPort(port)

        DispatchQueue.main.async {
            self.status = .starting
        }

        stoppingIntentionally = false
        recentOutput = ""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: uvxPath)
        process.arguments = [
            "--from", "git+https://github.com/T0mSIlver/voxmlx.git[server]",
            "voxmlx-serve",
            "--model", "T0mSIlver/Voxtral-Mini-4B-Realtime-2602-MLX-4bit",
            "--port", String(port)
        ]

        // HOMEとPATHを設定（サンドボックス外で動くように）
        var env = ProcessInfo.processInfo.environment
        if env["HOME"] == nil {
            env["HOME"] = NSHomeDirectory()
        }
        let additionalPaths = [
            "\(NSHomeDirectory())/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        env["PATH"] = additionalPaths.joined(separator: ":") + ":" + (env["PATH"] ?? "")
        process.environment = env

        // プロセスグループを設定して子プロセスもまとめてkillできるようにする
        process.qualityOfService = .userInitiated

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        stdoutPipe = stdout
        stderrPipe = stderr

        // 出力を監視してステータスを更新
        monitorOutput(pipe: stdout)
        monitorOutput(pipe: stderr)

        process.terminationHandler = { [weak self] proc in
            guard let self = self else { return }

            // readabilityHandlerをクリア（パイプ閉じ後の読み取り回避）
            self.stdoutPipe?.fileHandleForReading.readabilityHandler = nil
            self.stderrPipe?.fileHandleForReading.readabilityHandler = nil

            let exitCode = proc.terminationStatus
            print("[VoxtralServerManager] Server process terminated with code \(exitCode)")

            DispatchQueue.main.async {
                if self.stoppingIntentionally {
                    self.status = .stopped
                } else {
                    // 意図しない終了 → エラー原因を出力から推定
                    let errorDetail = self.extractErrorFromOutput()
                    self.status = .error(errorDetail ?? "Server exited (code \(exitCode))")
                }
            }
        }

        do {
            try process.run()
            serverProcess = process
            print("[VoxtralServerManager] Server process started (PID: \(process.processIdentifier))")
        } catch {
            DispatchQueue.main.async {
                self.status = .error("Failed to start: \(error.localizedDescription)")
            }
            print("[VoxtralServerManager] Failed to start server: \(error)")
        }
    }

    func stopServer() {
        stoppingIntentionally = true

        guard let process = serverProcess else {
            DispatchQueue.main.async {
                self.status = .stopped
            }
            return
        }

        DispatchQueue.main.async {
            self.status = .stopped
        }

        // プロセスグループ全体をkill（子プロセスも含む）
        let pid = process.processIdentifier
        if process.isRunning {
            // SIGTERMをプロセスグループに送信（マイナスPIDで子プロセスも対象）
            kill(-pid, SIGTERM)
            // 念のため個別にも
            process.terminate()
        }

        // 少し待ってまだ生きていたらSIGKILL
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if process.isRunning {
                kill(-pid, SIGKILL)
                process.terminate()
            }
        }

        serverProcess = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
        recentOutput = ""
        print("[VoxtralServerManager] Server stopped")
    }

    /// サーバーが ready になるまで待つ（タイムアウト付き）
    func waitForReady(timeout: TimeInterval = 120) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if status == .ready { return true }
            if case .error = status { return false }
            if status == .stopped { return false }
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
        }
        return status == .ready
    }

    // MARK: - Output Monitoring

    private func monitorOutput(pipe: Pipe) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                print("[voxmlx] \(trimmed)")
            }

            self?.recentOutput += text
            // 直近出力を2000文字に制限
            if let output = self?.recentOutput, output.count > 2000 {
                self?.recentOutput = String(output.suffix(2000))
            }

            self?.parseOutput(text)
        }
    }

    private func parseOutput(_ output: String) {
        let lower = output.lowercased()

        // エラー検出（ポート競合など）
        if lower.contains("address already in use") || lower.contains("errno 48") {
            let port = SettingsManager.shared.settings.voxtralPort
            DispatchQueue.main.async {
                self.status = .error("Port \(port) already in use")
            }
            return
        }

        // モデルロード中の検出
        if lower.contains("loading model") || lower.contains("downloading") {
            DispatchQueue.main.async {
                if self.status == .starting || self.status == .loadingModel {
                    self.status = .loadingModel
                }
            }
        }

        // サーバー起動完了の検出（uvicornのスタートアップメッセージ）
        if lower.contains("application startup complete") ||
           lower.contains("uvicorn running") {
            DispatchQueue.main.async {
                self.status = .ready
            }
            print("[VoxtralServerManager] Server is ready")
        }
    }

    private func extractErrorFromOutput() -> String? {
        let lines = recentOutput.components(separatedBy: .newlines)
        // ERROR行を探す
        for line in lines.reversed() {
            let lower = line.lowercased()
            if lower.contains("error") && !lower.contains("info") {
                // 余分なタイムスタンプ等を除去して短くする
                let cleaned = line.trimmingCharacters(in: .whitespaces)
                if cleaned.count > 100 {
                    return String(cleaned.suffix(100))
                }
                return cleaned
            }
        }
        return nil
    }

    // MARK: - Port Management

    private func killProcessOnPort(_ port: Int) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-ti", ":\(port)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty else { return }

            // PIDごとにkill
            for pidStr in output.components(separatedBy: .newlines) {
                if let pid = Int32(pidStr.trimmingCharacters(in: .whitespaces)) {
                    print("[VoxtralServerManager] Killing process \(pid) on port \(port)")
                    kill(pid, SIGTERM)
                }
            }
            // 少し待ってポート解放を確認
            Thread.sleep(forTimeInterval: 0.5)
        } catch {
            print("[VoxtralServerManager] Failed to check port \(port): \(error)")
        }
    }

    // MARK: - uvx Path Discovery

    private func findUvxPath() -> String? {
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/uvx",
            "/opt/homebrew/bin/uvx",
            "/usr/local/bin/uvx",
            "\(NSHomeDirectory())/.cargo/bin/uvx"
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // whichコマンドで探す
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["uvx"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        } catch {}

        return nil
    }
}
