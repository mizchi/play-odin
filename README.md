# play-odin

Go 経験者向けの Odin 入門記事と、手元で確かめるための実践例です。

- [ブログ草稿 — Go 風の構文から入る Odin](docs/odin-blog.md)
- [実践プラクティス集 — ビット配置、エラー、所有権、データ配置](docs/practices.md)
- [サンプルの型と契約](practice/contracts.odin)、[挙動を確かめるテスト](practice/practice_test.odin)

公式の [Getting Started](https://odin-lang.org/docs/install/) に従って Odin を用意します。検証した配布版は [dev-2026-11a](https://github.com/odin-lang/Odin/releases/tag/dev-2026-11a) の macOS ARM64 版で、`odin version` の表示は `dev-2026-11-nightly:9a69916` でした。文書の確認日は 2026-11-18 です。

```sh
just run            # 動作例
just test           # 25 テスト。リークと不正な解放も失敗にする
just test-negative  # コンパイルが拒否されるべき 4 例
just check          # -vet と本文のコード抜粋・ローカルリンクを検査
just verify         # 上の検査をまとめて実行
```

`just` と Node.js 24 以上も使います。Node.js は検査スクリプトだけで使い、追加パッケージは不要です。コンパイラの場所は `ODIN` で指定できます。

```sh
ODIN=/path/to/odin just verify
```

Wasm のサイズ測定もできます。外部依存のない加算関数、Hello World、既存の `basics` をビルドし、通常・サイズ優先・`wasm-opt` 最適化後のサイズを比較します。Hello World は `fmt`、`os.write_string`、WASI 直接呼び出し、独自の起動関数による差も測ります。`bit_set`・`bit_field`・`defer` は同じ処理の手書き版と比較します。非同期処理は JS ホストへの依頼と再開を、状態機械・コールバックの2方式で測ります。詳しい条件と実測値は [Wasm のビルドサイズ](docs/wasm-size.md) にあります。

```sh
just wasm-size  # Wasm / gzip / Brotli のバイト数を表示・保存
just test-wasm  # ビルド後に全52種類の Wasm の挙動を検証
```

Odin、`wasm-opt`、`wasm-ld`（または Zig）が必要です。`test-wasm` は Wasmtime も使います。生成物と測定レポートは `build/wasm/` に出力します。

標準ライブラリの Wasm 対応範囲は [Wasm で使える範囲](docs/wasm-support.md) にまとめています。`ODIN=/path/to/odin just test-wasm-stdlib` で、freestanding / WASI / JS 向けの計算・データ処理と、一部のホスト API を実行検証します。

Odin を書く際の失敗と解決、API の探し方は、リポジトリ内の [odin-practice スキル](skills/odin-practice/SKILL.md) にまとめています。

実用例として、標準入力の JSON Lines を集計する [ログ集計 CLI](docs/log-summary.md) があります。ネイティブ版と WASI 版の動作、最適化の実測、ビルドの調べ方を記録しています。 [Odin 側の再現メモ](docs/odin-issues.md)

`practice/` は型の定義、ビット列の変換、エラー処理、メモリ操作、データ操作をファイルごとに分けています。`examples/tour/` が利用例、`examples/compile-errors/` は意図的にコンパイルできない反例です。ビルドとテストはディレクトリを指定して実行してください。

エラー呼び出しを連鎖させる実例は、[パケット解析](practice/packets.odin)、[幅と高さの変換](practice/dimensions.odin)、[ファイルと JSON の設定読み込み](practice/settings.odin) にあります。設定ファイルのサンプルは [settings.json](examples/data/settings.json) です。`just run` はワークスペースのルートからこれらを実行します。

本文の `snippet` コメントで囲まれたコードは実ソースから取得しています。コードを変更したときは次のコマンドで抜粋を更新できます。

```sh
node scripts/check-docs.mjs --write
```

実行時の例:

```text
header: 2009, bytes: 09 20
decoded: Data true 512
doubled_count: 12 24 None
doubled_count: bad 0 Invalid_Number
doubled_count: -2 0 Negative_Number
owned counts: [3, 4]
after scratch: persistent
soa x: [11, 4]
deferred: 30
after defer scope
packet: Data abc
dimensions: 1280 720
settings: 4 1500
```
