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

    /// デフォルトの文字起こしプロンプト
    static let defaultTranscriptionPrompt = """
        Transcribe the following audio to text.

        CRITICAL RULES:
        - Output ONLY the transcription itself
        - DO NOT add any introduction like "Here is the transcription" or "はい、文字起こしはこちらです"
        - DO NOT add any commentary or explanation
        - DO NOT wrap the text in quotes
        - Remove filler words (um, uh, like, えーと, あの)
        - Add appropriate punctuation
        - Format as clean, readable text
        """

    // MARK: - Command Mode Detection
    
    func detectCommandMode(transcribedText: String) -> (isCommand: Bool, cleanedText: String) {
        // まずルールエンジンでチェック
        let ruleResult = RuleEngine.shared.process(text: transcribedText)
        
        if ruleResult.action == .generateCommand {
            return (true, ruleResult.cleanedText)
        }
        
        // フォールバック：従来のトリガーをチェック
        let triggers = SettingsManager.shared.settings.commandModeTriggers
        let trimmedText = transcribedText.trimmingCharacters(in: .whitespaces)
        
        for trigger in triggers {
            let lowercasedTrigger = trigger.lowercased()
            let lowercasedText = trimmedText.lowercased()
            if lowercasedText.hasPrefix(lowercasedTrigger) {
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
    
    func transcribe(audioURL: URL, screenshotData: Data? = nil) async throws -> String {
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

        // まず音声を文字起こし（ルール適用前に元のテキストを取得）
        let transcribedText = try await performBasicTranscription(audioData: audioData, screenshotData: screenshotData)
        
        // ルールエンジンで処理
        let ruleResult = RuleEngine.shared.process(text: transcribedText)
        
        // ルールにマッチした場合は専用プロンプトを使用
        if ruleResult.isDefault {
            // デフォルト処理：既に文字起こし結果を返す
            return transcribedText
        }
        
        // ルールに基づくプロンプト生成（カスタムプロンプトも考慮）
        let prompt = RuleEngine.shared.generatePrompt(
            for: ruleResult.action,
            text: ruleResult.cleanedText,
            parameters: ruleResult.parameters,
            customPrompt: ruleResult.matchedRule?.prompt
        )
        
        // ルールに基づいて追加処理
        return try await processWithRule(text: transcribedText, ruleResult: ruleResult, prompt: prompt)
    }
    
    /// 基本の文字起こしを実行
    private func performBasicTranscription(audioData: Data, screenshotData: Data? = nil) async throws -> String {
        let settings = SettingsManager.shared.settings
        let audioBase64 = audioData.base64EncodedString()

        var prompt = buildDefaultPrompt(settings: settings)

        // スクリーンショットがある場合はプロンプトを追加
        if screenshotData != nil {
            prompt += """


            IMPORTANT - SCREENSHOT CONTEXT RULES:
            - A screenshot is provided ONLY for context understanding
            - DO NOT transcribe or output any text visible in the screenshot
            - DO NOT describe what you see in the screenshot
            - ONLY transcribe what the user SAYS in the audio
            - Use the screenshot silently to understand context (e.g., what app they're using, what they might be referring to)
            - If the user says "this" or "here", understand what they mean from the screenshot, but output only their spoken words
            - The screenshot helps you understand intent, NOT to be transcribed
            """
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

        // partsを構築
        var parts: [[String: Any]] = [
            ["text": prompt]
        ]

        // スクリーンショットがある場合は追加
        if let screenshot = screenshotData {
            let screenshotBase64 = screenshot.base64EncodedString()
            parts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": screenshotBase64
                ]
            ])
            print("[GeminiService] Including screenshot (\(screenshot.count) bytes)")
        }

        // 音声を追加
        parts.append([
            "inline_data": [
                "mime_type": "audio/mp4",
                "data": audioBase64
            ]
        ])

        // リクエストボディの構築
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": parts
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

            // 履歴に追加
            DispatchQueue.main.async {
                TranscriptionHistoryManager.shared.addItem(text: result)
            }

            return result
        } catch let error as GeminiError {
            throw error
        } catch {
            throw GeminiError.networkError(error)
        }
    }
    
    /// デフォルトプロンプトを構築
    private func buildDefaultPrompt(settings: AppSettings) -> String {
        var prompt = """
        Transcribe the following audio to text.

        CRITICAL RULES:
        - Output ONLY the transcription itself
        - DO NOT add any introduction like "Here is the transcription" or "はい、文字起こしはこちらです"
        - DO NOT add any commentary or explanation
        - DO NOT wrap the text in quotes
        - Remove filler words (um, uh, like, えーと, あの)
        - Add appropriate punctuation
        - Format as clean, readable text
        """

        // 言語設定を追加
        if let languageInstruction = settings.speechLanguage.promptInstruction {
            prompt += "\n\nIMPORTANT: \(languageInstruction)"
        }

        return prompt
    }
    
    /// ルールに基づいて処理
    private func processWithRule(text: String, ruleResult: RuleProcessingResult, prompt: String) async throws -> String {
        do {
            // コマンド生成など、追加処理が必要な場合
            if ruleResult.action == .generateCommand {
                let command = try await generateContent(prompt: prompt)

                // テンプレート適用
                if let template = ruleResult.template {
                    let values: [String: String] = [
                        "description": ruleResult.cleanedText,
                        "command": command
                    ]
                    return RuleEngine.shared.applyTemplate(template, values: values)
                }

                return command
            }

            // 翻訳、整形、文体変換、要約、展開の場合
            switch ruleResult.action {
            case .translate, .format, .rewrite, .summarize, .expand:
                let processedText = try await generateContent(prompt: prompt)

                // テンプレート適用
                if let template = ruleResult.template {
                    var values: [String: String] = [:]
                    switch ruleResult.action {
                    case .translate:
                        values["original"] = ruleResult.cleanedText
                        values["translated"] = processedText
                    default:
                        values["content"] = processedText
                    }
                    return RuleEngine.shared.applyTemplate(template, values: values)
                }

                return processedText
            default:
                break
            }

            return text
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
    
    // MARK: - Selection Edit Mode

    /// 選択テキストを音声指示に基づいて編集
    /// - Parameters:
    ///   - selectedText: 選択されたテキスト
    ///   - instruction: 音声で指示された編集内容
    /// - Returns: 編集後のテキスト
    func processSelectionEdit(selectedText: String, instruction: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw GeminiError.noAPIKey
        }

        let prompt = """
        Edit the following text according to the instruction.

        CRITICAL RULES:
        - Output ONLY the edited text
        - DO NOT add any introduction like "Here is the result" or "編集結果はこちら"
        - DO NOT add any commentary or explanation
        - DO NOT wrap the text in quotes
        - DO NOT output the instruction itself
        - Maintain the original language of the text unless the instruction explicitly requests a different language

        Selected text:
        \(selectedText)

        Instruction:
        \(instruction)
        """

        return try await generateContent(prompt: prompt)
    }

    /// 選択テキストにルールを適用
    /// - Parameters:
    ///   - selectedText: 選択されたテキスト
    ///   - ruleResult: マッチしたルールの処理結果
    /// - Returns: ルール適用後のテキスト
    func processSelectionWithRule(selectedText: String, ruleResult: RuleProcessingResult) async throws -> String {
        guard !apiKey.isEmpty else {
            throw GeminiError.noAPIKey
        }

        // ルールに基づいてプロンプトを生成（選択テキストを処理対象にする）
        let prompt = RuleEngine.shared.generatePrompt(
            for: ruleResult.action,
            text: selectedText,
            parameters: ruleResult.parameters,
            customPrompt: ruleResult.matchedRule?.prompt
        )

        let result = try await generateContent(prompt: prompt)

        // テンプレート適用（選択編集モードでは翻訳以外はテンプレート無しで出力）
        if ruleResult.action == .translate, let template = ruleResult.template {
            let values: [String: String] = [
                "original": selectedText,
                "translated": result
            ]
            return RuleEngine.shared.applyTemplate(template, values: values)
        }

        return result
    }

    /// 選択テキスト編集用の音声を文字起こし（指示として）
    /// - Parameter audioURL: 音声ファイルのURL
    /// - Returns: 文字起こしされた指示テキスト
    func transcribeInstruction(audioURL: URL) async throws -> String {
        guard !apiKey.isEmpty else {
            throw GeminiError.noAPIKey
        }

        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL)
        } catch {
            throw GeminiError.encodingError
        }

        let audioBase64 = audioData.base64EncodedString()

        let prompt = """
        Transcribe the following audio to text.

        CRITICAL RULES:
        - Output ONLY the transcription itself
        - DO NOT add any introduction
        - DO NOT add any commentary or explanation
        - This is an instruction for text editing, so preserve the intent clearly
        - Remove filler words (um, uh, like, えーと, あの)
        """

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

            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as GeminiError {
            throw error
        } catch {
            throw GeminiError.networkError(error)
        }
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
