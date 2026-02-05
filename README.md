<p align="center">
  <img src="Gemisper/Resources/AppIcon.iconset/icon_256x256.png" alt="WhiskrIO" width="128" height="128">
</p>

# WhiskrIO

Gemini API を使用した macOS 用の音声入力アプリ。猫のひげ（Whisker）のように敏感に音声をキャッチし、テキストに変換します。

## 機能

### 🎤 ユニバーサル音声入力
- どのアプリケーションでも音声入力が可能
- **Push to Talk**: ⌥ Option + ⌘ Command など複合キー対応
- **トグルモード**: グローバルホットキーで録音開始/停止を切り替え
- メニューバーからも録音開始/停止可能

### 🤖 AI文字起こし（Gemini API）
- Google Gemini 2.5 Flash-Lite / Flash / Pro モデル対応
- 高精度な音声認識
- 日本語・英語対応（100+言語）

### ✨ AI自動編集
- **フィラーワード除去**: 「えーと」「あの」「まあ」などを自動削除
- **自動句読点**: 自然な文中に適切な句読点を追加
- **文体スタイル調整**: 
  - 自然（デフォルト）
  - フォーマル（ビジネス文書向け）
  - カジュアル（チャット向け）
  - 簡潔（要点まとめ）

### 📝 カスタムプロンプト
- ユーザー独自の文字起こしプロンプトを設定可能
- デフォルトは英語プロンプト
- 用途に応じた細かな調整が可能

### ⚡ コマンドモード
- 音声でzsh/bashコマンドを生成
- トリガーワードをカスタマイズ可能（デフォルト: 「コマンド」「command」）
- 例: 「コマンド ホームディレクトリのファイル一覧」→ `ls ~`

### 📜 ルールシステム（.cursorrules風）
- `~/.config/whiskrio/rules.yaml` で柔軟なルール定義
- トリガーワードとアクションを自由に設定
- 対応アクション:
  - `generate_command`: zsh/bashコマンド生成
  - `translate`: 翻訳（日英/英日など）
  - `format`: Markdown/JSON/箇条書き整形
  - `rewrite`: 文体変換（ビジネス/カジュアル）
  - `summarize`: 要約
  - `expand`: 詳細化
  - `custom`: カスタムプロンプト

### 📚 カスタム辞書
- 特定の単語やフレーズの変換ルールを登録
- 固有名詞や専門用語の正確な変換

### 🔖 スニペット機能
- よく使うフレーズを音声ショートカットで展開
- 例: 「@mail」→「your.email@example.com」

### 💰 使用量トラッキング
- 直近のトークン使用量と概算金額を表示
- 今日/今月の累計使用量
- メニューバーからリアルタイム確認

### 🎨 インターフェース
- 録音中のビジュアルインジケータ（画面下部にコンパクト表示）
- メニューバーアイコンでの状態確認
- 効果音（録音開始/停止）
- 日英UI切り替え対応

## システム要件

- macOS 13.0 以降
- Apple Silicon または Intel Mac
- インターネット接続（Gemini API使用のため）
- マイク

## インストール

### 1. ビルドからインストール

```bash
cd Gemisper
./build.sh

# アプリケーションへ移動
cp -r WhiskrIO.app /Applications/
```

### 2. 権限の付与

初回起動時に以下の権限を求められます：

- **マイク**: 音声入力に必要
- **アクセシビリティ**: 他アプリへのテキスト入力に必要

**システム設定 > プライバシーとセキュリティ** で各権限を有効化してください。

## 設定

### Gemini API キーの取得

1. [Google AI Studio](https://aistudio.google.com/app/apikey) にアクセス
2. 「APIキーを作成」をクリック
3. 生成されたキーをコピー
4. WhiskrIO の設定画面で API キーを貼り付け（👁️ボタンで表示/非表示切替、📋ボタンでペースト）

**注意**: APIキーは Keychain に安全に保存されます。

### モデル選択

設定画面 → API タブで選択可能:

| モデル | 特徴 | 料金 |
|--------|------|------|
| Gemini 2.5 Flash-Lite | 最速・最安 | $0.10/M tokens |
| Gemini 2.5 Flash | バランス型 | $0.30/M tokens |
| Gemini 2.5 Pro | 最高精度 | $1.25/M tokens |

### ホットキーの変更

1. メニューバーから設定を開く
2. 「ホットキー」タブを選択
3. Push to Talk またはトグルモードを選択
4. キーを設定

### カスタムプロンプトの設定

1. 設定 → 「プロンプト」タブ
2. 「文字起こしプロンプト」セクションで編集
3. 空欄の場合はデフォルトプロンプトを使用

### ルールファイルの設定

```bash
mkdir -p ~/.config/whiskrio
cp rules.yaml.sample ~/.config/whiskrio/rules.yaml
open ~/.config/whiskrio/rules.yaml
```

サンプル:
```yaml
version: "1.0"

triggers:
  - name: "zshコマンド"
    keywords: ["コマンド", "command"]
    action: "generate_command"
    parameters:
      shell: "zsh"

defaults:
  prompt: "Transcribe the following audio..."

templates:
  command: "{command}"
```

## 使い方

### 基本的な使い方（Push to Talk）

1. **⌥Option + ⌘Command を押し続ける**
2. **話す**（キーを押している間、録音されます）
3. **キーを離す**（自動的に録音停止→文字起こし→入力）

### コマンドモードの使い方

1. 音声入力の先頭に「コマンド」と言う
2. 実行したい内容を話す
3. zshコマンドが生成されて入力される

例:
- 音声: 「コマンド ホームディレクトリのファイル一覧」
- 出力: `ls ~`

### カスタム辞書の活用例

| 変換前 | 変換後 |
|--------|--------|
| つまり | つまり、 |
| 例えば | 例えば、 |
| 株式会社A | 株式会社AIテクノロジー |

### スニペットの活用例

| トリガー | 展開後 |
|----------|--------|
| @mail | your.email@example.com |
| @addr | 東京都渋谷区... |
| @tel | 03-1234-5678 |

## アーキテクチャ

```
Gemisper/
├── Sources/WhiskrIO/
│   ├── WhiskrIO.swift              # アプリケーションエントリーポイント
│   ├── Models/
│   │   ├── Settings.swift          # 設定モデル・トークン使用量
│   │   ├── GeminiModel.swift       # Geminiモデル定義
│   │   ├── RuleConfig.swift        # ルールシステム設定
│   │   └── TranscriptionHistory.swift # 文字起こし履歴
│   ├── Services/
│   │   ├── GeminiService.swift     # Gemini API連携
│   │   ├── RecordingManager.swift  # 音声録音
│   │   ├── HotkeyManager.swift     # グローバルホットキー
│   │   └── RuleEngine.swift        # ルール処理エンジン
│   ├── Views/
│   │   ├── OverlayWindow.swift     # 録音中オーバーレイ
│   │   ├── SettingsView.swift      # 設定画面
│   │   ├── StatusBarController.swift # メニューバー
│   │   ├── DictionaryView.swift    # 辞書・スニペット管理
│   │   └── RuleEditorView.swift    # ルールエディタ
│   └── Utils/
│       ├── TextInjector.swift      # テキスト自動入力
│       ├── KeychainManager.swift   # Keychain管理
│       └── Strings.swift           # ローカライゼーション
├── Package.swift
└── rules.yaml.sample               # ルールファイルサンプル
```

## WhisprFlowとの比較

| 機能 | WhisprFlow | WhiskrIO |
|------|------------|----------|
| ユニバーサル入力 | ✅ | ✅ |
| AI文字起こし | ✅ | ✅ (Gemini 2.5) |
| **Push to Talk** | ✅ | ✅ 複合キー対応 |
| **カスタムプロンプト** | ❌ | ✅ |
| **コマンドモード** | ❌ | ✅ zsh生成 |
| **ルールシステム** | ❌ | ✅ YAML設定 |
| フィラーワード除去 | ✅ | ✅ |
| 自動句読点 | ✅ | ✅ |
| カスタム辞書 | ✅ | ✅ |
| スニペット | ✅ | ✅ |
| 使用量トラッキング | ❌ | ✅ |
| 多言語対応 | 100+ | 100+ |
| **日英UI切替** | ❌ | ✅ |

## トラブルシューティング

### アプリが起動しない
- 権限設定を確認してください
- 右クリック > 「開く」から起動してみてください

### 音声が認識されない
- マイク権限が許可されているか確認
- インターネット接続を確認
- Gemini API キーが正しく設定されているか確認

### テキストが入力されない
- アクセシビリティ権限を確認
- 対象アプリがテキスト入力を受け付ける状態か確認

### APIキーが保存されない
- Keychainアクセス権限を確認
- 設定画面で「検証」ボタンを押して有効性を確認

## ライセンス

MIT License

## 謝辞

- [Google Gemini API](https://ai.google.dev/gemini-api)
- [WhisprFlow](https://wisprflow.ai/) - インスピレーションの源
- [YAMS](https://github.com/jpsim/YAMS) - YAMLパーサー
