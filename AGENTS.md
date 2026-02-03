# Gemisper - Agent Guide

## プロジェクト概要

GemisperはGemini APIを使用したmacOS用の音声入力アプリです。WhisprFlowの機能を再現しています。

- **言語**: Swift
- **プラットフォーム**: macOS 13.0+
- **アーキテクチャ**: Apple Silicon / Intel Mac
- **API**: Google Gemini 2.0 Flash

## ディレクトリ構造

```
Gemisper/
├── Sources/Gemisper/
│   ├── Gemisper.swift              # アプリケーションエントリーポイント
│   ├── Models/
│   │   └── Settings.swift          # 設定モデル・カスタム辞書・スニペット
│   ├── Services/
│   │   ├── GeminiService.swift     # Gemini API連携
│   │   ├── RecordingManager.swift  # 音声録音
│   │   └── HotkeyManager.swift     # グローバルホットキー
│   ├── Views/
│   │   ├── OverlayWindow.swift     # 録音中オーバーレイ
│   │   ├── SettingsView.swift      # 設定画面
│   │   ├── StatusBarController.swift # メニューバー
│   │   └── DictionaryView.swift    # 辞書・スニペット管理
│   └── Utils/
│       └── TextInjector.swift      # テキスト自動入力
├── Package.swift
├── README.md
└── USAGE.md
```

## 開発・ビルド

### 開発ビルド

```bash
cd Gemisper
swift build
```

### リリースビルド

```bash
swift build -c release
```

### .appバンドル作成

```bash
mkdir -p Gemisper.app/Contents/MacOS
cp .build/arm64-apple-macosx/release/Gemisper Gemisper.app/Contents/MacOS/
codesign --force --deep --sign - Gemisper.app
```

## コーディングスタイル

- Swift標準の命名規則に従う
- プロトコル指向プログラミングを活用
- SwiftUIを使用した宣言的UI
- 非処理は`async/await`パターンを使用

## 主要機能モジュール

### 1. 録音管理 (RecordingManager)
- マイクからの音声録音
- Push to Talk / トグルモード対応
- 録音状態の管理

### 2. Gemini連携 (GeminiService)
- 音声ファイルのBase64エンコード
- Gemini APIへのリクエスト
- レスポンス処理・自動編集

### 3. ホットキー (HotkeyManager)
- グローバルホットキーの登録
- 修飾キー（Option/Command）監視
- Push to Talk対応

### 4. テキスト入力 (TextInjector)
- アクセシビリティAPIを使用した他アプリへのテキスト入力
- クリップボード経由の入力フォールバック

## 設定ファイル

設定はUserDefaultsに保存されます：

- `geminiApiKey`: Gemini APIキー
- `inputMode`: 入力モード（pushToTalk / toggle）
- `hotkeyModifiers`: Push to Talk用修飾キー
- `stylePreset`: 文体スタイル
- `customDictionary`: カスタム辞書
- `snippets`: スニペット

## 権限要件

アプリは以下の権限が必要です：

1. **マイク** - 音声録音用
2. **アクセシビリティ** - 他アプリへのテキスト入力用
3. **Apple Events** - アプリケーション制御用

## 依存関係

Package.swiftで管理。現在は標準ライブラリのみ使用。

## 注意事項

- APIキーは設定画面でのみ管理、コードにハードコードしない
- 音声データはGemini API送信時のみ使用、ローカルに保存しない
- エラーハンドリングはユーザーに通知（オーバーレイまたはメニュー）
- メモリリーク防止のため、録音セッションは適切にクリーンアップ

## テスト

```bash
swift test
```

## Subagentの積極的な活用

このプロジェクトでは、以下の場合に積極的にSubagent（`Task`ツール）を使用してください：

### 推奨する使用シナリオ

#### 1. 複数ファイルの並行編集
複数の独立したファイルを修正・リファクタリングする場合は、ファイルごとにSubagentを並列起動します：

```
例: SettingsView.swift、DictionaryView.swift、StatusBarController.swiftの3ファイルを修正する場合
→ 3つのSubagentを並列で起動
```

#### 2. 大規模な調査・探索
コードベース全体や特定のモジュールを調査する場合は、Subagentに任せて結果を要約してもらいます：

```
例: "HotkeyManagerの実装を確認し、Push to Talkの処理フローを説明してください"
→ Subagentが該当ファイルを読み、要点をまとめて返す
```

#### 3. バグ修正・コンパイルエラーの解決
ビルドエラーやバグ修正が必要な場合は、Subagentに原因調査と修正を任せます：

```
例: "'ambiguous use of init' エラーが発生しているので修正してください"
→ Subagentがエラー箇所を特定し、修正内容を返す
```

#### 4. コンテキスト分離が必要な作業
以下のような場合はSubagentを使用してメインコンテキストをクリーンに保ちます：

- 試行錯誤が予想される調査や実験
- 最新の外部ライブラリ情報が必要な場合
- 特定の機能の実装をスクラッチから行う場合

### Subagent使用時のベストプラクティス

1. **明確なタスク定義**: Subagentには具体的で狭い範囲のタスクを与える
2. **必要な背景情報の提供**: ファイルパス、関連コード、期待する出力形式を明示
3. **並列化の活用**: 独立したタスクは並列実行で効率化
4. **結果の統合**: Subagentからの結果を確認し、必要に応じて統合

### 使用例

```
# 複数ファイルのリファクタリング（並列実行）
Task 1: SettingsView.swiftのプレビュー構文を修正
Task 2: DictionaryView.swiftのプレビュー構文を修正
Task 3: StatusBarController.swiftのプレビュー構文を修正

# 調査タスク
Task: "HotkeyManager.swiftでPush to Talkの実装を確認し、
       修飾キー検出のロジックを要約して返してください"

# エラー修正
Task: "ビルドエラー 'Cannot find type RecordingManager' を修正してください"
```

## リファレンス

- [README.md](./README.md) - ユーザー向けドキュメント
- [USAGE.md](./USAGE.md) - 詳細な使用方法
