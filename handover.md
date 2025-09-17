# 引き継ぎメモ（codex ブランチ）

## ブランチ/状態
- ブランチ: codex（origin/codex に反映済み）
- 主な変更: ランタイム解決（ps1/py/sh）、usage 表示とキャッシュ、パス構成再編、Python 依存解決、PS ブートストラップ微修正、README 更新

## コマンド解決/実行
- 拡張子優先: ps1 → py → sh
- バケット優先: bucket ヒント → pins → priority
- 取得場所: cmds/<name>.<ext>（local::<path> は <path>/cmds/<name>.<ext>）
- 実行:
  - ps1: ドットソース＋NuroCmd_<name>（ラッパーファイルは生成しない）
  - py: main(args) または main() を検出して実行（runpy＋inspect）
  - sh: bash <script> ...
- GitHub 解決: resolve_cmd_source_with_meta が sha1-hash（コミット固定）を考慮（raw/GitHub/local を集約）

## キャッシュ/パス
- スクリプト: ~/.nuro/cache/cmds/{ps1|py|sh}/<bucket>/<name>.<ext>
- usage テキスト: ~/.nuro/cache/usage/<bucket>/<name>.txt
- 旧 ~/.nuro/ps1 は廃止（--refresh 時に残骸削除）
- --refresh（引数なしの nuro 時）: cache/cmds（ps1/py/sh）と cache/usage を全削除 → 再取得
- 引数なし nuro: キャッシュ優先（キャッシュ空なら 1 回のみ GitHub で一覧取得）
- usage 表示: 固定幅 3 列（コマンド/種別/使用例）。全角幅を考慮して桁合わせ。使用例は ps1 のみ（py/sh は空欄）

## 依存関係（Python スクリプト）
- スクリプト内の __requires__ = ["pkg==ver", ...] を AST 解析で検出
- 判定最適化: ~/.nuro/cache/py-reqs.json に spec ごとの判定結果をキャッシュ（true=満たす/false=未満）
- インストール先とポリシー:
  - 必須: ~/.nuro/venv が存在すること（~/.nuro 配下以外は変更しないポリシー）
  - venv 無し: エラーを標準エラーに出力し、インストールせず実行中止（終了コード 1）
  - venv 有り: その仮想環境に -m pip install（永続化）
- 出力/ログ:
  - pip の標準出力/標準エラーは抑制
  - 実際にインストールした場合のみ、緑色 1 行で「Installed dependency: <spec>」を表示
  - 詳細は ~/.nuro/logs/nuro-debug.log（NURO_DEBUG=1 で有効）

## 設定/レジストリ
- 公式バケット既定: nuro/nuro/__init__.py の DEFAULT_OFFICIAL_BUCKET_BASE = https://raw.githubusercontent.com/nor-void/nuro
- アプリ設定: ~/.nuro/config/config.json（official_bucket_base）
- レジストリ: ~/.nuro/config/buckets.json
  - buckets[].uri: github::owner/repo@ref | raw::https://... | local::<path>
  - 任意: sha1-hash（コミット固定）、priority、trusted
  - pins: { "<cmd>": "<bucketName>" }

## PowerShell ブートストラップ（概要）
- 一覧/Usage は sha1-hash を尊重、公式バケットは raw::<base> で統一
- 取得先は cmds/<name>.ps1 前提
- ランタイムの ps1 実行は現行どおり（カレントシェル実行）

## 既知の注意点/今後候補
- py/sh の usage 表示は未対応（空欄）
- バージョン条件の厳密評価（>= など）は将来 packaging 導入で厳密化可能
- venv の用意: bootstrap/get.nuro.ps1 で ~/.nuro/venv を構築（依存導入には必須）

## 使い方（要点）
- nuro → キャッシュ優先一覧（空なら一度だけオンライン）
- nuro --refresh → キャッシュ全削除 → 最新取得 → usage 再キャッシュ
- nuro <cmd> / nuro <bucket:cmd> → ps1 → py → sh の順に最初の一致を実行
- Python 依存が必要なコマンド（例: trans.py）は ~/.nuro/venv が無いとエラー停止

