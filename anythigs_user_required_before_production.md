AI:

```
## 結論（要約）

`takt` を **API Key なし**で運用し、**Codex は ChatGPT Plus のサインイン（OAuth）**、**Claude Code は Organization（Console/Team）ログイン（OAuth）**で認証するには、

1. **Codex CLI と Claude Code を先にインストール＆ログイン** → 2) `takt` は **「プロバイダーCLI使用」モード**で動かす（`TAKT_*_API_KEY` を設定しない）→ 3) `piece` で **Plan(Claude)→Audit/Review(Codex)→Implement(Claude)→Fix(Codex)** を宣言、が最短です。([GitHub][1])

---

## 0. 前提（重要）

* `takt` は **「プロバイダーCLIを使用」**（Claude Code / Codex / OpenCode をインストール）または **API直接利用（API Key）**のどちらかを選べます。今回は前者です。([GitHub][1])
* **Codex を Plus 認証で使いたい**場合：**OpenAI API Key を環境変数で渡さない**（`OPENAI_API_KEY` を消す/設定しない）のが安全です。Codex 側が API Key を優先する構成だと「Plus 認証」になりません（ここが一番の事故ポイント）。
* **Claude を Organization ログインで使いたい**場合：Claude Code のログイン方式を **Console（組織課金）**に寄せる（or Team/Enterprise 組織にログインしてそれを使う）必要があります。([Claude Code][2])

## 3. takt を「CLIプロバイダー運用」でインストール＆設定

`takt` は npm で入ります。([GitHub][1])

```bash
npm install -g takt
takt --help
```

### 3.1 API Key を **設定しない**

CLI プロバイダー運用なので、以下は **未設定**にします：

* `TAKT_OPENAI_API_KEY`
* `TAKT_ANTHROPIC_API_KEY`

（設定すると “API直接利用” に倒れて、今回やりたい「Plus/OAuth」「Org/OAuth」からズレます）([GitHub][1])

さらに事故防止で、シェル起動時に以下を確認：

```bash
# 何も出ない/空であることを確認（出るなら消す）
echo "$OPENAI_API_KEY"
echo "$ANTHROPIC_API_KEY"
```

---

## 4. Dual-Core（Claude Plan → Codex Audit → Claude Implement → Codex Fix）の piece を作る

`takt` の肝は「piece(YAML) に協調手順・権限・記録を宣言する」点です。([GitHub][1])
以下は **最小の併用設計**（あなたの要件：Plan中心・監査・修正ループ）を `piece` に落とした例です。

### 4.1 配置

プロジェクト直下に作るのが扱いやすいです：

```bash
mkdir -p .takt/pieces
$EDITOR .takt/pieces/dual-core.yaml
```

### 4.2 `dual-core.yaml`（例）

> 重要：`allowed_tools` は **最小権限**に寄せています（Plan/Audit は原則 Read系のみ）。
> Fix だけ Bash を許可してテスト実行→最小修正に寄せます。

```yaml
name: dual-core
description: Claude(Code/Org)で計画→Codex(Plus)で監査→Claudeで実装→Codexで最小修正
initial_movement: plan
max_movements: 10

piece_config:
  provider_options:
    claude:
      network_access: true
    codex:
      network_access: true

movements:
  - name: plan
    edit: false
    provider: claude
    persona: architect-planner
    knowledge: architecture
    allowed_tools: [Read, Glob, Grep]
    instruction_template: |
      目的: 実装に入る前に PLAN.md を作る（仕様/手順/検証基準を固定する）。
      制約:
      - まだコード変更しない
      - 出力は「PLAN.md（リポジトリ直下）」と「要約レポート」
      生成物:
      - PLAN.md: 要件、変更ファイル候補、手順、テスト/検証、ロールバック手順、リスク
      - レポート: PLAN の要点（箇条書き）
    output_contracts:
      report:
        - name: 01-plan-summary.md
    rules:
      - condition: done
        next: audit

  - name: audit
    edit: false
    provider: codex
    persona: security-reviewer
    knowledge: architecture
    allowed_tools: [Read, Glob, Grep]
    instruction_template: |
      入力: リポジトリ直下の PLAN.md
      目的: PLAN.md を監査し、欠落/矛盾/セキュリティ/依存関係/手順の破綻を洗い出す。
      出力:
      - AUDIT.md（リポジトリ直下）: PASS/FAIL と根拠、修正提案
      - レポート: 重大指摘トップ5
      注意:
      - まだコード変更しない
    output_contracts:
      report:
        - name: 02-audit-top5.md
    rules:
      - condition: done
        next: implement

  - name: implement
    edit: true
    provider: claude
    persona: coder
    knowledge: architecture
    allowed_tools: [Read, Glob, Grep, Edit, Bash]
    instruction_template: |
      入力: PLAN.md と AUDIT.md
      目的: PLAN に従って実装する。AUDIT の指摘は必ず解消する（または理由を書いて却下）。
      ルール:
      - 変更は最小限で、差分の説明を残す
      - テスト/ビルドを実行し、失敗したら原因を切り分けるところまで
      出力:
      - 実装ログ（何を変えたか/コマンド/結果）
    output_contracts:
      report:
        - name: 03-implement-log.md
    rules:
      - condition: done
        next: fix

  - name: fix
    edit: true
    provider: codex
    persona: code-reviewer
    knowledge: architecture
    allowed_tools: [Read, Glob, Grep, Edit, Bash]
    instruction_template: |
      目的: テスト/ビルド失敗を「最小編集」で直し、品質ゲートを通す。
      ルール:
      - テストを“弱める”変更は禁止（必要ならテスト追加は可）
      - 1回の修正で直らなければ、原因→最小修正案→適用、の順で進める
      出力:
      - 修正ログ（原因/差分要約/再実行コマンド/結果）
    output_contracts:
      report:
        - name: 04-fix-log.md
    rules:
      - condition: done
        next: COMPLETE
```

---

## 5. 実行コマンド（今回の認証方式のまま動かす）

`--task` で直接実行、`--piece` で piece を指定できます。([GitHub][1])

```bash
# まずは対話なしで投げる（タスク文は短く具体）
takt --task "PLAN.mdを作り、監査し、実装して、テストが通るところまで直して" --piece dual-core
```

CI 的に完全非対話に寄せるなら `--pipeline` ですが、**OAuthログインの CLI をCIで安定運用するのは一般に難しい**（トークン更新・端末紐付けなど）ので、まずはローカル実行から始めるのが安全です。([GitHub][1])

---

## 6. 事故りやすい点（チェックリスト）

1. **`OPENAI_API_KEY` が残っていて Codex が API 課金に倒れる**
   → `echo "$OPENAI_API_KEY"` が空、かつ `~/.codex/config.toml` で chatgpt 強制（可能なら）([OpenAI Developers][4])
2. **Claude が個人ログインになってしまう**
   → managed settings で login method を固定（組織ルールに合わせる）([Claude Code][2])
3. **npm グローバルの権限問題（sudo 乱用）**
   → Claude Code 側も npm 導入時に “sudo 使うな” 系の注意があるので、ユーザ領域 prefix を徹底([Claude Code][6]



user:このとき対話型で実行してもこのpieceの設定は適用される？

AI:## 結論

**はい。対話型（Interactive mode）で実行しても、選択（または `--piece` 指定）した piece はそのまま適用されます。**
対話フェーズは「タスク文（instructions）を詰める前段」で、`/go` で確定した後に **piece を実行**します。([GitHub][1])

---

## どう適用されるか（内部フロー）

`takt` の対話モードは公式に次の流れです：

1. **piece を選ぶ**
2. 対話モード種別を選ぶ（assistant / persona / quiet / passthrough）
3. 会話でタスク内容を詰める
4. `/go` でタスク指示を確定
5. **piece を実行**（worktree作成→piece実行→PR…）([GitHub][1])

つまり、**piece の movement / rules / provider / tools / permission_mode などは、(5) の実行フェーズで必ず効きます**。

---

## 例：あなたの `dual-core` piece は対話型でも効く？

効きます。具体的には：

* `/go` 後、`dual-core.yaml` の `initial_movement` から movement が順に走り、各 movement の
  `provider`（claude/codex）、`allowed_tools`、`edit`、`rules` が適用されます（＝あなたの Dual-Core 設計がそのまま実行される）。([GitHub][1])

---

## ただし重要：対話フェーズ “自体” に piece がどこまで影響するか

対話モードは4種類あり、**対話フェーズが piece の persona/tools を使うか**が変わります：

* `assistant`（デフォルト）: AIが質問して要件整理（piece固有の persona/tools ではない）
* `persona`: **「最初の movement の persona（system prompt と tools）」で会話**する
* `quiet`: 質問なしで best-effort 生成
* `passthrough`: 入力を加工せずタスク文にする ([GitHub][1])

なので、**「対話中から plan を Claude（Orgログイン）で回したい／Read-only制約で動かしたい」**なら、`dual-core` の先頭 movement が `provider: claude` になっている前提で、対話モードを `persona` にするのが最も一貫します。([GitHub][1])

さらに、piece 側で `interactive_mode` を YAML に書いて**デフォルトの対話モードを固定**できます。([GitHub][1])

---

## 実務的におすすめの使い方

### 1) 対話起動時点から piece を固定したい

対話で `takt` を起動しても、最初に piece 選択が出ますが、オプションで piece 指定も可能です（`-w, --piece`）。([GitHub][1])

```bash
# 対話モードのまま、pieceだけ dual-core に固定して起動
takt -w dual-core
# → 対話で要件を詰める → /go → dual-core が実行される
```

### 2) 対話モードも毎回 persona にしたい（おすすめ）

`dual-core.yaml` に（可能なら）以下を追加：

```yaml
interactive_mode: persona
```

これで「対話フェーズ」も first movement の persona/tools 前提になり、Dual-Core の思想（Planの厳格化）がブレにくくなります。([GitHub][1])

---
