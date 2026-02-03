import Foundation

enum GeminiError: Error, LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(String)
    case networkError(Error)
    case encodingError
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "APIキーが設定されていません。設定画面でGemini APIキーを入力してください。"
        case .invalidResponse:
            return "APIからの応答が無効です。"
        case .apiError(let message):
            return "APIエラー: \(message)"
        case .networkError(let error):
            return "ネットワークエラー: \(error.localizedDescription)"
        case .encodingError:
            return "音声ファイルのエンコードに失敗しました。"
        }
    }
}

class GeminiService {
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    private var apiKey: String {
        SettingsManager.shared.settings.apiKey
    }
    private var modelName: String {
        SettingsManager.shared.settings.selectedModel.rawValue
    }
    
    // MARK: - Command Mode Detection
    
    func detectCommandMode(transcribedText: String) -> (isCommand: Bool, cleanedText: String) {
        let triggers = SettingsManager.shared.settings.commandModeTriggers
        let lowercasedText = transcribedText.lowercased()
        
        for trigger in triggers {
            let lowercasedTrigger = trigger.lowercased()
            // 先頭にトリガーがあるかチェック（前後の空白を無視）
            let trimmedText = transcribedText.trimmingCharacters(in: .whitespaces)
            if trimmedText.lowercased().hasPrefix(lowercasedTrigger) {
                // トリガー部分を除去
                let cleaned = String(trimmedText.dropFirst(trigger.count)).trimmingCharacters(in: .whitespaces)
                return (true, cleaned)
            }
        }
        
        return (false, transcribedText)
    }
    
    func generateZshCommand(instruction: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw GeminiError.noAPIKey
        }
        
        let prompt = """
        Convert the following instruction to a zsh command.
        Output ONLY the command itself, with no explanation, no markdown, no backticks.
        The command should be safe and follow best practices.
        
        Instruction: \(instruction)
        
        Command:
        """
        
        return try await generateContent(prompt: prompt)
    }
    
    private func generateContent(prompt: String) async throws -> String {
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.1,
                "maxOutputTokens": 1024
            ]
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        let urlString = "\(baseURL)/\(modelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GeminiError.apiError("HTTP error")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GeminiError.invalidResponse
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func transcribe(audioURL: URL) async throws -> String {
        guard !apiKey.isEmpty else {
            throw GeminiError.noAPIKey
        }
        
        let settings = SettingsManager.shared.settings
        
        // 音声ファイルをBase64エンコード
        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL)
        } catch {
            throw GeminiError.encodingError
        }
        
        // ファイルサイズが20MBを超える場合はFiles APIを使用
        let audioBase64 = audioData.base64EncodedString()
        
        // カスタムプロンプトが設定されていれば使用、なければデフォルト
        var prompt: String
        if let customPrompt = settings.customPrompt, !customPrompt.isEmpty {
            prompt = customPrompt
        } else {
            // デフォルトプロンプト（英語）
            prompt = "Transcribe the following audio to text. Remove filler words like \"um\", \"uh\", \"like\", \"you know\". Add appropriate punctuation. Format as clean, readable text."
            
            if settings.language == "ja" {
                prompt += " Respond in Japanese."
            } else if settings.language != "auto" {
                prompt += " Respond in \(settings.language)."
            }
        }
        
        // スタイル設定（カスタムプロンプトがない場合のみ）
        if settings.customPrompt == nil || settings.customPrompt!.isEmpty {
            switch settings.style {
            case .formal:
                prompt += " Use formal and professional language."
            case .casual:
                prompt += " Use casual and friendly language."
            case .concise:
                prompt += " Be concise and to the point."
            case .natural:
                break
            }
        }
        
        // リクエストボディの構築
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        [
                            "inline_data": [
                                "mime_type": "audio/mp4",
                                "data": audioBase64
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": 8192
            ]
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        // APIリクエスト（設定からモデル名を取得）
        let urlString = "\(baseURL)/\(modelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiError.invalidResponse
            }
            
            if httpResponse.statusCode != 200 {
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorJson["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    throw GeminiError.apiError(message)
                }
                throw GeminiError.apiError("HTTP \(httpResponse.statusCode)")
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first,
                  let content = firstCandidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let firstPart = parts.first,
                  let text = firstPart["text"] as? String else {
                throw GeminiError.invalidResponse
            }
            
            // トークン使用量を記録
            print("[DEBUG] GeminiService: API response keys: \(json.keys)")
            if let usageMetadata = json["usageMetadata"] as? [String: Any] {
                print("[DEBUG] GeminiService: usageMetadata = \(usageMetadata)")
                if let promptTokenCount = usageMetadata["promptTokenCount"] as? Int,
                   let candidatesTokenCount = usageMetadata["candidatesTokenCount"] as? Int {
                    print("[DEBUG] GeminiService: tokens input=\(promptTokenCount), output=\(candidatesTokenCount)")
                    DispatchQueue.main.async {
                        SettingsManager.shared.addTokenUsage(
                            inputTokens: promptTokenCount,
                            outputTokens: candidatesTokenCount,
                            modelName: self.modelName
                        )
                    }
                } else {
                    print("[DEBUG] GeminiService: Failed to extract token counts")
                }
            } else {
                print("[DEBUG] GeminiService: No usageMetadata in response")
            }
            
            var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // カスタム辞書の適用
            result = SettingsManager.shared.applyCustomDictionary(to: result)
            
            // スニペットの展開
            result = SettingsManager.shared.expandSnippets(in: result)
            
            return result
            
        } catch let error as GeminiError {
            throw error
        } catch {
            throw GeminiError.networkError(error)
        }
    }
    
    // MARK: - Streaming Transcription (for future use)
    
    func transcribeStreaming(audioURL: URL, onUpdate: @escaping (String) -> Void) async throws {
        // Gemini API は現在ストリーミング文字起こしをサポートしていないため、
        // 将来の機能拡張用にメソッドを用意
        // 現状は通常のtranscribeメソッドを使用
        let result = try await transcribe(audioURL: audioURL)
        onUpdate(result)
    }
    
    // MARK: - Validate API Key
    
    func validateAPIKey() async -> Bool {
        guard !apiKey.isEmpty else { return false }
        
        // 設定からモデル名を取得
        let urlString = "\(baseURL)/\(modelName)?key=\(apiKey)"
        guard let url = URL(string: urlString) else { return false }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
