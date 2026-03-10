# WhiskrIO - Agent Documentation

## プロジェクト概要

WhiskrIO は Gemini API を使用した macOS 用音声入力アプリです。
WhisprFlow の機能を再現しつつ、より柔軟なカスタマイズを可能にしています。

## アーキテクチャ

### ディレクトリ構造

```
WhiskrIO/
├── Sources/WhiskrIO/
│   ├── WhiskrIO.swift              # AppDelegate + アプリエントリーポイント
│   ├── Models/
│   │   ├── Settings.swift          # アプリ設定（Keychain対応）
│   │   ├── GeminiModel.swift       # Geminiモデル定義（2.5系）
│   │   ├── RuleConfig.swift        # ルールシステム設定（YAML）
│   │   ├── TokenUsage.swift        # トークン使用量追跡
│   │   ├── CustomDictionaryEntry.swift
│   │   └── Snippet.swift
│   ├── Services/
│   │   ├── GeminiService.swift     # Gemini API連携
│   │   ├── VoxtralService.swift    # Voxtral WebSocket通信（ストリーミング文字起こし）
│   │   ├── VoxtralServerManager.swift # voxmlxサーバーライフサイクル管理
│   │   ├── RecordingManager.swift  # 音声録音（バッチ: AVAudioRecorder / ストリーミング: AVAudioEngine）
│   │   ├── HotkeyManager.swift     # グローバルホットキー（CGEventTap）
│   │   ├── RuleEngine.swift        # ルール処理エンジン
│   │   └── TextInjector.swift      # テキスト自動入力
│   ├── Views/
│   │   ├── SettingsView.swift      # 設定画面（ScrollView+VStack）
│   │   ├── StatusBarController.swift # メニューバー管理
│   │   ├── OverlayWindow.swift     # 録音中インジケーター
│   │   └── DictionaryView.swift    # 辞書・スニペット管理
│   └── Utils/
│       ├── KeychainManager.swift   # Keychain APIラッパー
│       └── Strings.swift           # ローカライゼーション
├── Package.swift
├── build.sh
└── rules.yaml.sample
```

## 主要コンポーネント

### 1. SettingsManager

- `@Published` プロパティで SwiftUI と連携
- APIキーは Keychain に保存（`KeychainManager`）
- その他設定は UserDefaults に保存
- トークン使用量も永続化

### 2. GeminiService

- `transcribe(audioURL:)` - 音声文字起こし
- `detectCommandMode()` - コマンドモード検出
- `generateZshCommand()` - zshコマンド生成
- `generateContent()` - 汎用コンテンツ生成

### 3. RuleEngine

- `~/.config/gemisper/rules.yaml` を読み込み
- トリガー検出とアクション実行
- 対応アクション:
  - `generate_command` - コマンド生成
  - `translate` - 翻訳
  - `format` - フォーマット整形
  - `generate_code` - コード生成
  - `custom` - カスタムプロンプト

### 4. HotkeyManager

- Carbon API でグローバルホットキーを登録
- Push to Talk モード時は `NSEvent` で修飾キー監視
- 複合キー対応（⌥Option + ⌘Command など）

### 5. RecordingManager

- **バッチモード**（Gemini API使用時）: `AVAudioRecorder` で44.1kHz, AAC形式
- **ストリーミングモード**（Voxtral使用時）: `AVAudioEngine` で16kHz, PCM16, mono
  - 100msごとにオーディオチャンクをVoxtralServiceへ送信
  - 0.9秒ごとにコミット（中間テキスト取得）
- 録音レベルのモニタリング

### 6. VoxtralService

- WebSocket通信（`ws://host:port/v1/realtime`）
- リアルタイムストリーミング文字起こし
- メッセージプロトコル:
  - `input_audio_buffer.append` - PCM16オーディオチャンク送信（base64）
  - `input_audio_buffer.commit` - バッファコミット
  - `response.audio_transcript.delta` - 中間テキスト受信
  - `response.audio_transcript.done` - セグメント完了
- 自動リトライ: 最大10回（0.5秒刻みで間隔延長）

### 7. VoxtralServerManager

- voxmlxサーバーの起動/停止/状態監視
- `uvx` コマンド経由でサーバー起動
- モデル: `T0mSIlver/Voxtral-Mini-4B-Realtime-2602-MLX-4bit`
- サーバー状態: stopped → starting → loadingModel → ready / error
- ポート競合チェック・クリーンアップ

## セキュリティ

### APIキー管理

```swift
// Keychain に保存（推奨）
KeychainManager.shared.saveAPIKey(key)

// UserDefaults には保存しない
```

### 権限要件

- **マイク** (`NSMicrophoneUsageDescription`)
- **アクセシビリティ** (`NSAccessibilityUsageDescription`)

## ビルド

```bash
cd WhiskrIO/WhiskrIO
./build.sh
```

## 依存関係

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/jpsim/YAMS.git", from: "5.0.0"),
]
```

## 設定ファイル

### ルールファイル

`~/.config/gemisper/rules.yaml`:

```yaml
version: "1.0"

triggers:
  - name: "zshコマンド"
    keywords: ["コマンド", "command"]
    action: "generate_command"
    parameters:
      shell: "zsh"

defaults:
  prompt: "Transcribe..."

templates:
  command: "{command}"
```

## トラブルシューティング

### よくある問題

1. **ビルドエラー**
   - `swift package resolve` を実行
   - Xcode コマンドラインツールがインストールされているか確認

2. **メニューバーが表示されない**
   - `NSStatusBar.system` を使用しているか確認
   - `LSUIElement` が `true` になっているか確認

3. **ホットキーが動作しない**
   - アクセシビリティ権限を確認
   - 他のアプリとホットキーが競合していないか確認

4. **APIキーが保存されない**
   - Keychainアクセス権限を確認
   - `KeychainManager` のエラーハンドリングを確認

## 開発ガイドライン

### コードスタイル

- Swift Concurrency を使用（`async/await`）
- `@MainActor` でUI更新を保護
- エラーハンドリングは `Result` 型または `do-catch`

### 命名規則

- クラス: `PascalCase`
- 関数・変数: `camelCase`
- 定数: `camelCase`（enum case は `lowerCamelCase`）
- ファイル名: `PascalCase.swift`

### コメント

```swift
// MARK: - Section Name

/// 関数の説明
/// - Parameters:
///   - param1: パラメータ1の説明
/// - Returns: 戻り値の説明
func example(param1: String) -> Bool {
    // 実装
}
```

## テスト

（現在テストは未実装）

```bash
swift test
```

## ライセンス

MIT License
