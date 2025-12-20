# smart-ssh

ローカルネットワークに基づいてSSH接続方式を自動選択するツールです。ホームネットワークからは通常の公開鍵認証、外部ネットワークからはセキュリティキー認証を使用します。

[English](README.md) | 日本語

## 特徴

- **ホーム検出**: 信頼できるホームネットワークでは通常のSSH鍵を使用
- **外出モード**: 外部ネットワークではセキュリティキー（FIDO2/WebAuthn）認証を要求
- **クロスプラットフォーム**: Linux、macOS、WSL2で動作
- **SSH設定対応**: `Include`ディレクティブや複雑なSSH設定を適切に処理
- **複数ホームネットワーク**: 異なる識別子を持つ複数のホームロケーションをサポート
- **ゲートウェイMAC検出**: ルーターのMACアドレスでホームネットワークを識別（特別な権限不要）
- **IPベースフォールバック**: MAC検出が利用できない場合のネットワークベース検出
- **カラー出力**: 色分けされたメッセージで視認性向上（`NO_COLOR`対応）
- **ドライランモード**: 接続せずに認証方式をプレビュー
- **入力検証**: IPアドレスとCIDR形式の堅牢なエラー処理
- **設定ファイル**: XDG準拠の設定ファイルサポート
- **タブ補完**: BashとZshのホスト名・オプション補完
- **テスト**: batsによる包括的なテストスイート
- **SSHオプション転送**: SSHオプション（-v、-p、-Lなど）をそのまま転送

## セキュリティモデル

- **ホームネットワーク**: 信頼できるネットワークからは通常の公開鍵認証で便利にアクセス
- **外部ネットワーク**: 信頼できないネットワークからはセキュリティキー（YubiKeyなど）による強化認証
- **サーバーサイド強制**: 実際のセキュリティはサーバー側で送信元IPに基づいて強制

## インストール

### オプション1: クイックインストール（推奨）

```bash
# /usr/local/binにダウンロードしてインストール
curl -fsSL https://raw.githubusercontent.com/ngc-shj/smart-ssh/main/smart-ssh | sudo tee /usr/local/bin/smart-ssh > /dev/null
sudo chmod +x /usr/local/bin/smart-ssh

# インストール確認
smart-ssh --help
```

### オプション2: 手動インストール

```bash
# リポジトリをクローン
git clone https://github.com/ngc-shj/smart-ssh.git
cd smart-ssh

# スクリプトをインストール
sudo cp smart-ssh /usr/local/bin/
sudo chmod +x /usr/local/bin/smart-ssh

# タブ補完をインストール（オプション）
# Bash用
sudo cp completions/smart-ssh.bash /etc/bash_completion.d/smart-ssh

# Zsh用（Homebrewユーザー）
cp completions/_smart-ssh $(brew --prefix)/share/zsh/site-functions/_smart-ssh

# インストール確認
smart-ssh --help
```

### オプション3: ユーザーローカルインストール（sudo不要）

```bash
# ローカルbinディレクトリを作成（存在しない場合）
mkdir -p ~/.local/bin

# ダウンロードしてインストール
curl -fsSL https://raw.githubusercontent.com/ngc-shj/smart-ssh/main/smart-ssh -o ~/.local/bin/smart-ssh
chmod +x ~/.local/bin/smart-ssh

# PATHに追加（まだの場合、~/.bashrcまたは~/.zshrcに追加）
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc  # または ~/.zshrc
source ~/.bashrc  # または source ~/.zshrc

# インストール確認
smart-ssh --help
```

## 設定

smart-sshは3つのレベルの設定をサポートし、以下の優先順位で適用されます:
**環境変数 > 設定ファイル > デフォルト値**

### 1. 設定ファイル（推奨）

設定を永続化するための設定ファイルを作成:

```bash
# デフォルト設定ファイルを初期化
smart-ssh --init-config

# 設定ファイルを編集
vi ~/.config/smart-ssh/config
```

設定ファイル形式（`~/.config/smart-ssh/config`）:

```bash
# ホームゲートウェイMACアドレス（カンマ区切り、優先検出方式）
# 'smart-ssh --debug'でゲートウェイMACアドレスを確認できます
HOME_GATEWAY_MAC=aa:bb:cc:dd:ee:ff,11:22:33:44:55:66

# ホームネットワーク（カンマ区切りCIDR範囲、フォールバック検出方式）
HOME_NETWORK=192.168.1.0/24,10.0.0.0/24

# セキュリティキーのパス
SECURITY_KEY_PATH=~/.ssh/id_ed25519_sk

# ログレベル（debug、info、warn、error）
LOG_LEVEL=info
```

### 2. 環境変数

環境変数で一時的に設定を上書き:

```bash
# ゲートウェイMAC（優先方式）
export HOME_GATEWAY_MAC="aa:bb:cc:dd:ee:ff"

# 複数のホームネットワーク用に複数のゲートウェイMAC
export HOME_GATEWAY_MAC="aa:bb:cc:dd:ee:ff,11:22:33:44:55:66"

# IPベースフォールバック
export HOME_NETWORK="192.168.1.0/24"

# 複数ネットワーク（カンマ区切り）
export HOME_NETWORK="192.168.1.0/24,10.0.0.0/24,172.16.0.0/12"

# 別のセキュリティキー
export SECURITY_KEY_PATH="$HOME/.ssh/id_ecdsa_sk"

# コマンドごとの上書き
HOME_GATEWAY_MAC="aa:bb:cc:dd:ee:ff" smart-ssh hostname
HOME_NETWORK="192.168.1.0/24,10.0.0.0/8" smart-ssh hostname
```

### 3. SSH設定

サーバーごとに1つのエントリでSSHホスト設定を作成:

```ssh-config
# ~/.ssh/config

# サーバー設定（単一エントリ）
Host production
    HostName production.example.com
    User myuser
    Port 22
    IdentityFile ~/.ssh/id_ed25519
    PreferredAuthentications publickey

# その他のサーバー
Host production-server
    HostName prod.company.com
    User deploy
    IdentityFile ~/.ssh/id_ed25519
```

注: 外部ネットワークからの接続時は`-i`オプションでセキュリティキーが自動的に使用されます。

### 4. SSH鍵の生成

```bash
# ホーム用の通常鍵
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519

# 外出用のセキュリティキー（ハードウェアキーが必要）
ssh-keygen -t ed25519-sk -f ~/.ssh/id_ed25519_sk

# 公開鍵をサーバーにコピー
ssh-copy-id -i ~/.ssh/id_ed25519.pub production
ssh-copy-id -i ~/.ssh/id_ed25519_sk.pub production
```

### 5. サーバーサイド設定（強く推奨）

真のセキュリティのため、送信元IPに基づいて認証方式と鍵アルゴリズムを強制するようサーバーを設定:

```bash
# /etc/ssh/sshd_config.d/99-smart-ssh.conf

# Smart-SSH セキュリティキー設定
# Matchブロックは上から下へ処理され、最初にマッチしたものが適用

# 信頼できるネットワーク: 通常の公開鍵 + セキュリティキーアルゴリズム
Match Address 192.168.1.0/24,10.0.0.0/8,127.0.0.1,::1
    PubkeyAcceptedAlgorithms ssh-ed25519,ecdsa-sha2-nistp256,sk-ssh-ed25519@openssh.com,sk-ecdsa-sha2-nistp256@openssh.com
    PubkeyAuthOptions none
    AuthenticationMethods publickey

# その他すべてのアドレス: セキュリティキーアルゴリズムのみ
Match all
    PubkeyAcceptedAlgorithms sk-ssh-ed25519@openssh.com,sk-ecdsa-sha2-nistp256@openssh.com
    PubkeyAuthOptions touch-required
    AuthenticationMethods publickey
```

設定を適用:

```bash
sudo sshd -t  # 設定をテスト
sudo systemctl reload sshd  # 変更を適用
```

**重要**: IPアドレスを実際のホームネットワークとISP範囲に合わせて更新してください。`curl -4 ifconfig.co`でパブリックIPを確認し、CIDR範囲を調査してください。

## 使い方

```bash
# 初回セットアップ: 設定ファイルを作成
smart-ssh --init-config

# 設定とネットワーク情報を表示（ゲートウェイMAC、IPなど）
smart-ssh --debug

# サーバーに接続（ホーム/外出を自動検出）
smart-ssh production

# SSHオプションを渡す（詳細モード）
smart-ssh production -v

# カスタムSSHポートを使用
smart-ssh production -p 2222

# SSHオプションでポートフォワーディング
smart-ssh production -L 8080:localhost:80

# 複数のSSHオプション
smart-ssh production -v -p 2222 -L 8080:localhost:80

# --でsmart-sshとSSHオプションを明確に分離
smart-ssh --dry-run -- production -v -p 2222

# ネットワークに関係なくセキュリティキー認証を強制
smart-ssh --security-key bastion
smart-ssh -s web-server

# ドライランモード（接続せずに実行コマンドをプレビュー）
smart-ssh --dry-run production
smart-ssh -n staging

# 一時的に別のセキュリティキーを使用
SECURITY_KEY_PATH=~/.ssh/id_ecdsa_sk smart-ssh --security-key dev-server

# 一時的にホームネットワーク検出を上書き
HOME_GATEWAY_MAC="aa:bb:cc:dd:ee:ff" smart-ssh staging
HOME_NETWORK="192.168.1.0/24,10.0.0.0/8" smart-ssh staging

# カラー出力を無効化
NO_COLOR=1 smart-ssh production

# デバッグモード（設定とネットワーク情報を表示）
smart-ssh --debug

# ヘルプ
smart-ssh --help
```

## ネットワーク検出方式

smart-sshは以下の検出方式を優先順位順に使用します:

| 優先度 | 方式        | 説明                                     |
|--------|-------------|------------------------------------------|
| 1      | Gateway MAC | ARP経由のルーターMACアドレス（権限不要） |
| 2      | IPアドレス  | CIDR範囲マッチング（フォールバック）     |

### ゲートウェイMAC検出（推奨）

ゲートウェイMAC検出は、ルーターのMACアドレスでホームネットワークを識別します。この方式は:

- 特別な権限なしで動作
- 異なるIP設定でも信頼性が高い
- 複数のホームネットワークをサポート

ゲートウェイMACアドレスを確認するには:

```bash
smart-ssh --debug
# "Gateway MAC: xx:xx:xx:xx:xx:xx"を探す
```

## プラットフォームサポート

| プラットフォーム | Gateway MAC         | IP検出                           |
|------------------|---------------------|----------------------------------|
| macOS            | `arp -n`            | `route get default` + `ifconfig` |
| Linux            | `ip neigh` or `arp` | `ip route` or `ifconfig`         |
| WSL2             | N/A                 | PowerShell `Get-NetIPAddress`    |

## 使用例ワークフロー

1. **自宅（ゲートウェイMACが一致）**: 通常のSSH鍵で接続（タッチ不要）
2. **カフェ（異なるゲートウェイ）**: セキュリティキーで接続（YubiKeyタッチ必要）
3. **セキュリティキー強制**: `--security-key`オプションで常にセキュリティキーを使用
4. **不明なネットワーク**: 認証方式を手動で選択するようプロンプト

### 実際のシナリオ

- `smart-ssh production` - 本番サーバーにデプロイ
- `smart-ssh dev-server` - 開発環境に接続
- `smart-ssh bastion` - 内部ネットワークへのジャンプホストにアクセス
- `smart-ssh web-server` - Webサーバーを管理

## セキュリティの利点

- **自宅での利便性**: 信頼できるネットワークからのルーチンアクセスでセキュリティキーのタッチが不要
- **外出時の強力なセキュリティ**: 外部ネットワークからの必須ハードウェア認証により鍵盗難攻撃を防止
- **アルゴリズム強制**: サーバーサイドのアルゴリズム制限により弱い鍵攻撃を防止
- **ネットワークベース検出**: ゲートウェイMACとIPベースの検出で信頼性の高い識別
- **フィッシング耐性**: セキュリティキーがサーバーIDの暗号学的証明を提供
- **物理的存在**: タッチ要件により鍵への物理的アクセスを確保

## タブ補完

smart-sshはbashとzshシェルのタブ補完をサポートしています。

### Bash補完

```bash
# システム全体にインストール
sudo cp completions/smart-ssh.bash /etc/bash_completion.d/smart-ssh

# または現在のユーザー用にインストール
mkdir -p ~/.local/share/bash-completion/completions
cp completions/smart-ssh.bash ~/.local/share/bash-completion/completions/smart-ssh

# または~/.bashrcで直接source
echo "source $(pwd)/completions/smart-ssh.bash" >> ~/.bashrc
source ~/.bashrc
```

### Zsh補完

```bash
# Homebrewユーザー向け（推奨）
cp completions/_smart-ssh $(brew --prefix)/share/zsh/site-functions/_smart-ssh

# またはシステムディレクトリにインストール
sudo cp completions/_smart-ssh /usr/local/share/zsh/site-functions/_smart-ssh

# またはカスタム補完ディレクトリに追加
mkdir -p ~/.zsh/completions
cp completions/_smart-ssh ~/.zsh/completions/
echo 'fpath=(~/.zsh/completions $fpath)' >> ~/.zshrc
echo 'autoload -Uz compinit && compinit' >> ~/.zshrc
source ~/.zshrc
```

**機能**:

- `~/.ssh/config`からホスト名を補完（`Include`ディレクティブを含む）
- すべてのコマンドラインオプションを補完
- 組み合わせオプションで動作（例: `-s hostname`）
- コンテキスト認識補完: ホスト名の前はsmart-sshオプション、後はSSHオプション

### SSHエイリアスとして使用

`smart-ssh`を`ssh`の代替として使用できます:

```bash
# Bash (~/.bashrc)
if command -v smart-ssh >/dev/null 2>&1; then
    alias ssh='smart-ssh'
    # エイリアスに対して補完を有効化
    complete -F _smart_ssh_completion ssh
fi

# Zsh (~/.zshrc)
if (( $+commands[smart-ssh] )); then
    alias ssh='smart-ssh'
    # エイリアスに対して補完を有効化
    compdef _smart-ssh ssh
fi
```

注意: 上記のタブ補完スクリプトを先にインストールしてから、シェルのrcファイルにエイリアス設定を追加してください。

## テスト

smart-sshは[bats](https://github.com/bats-core/bats-core)を使用した包括的なテストスイートを含んでいます。

### batsのインストール

```bash
# macOS
brew install bats-core

# Linux（ソースから）
git clone https://github.com/bats-core/bats-core.git
cd bats-core
sudo ./install.sh /usr/local
```

### テストの実行

```bash
# すべてのテストを実行
bats tests/test_smart_ssh.bats

# 詳細出力で実行
bats -t tests/test_smart_ssh.bats

# 特定のテストを実行
bats -f "validate IP" tests/test_smart_ssh.bats
```

**テストカバレッジ**:

- 設定ファイルの作成と解析
- IPアドレスとCIDR検証
- 環境変数の優先順位
- コマンドラインオプションの処理
- ドライランモード
- デバッグモード
- ヘルプと使用方法の出力

## 要件

- セキュリティキーサポート付きSSHクライアント（OpenSSH 8.2+）
- 外出時接続用のハードウェアセキュリティキー（YubiKeyなど）
- オプション: テスト実行用のbats-core

## トラブルシューティング

### ネットワーク検出の問題

**問題**: smart-sshがネットワークを検出できない

**解決策**:

1. デバッグモードで何が起きているか確認:

   ```bash
   smart-ssh --debug
   ```

2. ゲートウェイMACとIPを確認:

   ```bash
   # macOS
   route -n get default
   arp -n $(route -n get default | grep gateway | awk '{print $2}')

   # Linux
   ip route show default
   ip neigh show $(ip route show default | awk '/default/ {print $3}')
   ```

3. ルーターのMACアドレスでHOME_GATEWAY_MACを設定:

   ```bash
   # 設定ファイルに
   HOME_GATEWAY_MAC=aa:bb:cc:dd:ee:ff
   ```

**問題**: 自宅にいるのにホームネットワークが検出されない

**解決策**:

1. ゲートウェイMACまたはIPが設定と一致しているか確認:

   ```bash
   smart-ssh --debug
   # "Gateway MAC"と"Current IP"を設定値と比較
   ```

2. 設定を更新:

   ```bash
   # 設定ファイルを編集
   vi ~/.config/smart-ssh/config

   # または環境変数を使用
   export HOME_GATEWAY_MAC="aa:bb:cc:dd:ee:ff"
   ```

### セキュリティキーの問題

**問題**: "Security key file not found"

**解決策**:

1. セキュリティキーを生成:

   ```bash
   ssh-keygen -t ed25519-sk -f ~/.ssh/id_ed25519_sk
   ```

2. キーパスを確認:

   ```bash
   ls -l ~/.ssh/id_ed25519_sk*
   ```

3. 必要に応じてSECURITY_KEY_PATHを更新:

   ```bash
   # 設定ファイルに
   SECURITY_KEY_PATH=~/.ssh/id_ecdsa_sk

   # または環境変数
   export SECURITY_KEY_PATH=~/.ssh/id_ecdsa_sk
   ```

**問題**: "Please touch your YubiKey"と表示されるが何も起きない

**解決策**:

1. セキュリティキーが接続されていることを確認
2. キーを抜き差ししてみる
3. USBポートの権限を確認（Linux）:

   ```bash
   sudo chmod a+rw /dev/usb/*
   ```

4. sshで直接キーが動作するか確認:

   ```bash
   ssh -i ~/.ssh/id_ed25519_sk hostname
   ```

### SSH設定の問題

**問題**: "SSH configuration for 'hostname' not found"

**解決策**:

1. SSH設定ファイルの存在を確認:

   ```bash
   ls -l ~/.ssh/config
   ```

2. ホストエントリの存在を確認:

   ```bash
   grep "^Host " ~/.ssh/config
   ```

3. ホストエントリを作成:

   ```ssh-config
   Host production
       HostName prod.example.com
       User myuser
       IdentityFile ~/.ssh/id_ed25519
   ```

### 設定ファイルの問題

**問題**: 設定ファイルが読み込まれない

**解決策**:

1. ファイルの場所を確認:

   ```bash
   ls -l ~/.config/smart-ssh/config
   ```

2. ファイル構文を確認（`=`の周りにスペースなし）:

   ```bash
   # 正しい
   HOME_GATEWAY_MAC=aa:bb:cc:dd:ee:ff

   # 間違い
   HOME_GATEWAY_MAC = aa:bb:cc:dd:ee:ff
   ```

3. 設定ファイルを再作成:

   ```bash
   smart-ssh --init-config
   ```

### 無効なCIDR形式エラー

**問題**: "Error: Invalid CIDR format"

**解決策**:

1. 適切なCIDR表記を使用:

   ```bash
   # 正しい
   HOME_NETWORK=192.168.1.0/24

   # 間違い
   HOME_NETWORK=192.168.1
   HOME_NETWORK=192.168.1.0
   ```

2. マスクビットが0-32であることを確認:

   ```bash
   # 有効
   10.0.0.0/8
   192.168.0.0/16
   192.168.1.0/24

   # 無効
   192.168.1.0/33
   ```

### ドライランモード

接続せずにテストするにはドライランモードを使用:

```bash
smart-ssh --dry-run production
```

これにより実行されるコマンドが正確に表示されます。

### デバッグログの有効化

詳細出力のためにLOG_LEVELをdebugに設定:

```bash
# 設定ファイルに
LOG_LEVEL=debug

# または環境変数
LOG_LEVEL=debug smart-ssh production
```

### まだ問題がある場合

1. デバッグモードを実行してすべての設定を確認:

   ```bash
   smart-ssh --debug
   ```

2. 環境変数の上書きでテスト:

   ```bash
   HOME_GATEWAY_MAC="aa:bb:cc:dd:ee:ff" smart-ssh --dry-run production
   ```

3. Issue報告: <https://github.com/ngc-shj/smart-ssh/issues>

## 作者

NOGUCHI Shoji ([@ngc-shj](https://github.com/ngc-shj))

## ライセンス

MIT License - 詳細は[LICENSE](LICENSE)を参照してください。
