# Plan Review: security-review-improvements

Date: 2026-03-14T00:00:00+09:00
Review rounds: 2

## Changes from Round 1 to Round 2

- Added detailed `tailscale whois` detection specification with Node.ID rationale
- Added ProxyJump/HostName/alias sanitization (regex validation)
- Added verification_uri https:// validation
- Added OIDC_CERT_LIFETIME validation (positive integer ≤ 86400)
- Added step to ensure alias resolution consistency across ssh_from_away() and ssh_with_oidc()
- Added ShellCheck pre-run step before CI creation
- Replaced patch application with patches directory cleanup (already applied in HEAD)
- Added VERSION/sha256 naming conventions
- Added --version exit code specification (exit 0)
- Added CI release verification step
- Improved _source_fn to awk-based brace counting
- Added comprehensive is_tailscale_host() fallback integration tests
- Added ssh_from_away() dry-run tests
- Added Threat Model documentation for all detection methods (Tailscale, Gateway MAC, IP)
- Gateway MAC / IP detection: kept as-is (UX convenience, documented in Threat Model)

## Functionality Findings

### F1 [Major] `tailscale whois` の Node.ID 検証だけでは不十分

`tailscale whois` は対象がローカル tailnet 外（exit node のピア等）でもレスポンスを返す場合がある。`Node.ID` の有無だけでなく、`tailscale status --json` の `Peer` マップとのクロスチェック、または `Node.ID` のみで十分とする根拠の明示が必要。

**Recommended action:** 検出仕様を明確化し、プランに記載する。

### F2 [Major] ssh_with_oidc() に ProxyJump エイリアス解決ロジックが欠落

patches-feature パッチは `ssh_from_away()` のみを対象としており、`ssh_with_oidc()` にはエイリアス解決が適用されない。OIDC パスで HostName エイリアスチェーンが壊れる。

**Recommended action:** 共通ヘルパー関数 `build_temp_ssh_config()` へのリファクタリング、または `ssh_with_oidc()` への同等ロジック追加をステップに含める。

### F3 [Major] ShellCheck 除外リストが未確定のまま CI 導入

既存スクリプトに対する ShellCheck 実行結果が事前確認されておらず、CI 初回失敗のリスク。

**Recommended action:** 実装前にローカルで ShellCheck を実行し、必要な SC 除外コードを確定する。

### F4 [Minor] patches-security/0001 が現行 HEAD と競合する可能性

HEAD で既に修正済みの行にパッチが当たり `git apply` が失敗する可能性。

**Recommended action:** `git apply --check` でドライラン後、手動マージを手順に明示。

### F5 [Minor] VERSION 番号と sha256 ファイル命名規則が未定義

リリース URL パターンと README のインストール手順が整合しないリスク。

**Recommended action:** バージョン決定根拠、sha256 ファイル名パターン、GitHub Releases アセット名を明示。

## Security Findings

### S1 [Major] `tailscale whois` のローカルデーモン信頼に関する脅威モデル文書化不足

`tailscale whois` はローカルデーモンへの信頼に依存。ユーザーがセキュリティ保証と誤解するリスク。

**Recommended action:** Threat Model に明記: whois はローカルデーモン信頼であり UX 利便性。サーバー側が実際の境界。

### S2 [Major] 一時 SSH config への ProxyJump/HostName インジェクション

`proxy_jump`、`target_hostname` に改行・ワイルドカードが含まれる場合、`Host *` 相当のエントリが注入される可能性。

**Recommended action:** temp config 書込前にサニタイズ検証を追加（正規表現: `^[a-zA-Z0-9._%-]+$`）。

### S3 [Major] `verification_uri` のスキーム検証欠如

OIDC プロバイダーの `verification_uri` が `https://` であることを検証していない。フィッシング誘導リスク。

**Recommended action:** `oidc_device_authorize()` 内で `https://` スキーム検証を追加。

### S4 [Minor] `OIDC_CERT_LIFETIME` 入力値の未検証

負値や極端に大きな値が CA に渡される可能性。

**Recommended action:** 正の整数であること + 上限（例: 86400 秒）のクライアント側検証を追加。

### S5 [Minor] リリース成果物の CI 検証欠如

`make release` のチェックサム生成が CI で自動検証されない。

**Recommended action:** CI に `make release && sha256sum --check` ステップを追加。

## Testing Findings

### T1 [Critical] `is_tailscale_host()` のフォールバック結合テストが欠如

`tailscale` CLI なし環境での `is_tailscale_host()` 動作を検証するテストが計画に含まれていない。

**Recommended action:** mock bin パターンで以下 3 ケースを追加:
1. CLI なし + CGNAT IP → return 0
2. CLI なし + 非 CGNAT IP → return 1
3. CLI あり + デーモン未起動 → フォールバック + 警告ログ

### T2 [Major] `--version` の終了コード仕様が未定義

テスト設計時に期待値が曖昧。既存引数パーステストとの衝突リスク。

**Recommended action:** `--version` は `exit 0` と明示し、既存テストとの整合性を確認。

### T3 [Major] patches-feature 適用後の ssh_from_away() テストが不在

ProxyJump 検出・エイリアス解決・LocalForward 保持の 3 つの新ロジックを検証するテストがない。

**Recommended action:** dry-run モードで temp config 内容を検証するテストを追加:
1. ProxyJump 設定ホスト → temp config に proxy host スタンザ含む
2. HostName エイリアス → 解決後 FQDN が書き込まれる
3. LocalForward → 全フィールド保持

### T4 [Minor] `oidc_check_cached_cert()` の日付検証がクロスプラットフォームでテストされない

macOS/Linux の `date` フォーマット差異に依存するロジックが、有効期限計算パスを通るテストがない。

**Recommended action:** mock 証明書で有効期限のヒット/ミス判定テストを追加。

### T5 [Minor] `_source_fn` のネスト関数抽出の脆弱性

`sed` パターンが最初の `}` で切り取りを終了し、ネスト関数がある場合に不完全抽出のリスク。

**Recommended action:** 抽出結果の `declare -f` 確認アサート追加、または `awk` ベースのブレース深度カウント方式に置換。
