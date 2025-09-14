# nuro プロジェクト解析メモ（temporary）

## 概要（全体でどういうアプリか）
- PowerShell スクリプトを“バケツ（bucket）”から取得・実行する、Scoop 風の極小ランナー。
- 初期導入は PowerShell ブートストラップで行い、最終的には `~/.nuro/venv` の Python モジュール `nuro`（`python -m nuro` / `nuro`）にディスパッチする設計。
- コマンドスクリプトの所在（GitHub/raw/local）をローカルのレジストリ（JSON）で管理し、pin/優先度で解決、必要に応じてダウンロード・検証・実行。

## 現在ある機能
- バケット/ピン管理（cmds/bucket.ps1）
  - 追加/一覧/削除、コマンドごとの pin/unpin、優先度。保存先は `~/.nuro/config/buckets.json`。
  - URI 形式: `github::owner/repo@ref` / `raw::https://base` / `local::<abs>` / 素のパスは local 扱いに自動補正。
- リモート取得（cmds/get.ps1）
  - `Invoke-WebRequest` による取得、`-Sha256` 検証、上書き制御、タイムアウト。
- 時刻表示（cmds/time.ps1）
  - ローカル/UTC の時刻を任意フォーマットで出力。
- Python3 検知/案内（cmds/install_python3_if_needed.ps1）
  - 主に Windows のレジストリから検知。非 Windows はガイダンスのみ。
- ブートストラップ実装（bootstrap/nuro.ps1）
  - 既に venv があれば `python -m nuro` へ委譲。無い場合も PowerShell 単体でコマンド解決・実行（bucket/pin、GitHub API から usage 収集を含む）。
- 初期化・配布用ワンライナー（bootstrap/get.nuro.ps1）
  - システム Python もしくは `uv` で venv 構築、チャネル（prod/test/dev）ごとのインストール、shim 作成、PATH 追記、疎通検証。
- ラッパー自動生成（tools/Create-NuroWrappers.ps1）
  - 任意の ps1 群（例: `limbo`）から nuro 規格の `NuroUsage_*`/`NuroCmd_*` ラッパーを生成。
- ユーティリティ群（limbo / private-scripts）
  - 例: `Show-AdminTools.ps1`（管理ツール起動 UI）、`port-open.ps1`（防火壁ルール作成）、`pgres2d.ps1`（Docker で PostgreSQL リストア）、`nascp_progress*.ps1`（SFTP 転送）など。

## 今後の方向性（推測）
- Python CLI への移行/強化
  - `nuro/nuro/cli.py` は現状プレースホルダー（"hello from nuro" のみ）。PowerShell 側が実用機能を持ち、Python 実装への置き換え・拡充が進む見込み。
- 公式バケットの外部化
  - 既定バケットが `github::mr-certain-a/nuro@<ref>` を指す構成。リモート配布/更新前提の運用強化。
- 既存 PowerShell 資産の取り込み
  - `tools/Create-NuroWrappers.ps1` により `limbo` 等の資産を nuro コマンド化し、リモート配布可能に。

## 操作方法（現時点）
- 初期化
  - PowerShell: `pwsh -f bootstrap/get.nuro.ps1 -Channel prod`
  - `-Channel dev` 時は `Repo`/`Branch`/`NURO_REF` で取得元を調整可。完了後、`~/.nuro/venv` と `~/.nuro/bin/nuro.cmd` が整備され PATH へ追加。
- 基本コマンド例
  - `nuro get -Url https://example.com/file.zip -Sha256 <hex> [-OutFile <path>] [-Force]`
  - `nuro time [-Utc] [-Format yyyy-MM-ddTHH:mm:ss.fffK]`
  - `nuro bucket ls`
  - `nuro bucket add <path|github::owner/repo@ref|raw::https://base> [name] [priority]`
  - `nuro bucket pin <command> <bucketName>` / `nuro bucket unpin <command>`
- デバッグ
  - `NURO_DEBUG=1` で詳細ログ（ロードや pin 状態など）。

## 環境設定/リポジトリ情報（ローカルで確認できる範囲）
- Git リモート/ブランチ（.git/config から）
  - origin: `https://github.com/nor-void/nuro.git`
  - ブランチ: `main`, `develop`, `codex`
  - HEAD: `.git/HEAD` は `refs/heads/codex` → 現在ローカル HEAD は `7814f457...`（refs ファイルより）
  - 備考: 実行環境では git の safe.directory 制約によりコマンドは未実行（設定ファイルの直接参照で確認）。
- Codex CLI 設定
  - `codex.approval.json`: `approvalMode: full-access`
  - `codex.approval.json.ask-on-write`: `approvalMode: ask-on-write`
- ログ
  - `logs/meg-NURO-*.log` が存在（動作履歴の痕跡）。

## 主要 ps1 の役割
- `bootstrap/nuro.ps1`: ランチャー兼 PowerShell 実装（bucket/pin、引数解析、GitHub API 経由の usage 収集）。
- `bootstrap/get.nuro.ps1`: 初期インストーラ（venv 構築、nuro インストール、shim/PATH、検証）。
- `cmds/get.ps1`: リモート取得（保存先推定、フォルダ作成、SHA256 検証、上書き制御）。
- `cmds/bucket.ps1`: バケットレジストリ管理（add/ls/rm/pin/unpin）。
- `cmds/time.ps1`: 日時出力ユーティリティ。
- `cmds/install_python3_if_needed.ps1`: Windows の Python3 検知とインストールガイダンス。
- `lib/core.ps1`: 共通ユーティリティ（`~/.nuro` 配下のディレクトリ、保存とハッシュ検証など）。
- `tools/Create-NuroWrappers.ps1`: 既存 ps1 から nuro 互換ラッパーを自動生成。
- `limbo/*.ps1`: 取り込み候補スクリプト群（管理ツール起動、防火壁設定、PostgreSQL リストア等）。
- `private-scripts/*`: 内部向け補助（現在コミットの one-liner 生成、SFTP 転送等）。

## 補足
- Python 側は現状プレースホルダーのため、機能は主として PowerShell 実装に依存。今後は Python CLI へ機能移行/拡充が見込まれる。
- ブートストラップは外部ネットワーク到達を前提に設計されているが、本解析では実アクセスは行っていない（検証は実環境で要確認）。

