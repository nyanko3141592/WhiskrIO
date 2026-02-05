import SwiftUI

// MARK: - Rule Editor View

struct RuleEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let existingRule: TriggerRule?
    let onSave: (TriggerRule) -> Void

    @State private var name: String = ""
    @State private var keywordsText: String = ""
    @State private var action: TriggerRule.ActionType = .custom
    @State private var customPrompt: String = ""

    // パラメータ
    @State private var shellType: String = "zsh"
    @State private var targetLang: String = "en"
    @State private var sourceLang: String = "auto"
    @State private var formatType: String = "plain"
    @State private var rewriteStyle: String = "natural"
    @State private var summarizeLength: String = "medium"

    @State private var showValidationError: Bool = false
    @State private var validationErrorMessage: String = ""

    init(existingRule: TriggerRule? = nil, onSave: @escaping (TriggerRule) -> Void) {
        self.existingRule = existingRule
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Text(existingRule == nil ? "新規ルール" : "ルールを編集")
                    .font(.headline)
                Spacer()
                Button("キャンセル") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // フォーム
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 基本情報
                    basicInfoSection

                    Divider()

                    // アクション選択
                    actionSection

                    Divider()

                    // アクション別パラメータ
                    parametersSection

                    // カスタムプロンプト（カスタムアクションの場合）
                    if action == .custom {
                        Divider()
                        customPromptSection
                    }
                }
                .padding()
            }

            Divider()

            // フッター
            HStack {
                if showValidationError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(validationErrorMessage)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                Spacer()

                Button("保存") {
                    saveRule()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 500, height: 550)
        .onAppear {
            loadExistingRule()
        }
    }

    // MARK: - Sections

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("基本情報")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                // ルール名
                VStack(alignment: .leading, spacing: 4) {
                    Text("ルール名")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("例: ビジネスメール変換", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                // キーワード
                VStack(alignment: .leading, spacing: 4) {
                    Text("トリガーキーワード（カンマ区切り）")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("例: ビジネス, business, biz", text: $keywordsText)
                        .textFieldStyle(.roundedBorder)
                    Text("音声入力の先頭にこれらのキーワードがあると、このルールが発動します")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("アクション")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                // アクション選択
                Picker("処理タイプ", selection: $action) {
                    ForEach(TriggerRule.ActionType.allCases, id: \.self) { actionType in
                        HStack {
                            Image(systemName: actionType.icon)
                            Text(actionType.displayName)
                        }
                        .tag(actionType)
                    }
                }
                .pickerStyle(.menu)

                // アクションの説明
                Text(actionDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private var parametersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("パラメータ")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                switch action {
                case .generateCommand:
                    commandParameters
                case .translate:
                    translateParameters
                case .format:
                    formatParameters
                case .rewrite:
                    rewriteParameters
                case .summarize:
                    summarizeParameters
                case .expand:
                    Text("追加パラメータはありません")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                case .custom:
                    Text("下のカスタムプロンプトで処理内容を定義してください")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
    }

    private var commandParameters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("シェル", selection: $shellType) {
                Text("zsh").tag("zsh")
                Text("bash").tag("bash")
                Text("fish").tag("fish")
            }
            .frame(maxWidth: 200)
        }
    }

    private var translateParameters: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("翻訳元")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("", selection: $sourceLang) {
                        Text("自動検出").tag("auto")
                        Text("日本語").tag("ja")
                        Text("英語").tag("en")
                        Text("中国語").tag("zh")
                        Text("韓国語").tag("ko")
                        Text("フランス語").tag("fr")
                        Text("ドイツ語").tag("de")
                        Text("スペイン語").tag("es")
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }

                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)

                VStack(alignment: .leading) {
                    Text("翻訳先")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("", selection: $targetLang) {
                        Text("日本語").tag("ja")
                        Text("英語").tag("en")
                        Text("中国語").tag("zh")
                        Text("韓国語").tag("ko")
                        Text("フランス語").tag("fr")
                        Text("ドイツ語").tag("de")
                        Text("スペイン語").tag("es")
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
            }
        }
    }

    private var formatParameters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("フォーマット", selection: $formatType) {
                Text("プレーンテキスト").tag("plain")
                Text("Markdown").tag("markdown")
                Text("JSON").tag("json")
                Text("箇条書き").tag("bullet")
            }
            .frame(maxWidth: 200)
        }
    }

    private var rewriteParameters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("文体スタイル", selection: $rewriteStyle) {
                Text("ナチュラル").tag("natural")
                Text("ビジネスメール").tag("business_email")
                Text("カジュアル").tag("casual")
                Text("フォーマル").tag("formal")
                Text("アカデミック").tag("academic")
            }
            .frame(maxWidth: 200)
        }
    }

    private var summarizeParameters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("要約の長さ", selection: $summarizeLength) {
                Text("短い (1-2文)").tag("short")
                Text("普通 (2-3文)").tag("medium")
                Text("詳細 (3-5文)").tag("long")
            }
            .frame(maxWidth: 200)
        }
    }

    private var customPromptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("カスタムプロンプト")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("{text} は入力テキストに置換されます")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextEditor(text: $customPrompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 100)
                    .border(Color.gray.opacity(0.3), width: 1)

                // プロンプト例
                HStack {
                    Text("例:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("敬語変換") {
                        customPrompt = """
                        以下のテキストを丁寧な敬語に変換してください。

                        テキスト: {text}

                        敬語変換:
                        """
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)

                    Button("校正") {
                        customPrompt = """
                        以下のテキストの誤字脱字を修正し、文法を校正してください。

                        テキスト: {text}

                        校正後:
                        """
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var actionDescription: String {
        switch action {
        case .generateCommand:
            return "テキストをシェルコマンドに変換します"
        case .translate:
            return "テキストを指定した言語に翻訳します"
        case .format:
            return "テキストを指定したフォーマットに整形します"
        case .rewrite:
            return "テキストを指定したスタイルで書き換えます"
        case .summarize:
            return "テキストを要約します"
        case .expand:
            return "テキストを詳細に展開します"
        case .custom:
            return "カスタムプロンプトで自由に処理を定義できます"
        }
    }

    // MARK: - Actions

    private func loadExistingRule() {
        guard let rule = existingRule else { return }

        name = rule.name
        keywordsText = rule.keywords.joined(separator: ", ")
        action = rule.action
        customPrompt = rule.prompt ?? ""

        // パラメータの読み込み
        shellType = rule.parameters["shell"] ?? "zsh"
        targetLang = rule.parameters["target_lang"] ?? "en"
        sourceLang = rule.parameters["source_lang"] ?? "auto"
        formatType = rule.parameters["format"] ?? "plain"
        rewriteStyle = rule.parameters["style"] ?? "natural"
        summarizeLength = rule.parameters["length"] ?? "medium"
    }

    private func saveRule() {
        // バリデーション
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            showValidationError = true
            validationErrorMessage = "ルール名を入力してください"
            return
        }

        let keywords = keywordsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if keywords.isEmpty {
            showValidationError = true
            validationErrorMessage = "少なくとも1つのキーワードを入力してください"
            return
        }

        // パラメータの構築
        var parameters: [String: String] = [:]

        switch action {
        case .generateCommand:
            parameters["shell"] = shellType
        case .translate:
            parameters["target_lang"] = targetLang
            parameters["source_lang"] = sourceLang
        case .format:
            parameters["format"] = formatType
        case .rewrite:
            parameters["style"] = rewriteStyle
        case .summarize:
            parameters["length"] = summarizeLength
        case .expand, .custom:
            break
        }

        // ルールの作成
        let rule = TriggerRule(
            id: existingRule?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            keywords: keywords,
            action: action,
            parameters: parameters,
            prompt: action == .custom && !customPrompt.isEmpty ? customPrompt : nil
        )

        onSave(rule)
        dismiss()
    }
}

// MARK: - Rules List View

struct RulesListView: View {
    @Binding var rules: [TriggerRule]
    let onAdd: () -> Void
    let onEdit: (TriggerRule) -> Void
    let onDelete: (TriggerRule) -> Void
    let onReorder: (IndexSet, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ヘッダー
            HStack {
                Text("トリガールール")
                    .font(.headline)

                Spacer()

                Button(action: onAdd) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("追加")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Text("ルールは上から順に評価されます。ドラッグで順序を変更できます。")
                .font(.caption)
                .foregroundColor(.secondary)

            // ルールリスト
            if rules.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("ルールがありません")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("「追加」ボタンで新しいルールを作成してください")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                List {
                    ForEach(rules) { rule in
                        RuleRowView(
                            rule: rule,
                            onEdit: { onEdit(rule) },
                            onDelete: { onDelete(rule) }
                        )
                    }
                    .onMove(perform: onReorder)
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .frame(minHeight: 200, maxHeight: 300)
            }
        }
    }
}

// MARK: - Rule Row View

struct RuleRowView: View {
    let rule: TriggerRule
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // アイコン
            Image(systemName: rule.action.icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)

            // 情報
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name)
                    .font(.system(.body, weight: .medium))

                // キーワード
                HStack(spacing: 4) {
                    ForEach(rule.keywords.prefix(3), id: \.self) { keyword in
                        Text(keyword)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                    if rule.keywords.count > 3 {
                        Text("+\(rule.keywords.count - 3)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // アクションタイプ
            Text(rule.action.displayName)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)

            // アクションボタン
            HStack(spacing: 4) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("編集")
                .opacity(isHovering ? 1.0 : 0.0)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("削除")
                .opacity(isHovering ? 1.0 : 0.0)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button(action: onEdit) {
                Label("編集", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("削除", systemImage: "trash")
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct RuleEditorView_Previews: PreviewProvider {
    static var previews: some View {
        RuleEditorView { _ in }
    }
}
#endif
