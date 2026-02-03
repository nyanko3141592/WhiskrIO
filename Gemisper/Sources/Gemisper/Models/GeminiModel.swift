import Foundation

enum GeminiModel: String, Codable, CaseIterable, Identifiable {
    var id: String { rawValue }
    
    // MARK: - Gemini 2.5 Series (推奨)
    case flashLite = "gemini-2.5-flash-lite"
    case flash = "gemini-2.5-flash"
    case pro = "gemini-2.5-pro"
    
    // MARK: - Gemini 2.0 Series (Deprecated)
    case gemini20Flash = "gemini-2.0-flash"
    case gemini20FlashLite = "gemini-2.0-flash-lite"
    
    var displayName: String {
        switch self {
        case .flashLite:
            return "Gemini 2.5 Flash-Lite"
        case .flash:
            return "Gemini 2.5 Flash"
        case .pro:
            return "Gemini 2.5 Pro"
        case .gemini20Flash:
            return "Gemini 2.0 Flash (Deprecated)"
        case .gemini20FlashLite:
            return "Gemini 2.0 Flash-Lite (Deprecated)"
        }
    }
    
    var description: String {
        switch self {
        case .flashLite:
            return "最速・最安のコスト効率モデル。高スループットで音声認識に最適。無料枠あり。"
        case .flash:
            return "価格性能比最良のモデル。速度と精度のバランスが取れている。無料枠あり。"
        case .pro:
            return "最先端のThinkingモデル。複雑な推論や専門的な文字起こしに強い。無料枠あり。"
        case .gemini20Flash, .gemini20FlashLite:
            return "【非推奨】2026年3月31日に終了予定。"
        }
    }
    
    /// 音声認識に対応しているか
    var supportsAudio: Bool {
        switch self {
        case .flashLite, .flash, .pro, .gemini20Flash, .gemini20FlashLite:
            return true
        }
    }
    
    /// 無料枠があるか
    var hasFreeTier: Bool {
        switch self {
        case .flashLite, .flash, .pro, .gemini20Flash, .gemini20FlashLite:
            return true
        }
    }
    
    /// 推奨モデル（非推奨でない）
    var isRecommended: Bool {
        switch self {
        case .gemini20Flash, .gemini20FlashLite:
            return false
        default:
            return true
        }
    }
    
    /// 価格帯（Input/Output per 1M tokens in USD）
    var pricingDescription: String {
        switch self {
        case .flashLite:
            return "$0.10 / $0.40 (最安)"
        case .flash:
            return "$0.30 / $2.50 (安)"
        case .pro:
            return "$1.25 / $10.00 (高)"
        case .gemini20Flash:
            return "$0.10~0.70 / $0.40"
        case .gemini20FlashLite:
            return "$0.075 / $0.30"
        }
    }
    
    /// 概算金額計算（USD→JPY換算、1USD=150JPY）
    func calculateCost(inputTokens: Int, outputTokens: Int) -> (usd: Double, jpy: Int) {
        let inputCostPer1M: Double
        let outputCostPer1M: Double
        
        switch self {
        case .flashLite:
            inputCostPer1M = 0.10
            outputCostPer1M = 0.40
        case .flash:
            inputCostPer1M = 0.30
            outputCostPer1M = 2.50
        case .pro:
            inputCostPer1M = 1.25
            outputCostPer1M = 10.00
        case .gemini20Flash:
            inputCostPer1M = 0.35
            outputCostPer1M = 0.40
        case .gemini20FlashLite:
            inputCostPer1M = 0.075
            outputCostPer1M = 0.30
        }
        
        let inputCost = Double(inputTokens) / 1_000_000 * inputCostPer1M
        let outputCost = Double(outputTokens) / 1_000_000 * outputCostPer1M
        let totalUSD = inputCost + outputCost
        let totalJPY = Int(totalUSD * 150) // 1USD = 150JPY
        
        return (usd: totalUSD, jpy: totalJPY)
    }
}
