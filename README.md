# Gemisper

Gemini API を使用した macOS 用の音声入力アプリ。WhisprFlow の機能を再現。

## 機能

### 🎤 ユニバーサル音声入力
- どのアプリケーションでも音声入力が可能
- **Push to Talk**: ⌥ Option または ⌘ Command キーを押している間だけ録音
- **トグルモード**: グローバルホットキー（⌘⇧F3）で録音開始/停止を切り替え
- メニューバーからも録音開始/停止可能

### 🤖 AI文字起こし（Gemini API）
- Google Gemini 2.0 Flash モデルを使用
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

### 📚 カスタム辞書
- 特定の単語やフレーズの変換ルールを登録
- 固有名詞や専門用語の正確な変換

### 📝 スニペット機能
- よく使うフレーズを音声ショートカットで展開
- 例: 「@mail」→「your.email@example.com」

### 🎨 インターフェース
- 録音中のビジュアルインジケータ（オーバーレイ表示）
- メニューバーアイコンでの状態確認
- 効果音（録音開始/停止）

## システム要件

- macOS 13.0 以降
- Apple Silicon または Intel Mac
- インターネット接続（Gemini API使用のため）
- マイク

## インストール

### 1. ビルドからインストール

```bash
cd Gemisper
swift build -c release

# .app バンドルを作成
mkdir -p Gemisper.app/Contents/MacOS
cp .build/arm64-apple-macosx/release/Gemisper Gemisper.app/Contents/MacOS/
# Info.plist を配置
codesign --force --deep --sign - Gemisper.app

# アプリケーションへ移動
mv Gemisper.app /Applications/
```

### 2. 権限の付与

初回起動時に以下の権限を求められます：

- **マイク**: 音声入力に必要
- **アクセシビリティ**: 他アプリへのテキスト入力に必要
- **Apple Events**: アプリケーション制御に必要

**システム設定 > プライバシーとセキュリティ** で各権限を有効化してください。

## 設定

### Gemini API キーの取得

1. [Google AI Studio](https://aistudio.google.com/app/apikey) にアクセス
2. 「APIキーを作成」をクリック
3. 生成されたキーをコピー
4. Gemisper の設定画面で API キーを貼り付け

### ホットキーの変更

1. メニューバーから設定を開く
2. 「ホットキー」タブを選択
3. 新しいキーコンビネーションを入力

## 使い方

### 基本的な使い方

1. **録音開始**: ホットキーを押す（またはメニューから「録音開始」を選択）
2. **話す**: 自然に話してください（句読点を意識する必要はありません）
3. **録音停止**: もう一度ホットキーを押す
4. **自動入力**: 変換されたテキストがアクティブなアプリに入力されます

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
└── Package.swift
```

## WhisprFlowとの比較

| 機能 | WhisprFlow | Gemisper |
|------|------------|----------|
| ユニバーサル入力 | ✅ | ✅ |
| AI文字起こし | ✅ | ✅ (Gemini) |
| **Push to Talk** | ✅ | ✅ ⌥/⌘キー対応 |
| トグルモード | ✅ | ✅ |
| フィラーワード除去 | ✅ | ✅ |
| 自動句読点 | ✅ | ✅ |
| カスタム辞書 | ✅ | ✅ |
| スニペット | ✅ | ✅ |
| 多言語対応 | 100+ | 100+ |
| オフライン使用 | ❌ | ❌ |
| ウィスパー対応 | ✅ | ✅（小声でも認識）|
| スタイル調整 | ✅ | ✅ |

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

## ライセンス

MIT License

## 謝辞

- [Google Gemini API](https://ai.google.dev/gemini-api)
- [WhisprFlow](https://wisprflow.ai/) - インスピレーションの源
