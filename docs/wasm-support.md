# Odin の標準ライブラリを Wasm で使える範囲

2026-11-18、Odin `dev-2026-11-nightly:9a69916` で確認しました。計算・メモリ上のデータ処理は広く使えます。OS やブラウザの機能は、ターゲットのホスト契約とバックエンドの実装によって範囲が決まります。

## 3種類のターゲット

| ターゲット | 主な用途 | ホストに必要なもの |
| --- | --- | --- |
| `freestanding_wasm32` | 独立した計算・変換モジュール、独自ホスト | 必要な imports と、使用するランタイムの初期化 |
| `wasi_wasm32` | Wasmtime 等で動くプログラム・ツール | WASI Preview 1、ファイルアクセス先の preopen 等 |
| `js_wasm32` | ブラウザとの連携 | `odin.js` と必要な JS/DOM/GPU API |

[公式の Wasm README](https://github.com/odin-lang/Odin/blob/master/core/sys/wasm/README.md) は、ブラウザ向けを `js_wasm32`、単独 VM 向けを WASI または freestanding と区別しています。ここで確認したのは wasm32 の3種類で、wasm64p32 は実行検証していません。

## 実行して確認したもの

[検証プログラム](../examples/wasm/stdlib/main.odin) を3ターゲットでビルドし、8つの処理群の結果を確認しました。単に import できるかではなく、実際の割り当て・変換・圧縮展開・パターン照合まで実行しています。

| 処理 | freestanding | WASI | JS |
| --- | --- | --- | --- |
| 固定バッファの `mem.Arena`、動的配列 | 成功 | 成功 | 成功 |
| `map[string]int`、`container/queue` | 成功 | 成功 | 成功 |
| `math/linalg` の正規化・逆行列 | 成功 | 成功 | 成功 |
| JSON の構造体 marshal / unmarshal | 成功 | 成功 | 成功 |
| CBOR の構造体 marshal / unmarshal | 成功 | 成功 | 成功 |
| LZ4 Block の圧縮・展開 | 成功 | 成功 | 成功 |
| 正規表現のコンパイル・マッチ | 成功 | 成功 | 成功 |
| 文字列の複製・部分文字列の検索 | 成功 | 成功 | 成功 |
| `time.now` / JS の `tick_now` | 対象外 | 成功 | 成功 |
| `os.write_entire_file` / `read_entire_file` | 対象外 | preopen 先で成功 | 対象外 |

この表は各パッケージの全 API の保証ではなく、上記の代表操作の結果です。JSON/CBOR の反射を使うため `-no-rtti` は付けていません。WASI の実行には Node.js の WASI Preview 1 を使い、JS 向けは公式 `odin.js` の imports を Node.js 上で使用しました。DOM、イベント、WebGPU の実ブラウザ上での動作はこの検証には含みません。

## freestanding の準備で必要だったこと

最初は通常の `main` だけに処理を書いたため、freestanding の生成物では処理が削除され、getter が0を返す337 Bのファイルになりました。そこで、ホストから呼ぶ `run_checks` を `@(export)` / `proc "c"` として公開しました。

それでも、`runtime.default_context()` を設定するだけでは実行時に trap しました。今回の単発検証では、Wasm allocator を通常の allocator に設定し、一時領域には明示的な Arena を用意し、`runtime._startup_runtime()` と `_cleanup_runtime()` も呼ぶことで実行できました。`base/runtime/default_temporary_allocator.odin` では freestanding のデフォルト一時 allocator が nil allocator になります。

これらは独自 entry point のライフサイクルとして管理する処理です。一般の API 呼び出しごとに起動・終了処理を繰り返すテンプレートではありません。また、整数演算だけの小さな関数に、今回の標準ライブラリ一式や初期化を持ち込む必要はありません。

## 制限されるもの・ホスト側へ委ねるもの

| 機能 | この配布版の Wasm での範囲 |
| --- | --- |
| ファイル・ディレクトリ | WASI の実装と preopen の範囲。ブラウザの通常ファイルアクセスとは異なる |
| TCP/UDP、DNS | `core:net` の Wasm 向けには未実装の backend がある。socket 操作は `.Network_Unreachable` 等を返す |
| HTTP・ブラウザの通信 | JS 側の fetch 等と独自 imports / 完了コールバックで連携する構成が必要。Odin の native socket API をそのまま使う構成とは異なる |
| OS スレッド・thread pool | JS/WASI の `core:thread` は `IS_SUPPORTED == false`。ホストの Worker 等を使う構成は別途実装が必要 |
| `core:nbio` | この版の WASI 利用例は標準ライブラリ内の型検査で失敗。native での動作確認とは区別する |
| 子プロセス・プロセス一覧等 | WASI の `core:os` 実装には `.Unsupported` を返す stub がある |
| 仮想メモリ・mmap・保護属性 | `core:mem/virtual` の fallback には空実装や失敗を返す API がある。通常の linear memory 上の allocator とは別 |
| `time.sleep` | JS 向けの `odin.js` は待機処理が空。非同期タイマーとして使わず、ホストのイベントループと連携する |
| 描画・入力・DOM | `js_wasm32` から JS ブリッジを使う。wgpu はブラウザ向け WebGPU backend がある。実ブラウザ検証は未実施 |
| C ライブラリの bindings | 同梱されていても native のライブラリを Wasm にリンクできるとは限らない。Wasm 向けビルドやホスト側の対応実装が必要 |
| 暗号 | アルゴリズムの実装有無だけで用途に適するとは判断しない。付属 README に Wasm のタイミング特性等の制約がある |

ソース上の根拠:

- [net の socket fallback](https://github.com/odin-lang/Odin/blob/master/core/net/socket_others.odin)、[DNS fallback](https://github.com/odin-lang/Odin/blob/master/core/net/dns_others.odin)
- [thread の JS/WASI 実装](https://github.com/odin-lang/Odin/blob/master/core/thread/thread_other.odin)、[プロセス操作](https://github.com/odin-lang/Odin/blob/master/core/os/process_wasi.odin)
- [仮想メモリ fallback](https://github.com/odin-lang/Odin/blob/master/core/mem/virtual/virtual_other.odin)
- [odin.js のホスト API](https://github.com/odin-lang/Odin/blob/master/core/sys/wasm/js/odin.js)、[JS の時刻処理](https://github.com/odin-lang/Odin/blob/master/core/time/time_js.odin)
- [wgpu の Wasm 条件](https://pkg.odin-lang.org/vendor/wgpu/)、[crypto README](https://github.com/odin-lang/Odin/blob/master/core/crypto/README.md)

パッケージ全体を「対応 / 非対応」と分類するだけでは不十分です。例えば `core:net` の URL 解析のようなデータ処理と socket の作成は性質が違い、`mem.Arena` と OS の reserve/commit も同じ可搬性ではありません。未検証の API は、実際に使用する呼び出しを含む最小例で確認します。

## 再実行

```sh
ODIN=/path/to/odin just test-wasm-stdlib
```

[ビルドスクリプト](../scripts/build-wasm-stdlib.mjs) は、バージョン・コマンド・imports・ビルド診断を `build/wasm-stdlib/results.json` に保存します。[実行テスト](../scripts/wasm-stdlib.test.mjs) は、freestanding の export を実際に呼び、WASI の専用一時ディレクトリ内のファイルを読み書きし、JS 向けを公式ヘルパーで起動して結果を確認します。

詳細な失敗と解決は [odin-practice スキル](../skills/odin-practice/SKILL.md) に残しています。
