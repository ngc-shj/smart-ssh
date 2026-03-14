# OIDC Device Flow 対応 実装計画

## Objective

会社PC（macOS、Tailscaleなし、セキュリティキーなし）から安全にSSH接続できるようにする。
OIDC Device Flow (RFC 8628) で認証 → 短寿命SSH証明書を取得 → その証明書でSSH接続する機能を smart-ssh に追加する。

## Requirements

### Functional

- OIDC Device Flow による認証（ブラウザでURL+コードを入力して承認）
- 認証成功後、CA API から短寿命SSH証明書を自動取得
- 証明書キャッシュ（有効期限内は再認証不要。キャッシュ有効時は Discovery リクエストもスキップ）
- `--oidc` フラグで強制OIDC認証
- `--dry-run` でのOIDCフロー確認
- `--debug` でのOIDC設定表示
- OIDC失敗時のフォールバック（条件付き: 後述）

### Non-functional

- 既存のhome/away判定ロジックへの影響なし
- 外部依存は `jq` のみ追加（`curl`, `ssh-keygen` は既存）
- CA実装に依存しない汎用API方式
- RFC 8628 準拠のエラーハンドリング

## アーキテクチャ

```text
現在:  main() → ネットワーク検出 → home → ssh_from_home()
                                 → away → ssh_from_away() (sk key)

変更後: main() → ネットワーク検出 → home → ssh_from_home()
                                  → away → OIDC有効? → ssh_with_oidc() → 条件付きフォールバック
                                         → OIDC無効  → ssh_from_away() (sk key)
```

## 変更対象ファイル

| ファイル                      | 変更内容                                           |
| ----------------------------- | -------------------------------------------------- |
| `smart-ssh`                   | OIDC関連関数の追加、main()フロー変更、設定項目追加 |
| `tests/test_smart_ssh.bats`   | OIDCユニットテスト追加                             |
| `completions/smart-ssh.bash`  | `--oidc` オプション補完                            |
| `completions/_smart-ssh`      | `--oidc` オプション補完                            |
| `README.md` / `README.ja.md` | OIDC設定ドキュメント追加                           |

## 設定項目 (`~/.config/smart-ssh/config`)

```ini
OIDC_ENABLED=false
OIDC_ISSUER=https://accounts.example.com
OIDC_CLIENT_ID=smart-ssh-cli
OIDC_SCOPES=openid email
OIDC_CA_URL=https://ca.example.com
OIDC_CA_PROVISIONER=oidc
OIDC_CA_MODE=api              # "api" (curl直接) ※ "step" は将来対応
OIDC_CERT_LIFETIME=3600       # 秒
OIDC_CERT_DIR=~/.ssh/oidc-certs
OIDC_AUTH_MODE=auto            # auto|prefer|only|disabled
```

`OIDC_AUTH_MODE`:

- `auto` -- away時にsk keyファイルが存在しなければOIDCを試行。OIDC失敗時はフォールバックなし（sk keyがないため）
- `prefer` -- away時にOIDCを優先。exit 2（ネットワーク/CA障害）のみsk keyへフォールバック。exit 1（設定/依存関係エラー）や exit 3（認証拒否）はフォールバックなし
- `only` -- OIDCのみ（フォールバックなし、失敗時エラー終了）
- `disabled` -- OIDC無効

## 新規関数一覧

1. **`check_oidc_dependencies()`** -- `jq`, `curl` 存在確認
2. **`validate_oidc_urls()`** -- `OIDC_ISSUER` と `OIDC_CA_URL` が `https://` スキームであることを検証。違反時はエラー終了。`ssh_with_oidc()` の先頭で呼び出す（`--oidc` フラグで `OIDC_ENABLED=false` のまま起動した場合にも確実に検証）
3. **`oidc_discover(issuer_url)`** -- `.well-known/openid-configuration` から `device_authorization_endpoint`, `token_endpoint` 取得。取得したエンドポイントURLが `OIDC_ISSUER` と同一オリジン（scheme://host:port）に属することを検証（Token Relay 攻撃防止）
4. **`oidc_device_authorize()`** -- Device Authorization Request → `user_code`, `verification_uri` 表示
5. **`oidc_poll_token()`** -- ポーリングでトークン取得 (RFC 8628準拠)。`current_interval = max(5, server_interval)` でクライアント側最小5秒を強制。`slow_down` 時は `current_interval += 5`（最小5秒適用済みの値に加算）。最大タイムアウトは `expires_in` 値（デフォルト300秒）。タイムアウト到達時は exit 3（フォールバック禁止。`slow_down` 誘発によるForced Downgrade防止）。テスト用に `_OIDC_POLL_INTERVAL_OVERRIDE` と `_OIDC_POLL_TIMEOUT_OVERRIDE` 環境変数でオーバーライド可能（`_OVERRIDE=0` は即時終了）
6. **`oidc_get_certificate()`** -- ID token → CA に送信 → SSH証明書取得。token は `printf 'Authorization: Bearer %s' "$token" | curl -H @- ...` でstdin渡し（`/proc/<pid>/cmdline` 漏洩防止）
7. **`oidc_check_cached_cert()`** -- 証明書ファイル **と** 対応する秘密鍵ファイルの両方の存在確認 + `ssh-keygen -L` で証明書有効期限チェック
8. **`ssh_with_oidc(hostname, dry_run, ssh_options...)`** -- 内部フロー後述
9. **`should_use_oidc()`** -- OIDC使用判定ロジック（後述）

## `ssh_with_oidc()` 内部フロー

```bash
ssh_with_oidc() {
    local hostname="$1" dry_run="$2"; shift 2; local ssh_options=("$@")

    # 1. 前提条件チェック
    check_oidc_dependencies || return 1
    validate_oidc_urls || return 1

    # 2. 証明書ディレクトリ準備
    ensure_oidc_cert_dir || return 1

    # 3. キャッシュチェック
    if oidc_check_cached_cert; then
        log_info "Using cached OIDC certificate"
    else
        # 4. OIDC認証フロー
        oidc_discover "$OIDC_ISSUER" || return 2
        oidc_device_authorize || return 2
        oidc_poll_token || return $?  # exit 2 or 3
        oidc_get_certificate || return 2
        log_info "SSH certificate obtained successfully"
    fi

    # 5. 一時SSH config生成 + 接続
    local temp_config
    temp_config=$(umask 077 && mktemp) || return 1
    trap 'rm -f "$temp_config"' RETURN INT TERM
    # ... config生成 + ssh 実行 (INT/TERM trap 内では exit を呼ぶ)
}
```

## `should_use_oidc()` 判定ロジック

```bash
should_use_oidc() {
    [ "$FORCE_OIDC" = true ] && return 0
    [ "$OIDC_ENABLED" = "true" ] || return 1
    case "$OIDC_AUTH_MODE" in
        only|prefer) return 0 ;;
        auto) [ ! -f "$SECURITY_KEY_PATH" ] && return 0; return 1 ;;
        disabled|*) return 1 ;;
    esac
}
```

## main() への統合

```bash
# away ブランチ内
if should_use_oidc; then
    local oidc_exit_code=0
    ssh_with_oidc "$hostname" "$dry_run" "${ssh_options[@]}" || oidc_exit_code=$?

    if [ "$oidc_exit_code" -ne 0 ]; then
        # --oidc / only / auto: フォールバックなし
        if [ "$FORCE_OIDC" = true ] || [ "$OIDC_AUTH_MODE" = "only" ] || [ "$OIDC_AUTH_MODE" = "auto" ]; then
            log_error "OIDC authentication failed (exit $oidc_exit_code)"
            exit "$oidc_exit_code"
        fi
        # prefer: exit 2 (ネットワーク/CA障害) のみフォールバック
        if [ "$OIDC_AUTH_MODE" = "prefer" ] && [ "$oidc_exit_code" -eq 2 ]; then
            log_warn "OIDC network/CA error, falling back to security key"
            ssh_from_away "$hostname" "$dry_run" "${ssh_options[@]}"
        else
            log_error "OIDC authentication failed (exit $oidc_exit_code)"
            exit "$oidc_exit_code"
        fi
    fi
else
    ssh_from_away "$hostname" "$dry_run" "${ssh_options[@]}"
fi
```

## Exit Codes

| Code | 意味                                                             |
| ---- | ---------------------------------------------------------------- |
| 0    | 成功                                                             |
| 1    | 一般エラー（依存関係不足、設定不正、URL検証失敗等）              |
| 2    | ネットワーク/CAエラー（Discovery失敗、CA API失敗）               |
| 3    | 認証拒否/タイムアウト（`access_denied`, `expired_token`, ポーリングタイムアウト） |

## CLIオプション

`--oidc` フラグ追加:

- ネットワーク判定・`OIDC_AUTH_MODE` 設定を両方オーバーライド
- フォールバックなし、失敗時は exit code でエラー終了
- 内部的に `FORCE_OIDC=true` を設定
- 引数パース: `main()` 内の `-*` キャッチオール（L765-767）より前に `--oidc)` ケースを追加。トップレベル `case`（L971-981）にも `--oidc` を追加し `main()` に委譲

## 依存関係

- `jq` (新規必須) -- JSONパース
- `curl` (既存) -- HTTPリクエスト
- `ssh-keygen` (既存) -- 鍵生成・証明書検証

※ `step` CLI 対応 (`OIDC_CA_MODE=step`) は将来対応。初期実装は `api` モードのみ。

## セキュリティ

- ID token はシェル `local` 変数のみ。curl へは bash 組み込み `printf 'Authorization: Bearer %s' "$token" | curl -H @- ...` でstdin渡し。smart-ssh は `#!/bin/bash` shebang のため `printf` は組み込みコマンドとして実行され、外部プロセスを生成しない（`/proc/<pid>/cmdline` 漏洩なし）
- `OIDC_ISSUER` と `OIDC_CA_URL` は `https://` スキーム必須。`validate_oidc_urls()` で検証（`ssh_with_oidc()` 先頭で呼出）
- Discovery レスポンスのエンドポイントURLが `OIDC_ISSUER` と同一オリジン（scheme://host:port）に属することを検証（Token Relay 攻撃防止）
- 一時SSHコンフィグは `umask 077 && mktemp` でサブシェル内で作成（TOCTOU 排除）
- 証明書ディレクトリ: `~/.ssh/` が存在しない場合は `mkdir -m 700 ~/.ssh` を先に実行。`OIDC_CERT_DIR` は `mkdir -m 700` で作成。既存パスがシンボリックリンクでないことを `-L` で確認
- ポーリングインターバル: クライアント側最小5秒を強制（DoS防止）
- ポーリングタイムアウト: exit 3 扱い（フォールバック禁止。`slow_down` 誘発による Forced Downgrade 防止）
- curl: すべてのリクエストに `--fail --max-time 30 --connect-timeout 10` を付与（無限ブロック防止）
- `--debug` 出力: ID token は **表示しない**（長さのみ表示）。`OIDC_CLIENT_ID` は先頭8文字 + マスク
- 期限切れの証明書・鍵ペアは新規取得時に上書き
- フォールバック制御: `auto` モードはフォールバックなし（sk keyがないため意味がない）。`prefer` モードは exit 2 のみフォールバック。exit 1/3 はフォールバック禁止

## `load_config()` 拡張

既存の `case` 文に OIDC キーを追加。`OIDC_CERT_DIR` は `SECURITY_KEY_PATH` と同様に `~` を `$HOME` に展開する処理を適用。

## 実装フェーズ

1. 設定基盤 -- `load_config` OIDC キー追加、デフォルト値、`init_config` テンプレート
2. OIDCコア -- `oidc_discover`（オリジン検証含む）, `oidc_device_authorize`, `oidc_poll_token`（最小インターバル強制）
3. 証明書取得 -- `oidc_get_certificate`（stdin token渡し）, `oidc_check_cached_cert`（鍵+証明書チェック）
4. SSH統合 -- `ssh_with_oidc`（umask 077 mktemp）, `should_use_oidc`, `main()`（exit code別フォールバック）, `validate_oidc_urls`
5. CLI/UX -- `--oidc` オプション（引数パース順序注意）、`usage()` 更新、補完スクリプト更新
6. テスト -- 後述の Testing Strategy に従う
7. ドキュメント -- README更新

## Considerations & Constraints

- `date` コマンドの macOS/Linux 互換性 → `ssh-keygen -L` の出力からエポック秒に変換する際、macOS (`date -jf`) と Linux (`date -d`) を分岐
- ポーリング中の Ctrl+C シグナルハンドリング
- ProxyJump との組み合わせ（`ssh_from_away()` のロジック再利用）
- CA側のセットアップはスコープ外（ドキュメントで案内）
- `step` CLI モードは将来対応（初期実装は `api` モードのみ）

## Testing Strategy

### 設定・初期化

- 設定パース・デフォルト値のユニットテスト（`OIDC_CERT_DIR` の `~` 展開含む）
- `validate_oidc_urls()`: https:// → exit 0 / http:// → exit 1 / 空文字列 → exit 1
- `check_oidc_dependencies()`: jq有無 + curl有無のテスト

### 判定ロジック

- `should_use_oidc()`: `OIDC_AUTH_MODE` 4値 x sk key 有無 2状態 = 8ケース + `--oidc` フラグによるオーバーライド（`OIDC_ENABLED=false` でも `FORCE_OIDC=true` なら true）

### OIDCコア

- `oidc_discover()`: curl モック + オリジン検証テスト（同一オリジン OK / scheme不一致 NG / host不一致 NG / port不一致 NG）。各失敗時の exit code = 2 を検証。malformed JSON / 空ボディ / 必須フィールド欠落のエラーハンドリングテスト
- `oidc_poll_token()`: `_OIDC_POLL_INTERVAL_OVERRIDE=0`, `_OIDC_POLL_TIMEOUT_OVERRIDE=2` で高速テスト。RFC 8628 エラーコード別テスト:
  - `authorization_pending` → 再試行
  - `slow_down` → インターバル増加（最小5秒強制も確認）
  - `expired_token` → exit 3
  - `access_denied` → exit 3
  - タイムアウト到達 → exit 3
  - `_OIDC_POLL_TIMEOUT_OVERRIDE=0` → 即時 exit 3
- `oidc_get_certificate()`: curl モック。CA API 成功/失敗の exit code 検証（0/2）。CAレスポンスボディの検証（証明書PEM存在確認）テスト含む。token安全性は `#!/bin/bash` shebang による組み込み printf で保証（外部プロセスが生成されないため cmdline 検証テストは不要）。証明書・秘密鍵ファイルは `umask 077` 下で作成されることをテスト

### 証明書キャッシュ

- `oidc_check_cached_cert()`: 有効/期限切れ/ファイル欠損(証明書なし)/ファイル欠損(秘密鍵なし) の4ケース。`ssh-keygen -L` 出力はヒアドキュメントでモック。macOS/Linux の日付フォーマット差異は CI matrix で検証

### CLI・統合

- `--oidc` フラグ: exit code 検証（0/1/2/3）
- `--debug` でのOIDC情報表示テスト（ID token 非表示、CLIENT_ID マスク確認）
- `--dry-run --oidc hostname`: bats自動テスト（curl モック + `OIDC_ENABLED=true`）

### フォールバック

- `auto` モード + OIDC失敗 → フォールバックなし（exit code そのまま）
- `prefer` モード + exit 2 → フォールバック発生
- `prefer` モード + exit 1 → フォールバックなし
- `prefer` モード + exit 3 → フォールバックなし
- `only` モード + 任意の失敗 → フォールバックなし

### CI

- GitHub Actions: `os: [ubuntu-latest, macos-latest]` マトリクス

## 検証方法

1. `bats tests/test_smart_ssh.bats` -- 全テスト通過確認
2. `./smart-ssh --debug` -- OIDC設定が表示されること（ID token 非表示、シークレットはマスク）
3. `./smart-ssh --dry-run --oidc hostname` -- ドライランでOIDC証明書パスが表示されること（stderr出力）
4. 実環境テスト: step-ca + Google/Keycloak OIDC で実際にDevice Flow → SSH接続
