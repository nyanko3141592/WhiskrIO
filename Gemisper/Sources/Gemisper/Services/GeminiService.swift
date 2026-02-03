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
        
        // プロンプトの構築
        var prompt = "以下の音声を文字起こししてください。"
        
        if settings.removeFillerWords {
            prompt += " 「えーと」「あの」「まあ」「なんか」などのフィラーワードは削除してください。"
        }
        
        if settings.addPunctuation {
            prompt += " 適切な句読点を追加して読みやすく整形してください。"
        }
        
        prompt += " \(settings.style.prompt)"
        
        if settings.language == "ja" {
            prompt += " 日本語で応答してください。"
        } else {
            prompt += " 言語: \(settings.language)"
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
            if let usageMetadata = json["usageMetadata"] as? [String: Any],
               let promptTokenCount = usageMetadata["promptTokenCount"] as? Int,
               let candidatesTokenCount = usageMetadata["candidatesTokenCount"] as? Int {
                DispatchQueue.main.async {
                    SettingsManager.shared.addTokenUsage(
                        inputTokens: promptTokenCount,
                        outputTokens: candidatesTokenCount,
                        modelName: self.modelName
                    )
                }
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
