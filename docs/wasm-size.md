# Odin の Wasm ビルドサイズ

2026-11-18 に macOS ARM64 で測定しました。外部依存のない関数は164 B、`core:fmt` と WASI を使う Hello World は160,845 B でした。同じ文字列をフォーマットせず出すと24,581 B、WASI を直接呼ぶと15,031 B、通常の起動処理も省くと660 B になりました。ここで測るのはファイルのバイト数で、実行時メモリの使用量ではありません。

## 対象とビルド条件

- [add](../examples/wasm/add/main.odin): `i32` の加算を C ABI で公開。`freestanding_wasm32`、`-no-entry-point`。ホストからの import は不要です。
- [hello](../examples/wasm/hello/main.odin): `core:fmt` で `Hello, Odin!` を出力。`wasi_wasm32`。
- [basics](../examples/basics/main.odin): 配列の合計を計算して `14` を出力。`wasi_wasm32`。
- [hello-os](../examples/wasm/hello-os/main.odin): `os.write_string(os.stdout, ...)` で同じ文字列を出力。`wasi_wasm32`。
- [hello-wasi](../examples/wasm/direct-write/main.odin): `core:sys/wasm/wasi` の `fd_write` を直接呼ぶ。通常の `main` を持つ `wasi_wasm32`。
- [hello-wasi-minimal](../examples/wasm/direct-write/main.odin): hello-wasi と同じ書き込み処理を独自の `_start` から呼ぶ。`freestanding_wasm32`、`-no-entry-point`。WASI Preview 1 の import を持ち、Wasmtime で動作します。
- [bit-set](../examples/wasm/features/bit-set/main.odin)、[bit-field](../examples/wasm/features/bit-field/main.odin)、[defer](../examples/wasm/features/defer/main.odin): 各機能と同じ処理の手書き版を比較する6例。すべて `freestanding_wasm32`、`-no-entry-point`。
- [async-state / async-callback](../examples/wasm/async-host/main.odin): JS ホストに処理を依頼して、2回中断・再開する実装。状態機械と継続関数の2方式。`freestanding_wasm32`、`-no-entry-point`。

`minimal` はデフォルトの `-o:minimal`、`size` は `-o:size` です。`no-rtti` は `-o:size -no-rtti` で、今回の Odin では freestanding 専用です。今回の freestanding の例ではサイズ改善はありませんでした。

`optimized` は、freestanding の10例では `no-rtti`、`wasi_wasm32` の4例では `size` の生成物に次の処理を適用したものです。

```sh
wasm-opt input.wasm -Oz --strip-debug --strip-producers -o output.wasm
```

境界チェックや assert を無効化するフラグは使っていません。圧縮は Node.js 標準の zlib で gzip level 9 と Brotli quality 11 を指定しています。

## 実測値

単位はすべて B です。1 KiB = 1,024 B。

| プログラム | 設定 | Wasm | gzip | Brotli |
| --- | --- | ---: | ---: | ---: |
| add | minimal | 285 | 245 | 200 |
| add | size | 268 | 233 | 187 |
| add | no-rtti | 271 | 234 | 192 |
| add | optimized | 164 | 156 | 129 |
| hello | minimal | 420,045 | 231,224 | 164,278 |
| hello | size | 199,300 | 87,287 | 72,906 |
| hello | optimized | 160,845 | 80,380 | 67,787 |
| basics | minimal | 420,211 | 231,316 | 164,551 |
| basics | size | 199,301 | 87,288 | 72,719 |
| basics | optimized | 160,837 | 80,369 | 67,920 |
| hello-os | minimal | 119,803 | 56,504 | 43,326 |
| hello-os | size | 31,687 | 13,081 | 11,071 |
| hello-os | optimized | 24,581 | 11,541 | 9,798 |
| hello-wasi | minimal | 41,106 | 20,116 | 16,281 |
| hello-wasi | size | 19,986 | 8,211 | 7,100 |
| hello-wasi | optimized | 15,031 | 7,130 | 6,108 |
| hello-wasi-minimal | minimal | 3,378 | 2,135 | 1,839 |
| hello-wasi-minimal | size | 1,077 | 741 | 638 |
| hello-wasi-minimal | no-rtti | 1,080 | 742 | 646 |
| hello-wasi-minimal | optimized | 660 | 520 | 449 |

hello と basics は最適化後ほぼ同じサイズです。今回の例では、加算やループよりも `core:fmt` とランタイムを含む構成の影響が大きいと推測できます。最適化後の hello を `wasm-tools objdump` で調べると、code セクションは108,071 B、data セクションは51,434 B でした。

## フォーマット処理を避けると何が残るか

同じ `Hello, Odin!\n` を出す比較では、`fmt.println` を `os.write_string` に替えるだけで約84.7%小さくなりました。この差は `fmt` と、その利用によって必要になる依存処理を含んでいます。フォーマット処理単体のサイズを計測したものではありません。

WASI の `fd_write` を直接使っても、通常の `main` から起動する構成では15,031 B ありました。`wasm-tools print` で確認すると、引数の読み込み、標準アロケータ、一時アロケータ、乱数生成器などのコードが残っています。最適化後の import は `args_sizes_get`、`args_get`、`fd_write`、`proc_exit`、`random_get` の5個です。

同じ書き込み処理を独自の `_start` から呼び、Odin の通常の起動処理を通らない構成では660 B になりました。残る import は、標準出力用の `wasi_snapshot_preview1.fd_write` と、失敗時に終了コードを返す `wasi_snapshot_preview1.proc_exit` の2個だけです。短い書き込みの再試行とエラー処理、スライスの境界チェックも含みます。code セクションは297 B、data セクションは101 B です。

WASI の I/O 実装本体はホストが提供します。Wasm 側には import の宣言、引数の準備、呼び出し、メモリと文字列などが残ります。`fd_write` の契約は [WASI Preview 1 の仕様](https://github.com/WebAssembly/WASI/blob/a2b96e81c0586125cc4dc79a5be0b78d9a059925/legacy/preview1/docs.md#fd_write) を参照してください。

独自の `_start` は、引数のセットアップや暗黙の context の初期化、通常のグローバル初期化などを実行しません。今回の書き込み関数は `proc "contextless"` で、割り当てやグローバル初期化を必要としません。この構成を一般の `main` にそのまま置き換えることはできません。

これらは小さなサンプルの実測値であり、Odin プログラム全般の上限・下限を示すものではありません。WASI ランタイム本体やブラウザ用の JavaScript はサイズに含みません。WASI 版は `wasi_snapshot_preview1` のホスト実装が必要です。ブラウザ向けの `js_wasm32` とその補助 JavaScript は今回の測定対象に含めていません。ターゲットの使い分けは [Odin 公式の Wasm README](https://github.com/odin-lang/Odin/blob/master/core/sys/wasm/README.md) に記載されています。

## 言語機能によるサイズの増分

`bit_set`・`bit_field`・`defer` は、比較対象と同じ公開関数名・C ABI・入出力を使いました。入力はホストから渡し、`defer` の状態も公開関数から読み出すため、処理全体が定数に畳み込まれたり削除されたりする例にはなっていません。各ソースを `-define:USE_FEATURE=false` 付きでビルドすると手書き版になります。

以下は `optimized` の結果です。「全体」は各モジュールのサイズで、「増分」は同じ処理を手書きした版との差です。3組ともバイナリ全体がバイト単位で一致しました。import はすべて0個です。

| 機能 | 機能版の全体 (B) | 手書き版の全体 (B) | 増分 (B) | バイナリ一致 |
| --- | ---: | ---: | ---: | --- |
| bit_set | 205 | 205 | 0 | 完全一致 |
| bit_field | 247 | 247 | 0 | 完全一致 |
| defer | 222 | 222 | 0 | 完全一致 |

- `bit_set`: 32 bit のフラグの和集合・差集合・`.Execute in flags` を、整数の OR・AND NOT・ビット検査と比較しました。最適化後の code セクションは双方26 B です。値のデータ表現は双方4 B です。
- `bit_field`: 32 bit のヘッダの詰め込み、12 bit フィールドの取り出し、符号付き8 bit フィールドの符号拡張を、整数のマスク・シフトと比較しました。最適化後の code セクションは双方64 B です。値のデータ表現は双方4 B です。
- `defer`: スコープを抜ける際の逆順の後処理を、各 return の前に明示的に置いた処理と比較しました。早期 return と、登録後に変更される変数の評価も含めています。最適化後の code セクションは双方44 B です。

`bit_field` は最適化設定に注意が必要でした。`-o:minimal` の code セクションは機能版529 B、手書き版181 B でしたが、`-o:size` では双方64 B に縮みました。`size` や `no-rtti` のファイル全体には名前セクションが残り、出力ファイル名の `-manual` による7 B の差があります。機能のコストとメタデータの差を混同しないため、最終比較には名前情報を除去した `optimized` を使っています。

この結果から、今回の範囲では次のように分類できます。I/O の行は Hello World のモジュール全体で、機能単体の増分ではありません。別々のモジュールのサイズを足してアプリケーション全体のサイズを予測することはできません。

| 分類 | 実測した対象 | サイズ上の性質 |
| --- | --- | --- |
| 整数演算・制御フローに変換される機能 | bit_set、bit_field、defer | 最適化後の手書きとの差は0 B。専用ランタイムや I/O の import は追加されない |
| 小さなホスト API 呼び出し | fd_write と独自 _start | 660 B。ホストに I/O 実装を委ねる |
| 起動処理・標準 context の依存 | fd_write と通常の main | 15,031 B。引数処理、アロケータ、乱数生成器などが残る |
| OS 抽象を介した I/O | os.write_string | 24,581 B。ファイル操作群なども残る |
| 汎用フォーマットと依存処理 | fmt.println | 160,845 B。今回の測定では大きい |

`defer` で呼ぶ処理が `delete` や `fmt.println` なら、その処理に必要なコードは残ります。また、多数の出口に大きな後処理が展開される場合もサイズは変わり得ます。「defer 自体のための専用ランタイムが不要」と「後処理もサイズを消費しない」は別の話です。大きな配列を基底型とする bit_set など、今回より大きなデータ表現は未測定です。

言語仕様は Odin 公式 Overview の [bit_set](https://odin-lang.org/docs/overview/#bit-sets)、[bit_field](https://odin-lang.org/docs/overview/#bit-fields)、[defer](https://odin-lang.org/docs/overview/#defer-statement) を参照してください。サイズの数値は、このリポジトリの比較例による実測値です。

## 非同期処理

今回使った Odin 配布版には、言語組み込みの `async` / `await` はありません。標準ライブラリの [core:nbio](https://pkg.odin-lang.org/core/nbio/) は、非ブロッキング I/O とイベントループをコールバック方式で提供します。`tick` / `run` などが完了した処理のコールバックを呼びます。

Wasm では、ホストのイベントループで待機し、完了時に Wasm の関数を呼び戻す構成を小さく実装できます。[比較例](../examples/wasm/async-host/main.odin) は同じ5つの公開関数と `host.request` という1つの import を使い、次の2方式を切り替えます。

- `async-state`: `Phase` と `switch` で続きの処理を選ぶ。コンパイラによる async 変換ではなく、手書きの状態機械です。
- `async-callback`: 次に実行する `proc "contextless"` を保持し、完了時に呼ぶ。`-define:USE_CALLBACKS=true` で選択します。

両方とも固定の1タスク枠を持ち、2つの処理を順にホストへ依頼します。テスト用ホストの処理は `+1`、次に `*2` で、入力20が42になります。`begin` が返った時点では未完了です。ホストが後から `complete` を呼ぶと再開します。エラー、重複・順序違い・古い返答の無視、タスクの置き換えも含みます。キャンセルは結果を無視する操作であり、ホスト側の処理自体を中止する操作ではありません。

以下は Wasm ファイル全体のサイズです。一般的な async ランタイムの増分を測った数値ではありません。

| プログラム | 設定 | Wasm | gzip | Brotli |
| --- | --- | ---: | ---: | ---: |
| async-state | minimal | 1,068 | 724 | 619 |
| async-state | size | 656 | 448 | 369 |
| async-state | no-rtti | 659 | 448 | 383 |
| async-state | optimized | 462 | 340 | 284 |
| async-callback | minimal | 1,236 | 792 | 671 |
| async-callback | size | 805 | 513 | 433 |
| async-callback | no-rtti | 808 | 514 | 439 |
| async-callback | optimized | 547 | 374 | 314 |

最適化後の code セクションは状態機械版225 B、コールバック版287 B でした。コールバック版には2つの継続関数と間接呼び出し用の関数テーブルが残ります。ファイル全体では85 B の差でした。

[非同期テスト](../scripts/wasm-async.test.mjs) では、状態遷移をホスト側から段階的に進める検証と、JS の Promise で完了通知を後回しにする検証を行います。JS の Promise 実装、イベントループ、実際のネットワークやタイマーの実装はこのサイズに含めていません。この例にはヒープ割り当て、複数タスクのスケジューラ、任意の呼び出し階層を中断する仕組みもありません。

### 標準ライブラリ側の制約

`core:nbio` の Wasm 向けフォールバックは `FULLY_SUPPORTED == false` で、ファイル・ネットワーク操作は `.Unsupported` / `.Network_Unreachable` になります。[公式のフォールバック実装](https://github.com/odin-lang/Odin/blob/master/core/nbio/impl_others.odin) にキューやタイムアウト処理はありますが、今回の配布版では、その利用も型検査で失敗しました。

[next_tick の利用例](../examples/wasm/nbio-next-tick/main.odin) を `odin check examples/wasm/nbio-next-tick -target:wasi_wasm32 -vet` で検証すると、`Handle(-100)` を `uintptr` に変換できないエラーと、`_Recv` / `_Send` に `bufs` フィールドがないエラーになります。この例の Wasm は生成されておらず、サイズは未計測です。測定スクリプトはこの型検査を独立したプローブとして実行し、成否と診断を `results.json` の `availability` に記録します。

また、[core:thread の JS / WASI 向け実装](https://github.com/odin-lang/Odin/blob/master/core/thread/thread_other.odin) は `IS_SUPPORTED == false` です。OS スレッド、スレッドプール、スタックを切り替える外部コルーチン、Asyncify などのサイズは今回測っていません。

今回の分類では、ホストに待機を任せる小さな状態機械やコールバックは軽量です。キュー、タイマー、メモリ管理、I/O バックエンド、タスク間の同期などを Wasm 側へ持ち込む構成は、その実装ごとに測る必要があります。

## 再実行

```sh
ODIN=/path/to/odin just wasm-size
ODIN=/path/to/odin just test-wasm
```

測定には [Odin dev-2026-11a](https://github.com/odin-lang/Odin/releases/tag/dev-2026-11a) の macOS ARM64 版を使いました。

必要なコマンドは Odin、Node.js 24 以上、`wasm-opt`、`wasm-ld` です。`wasm-ld` が PATH にない場合は、インストール済みの Zig の `zig wasm-ld` を作業用ラッパー経由で利用します。通常の導入方法は [Odin 公式のインストール手順](https://odin-lang.org/docs/install/#a-note-on-wasm-and-llvm-binaries) を参照してください。実行ファイルは `ODIN`、`WASM_OPT`、`ZIG`、`WASMTIME` 環境変数で変更できます。

測定に使ったバージョン:

- Odin: `dev-2026-11-nightly:9a69916`
- リンカ: Zig 0.16.0 に同梱の LLD 21.1.8
- wasm-opt: 116
- Node.js: v24.22.2
- Wasmtime: 42.0.1

[測定スクリプト](../scripts/wasm-size.mjs) は、生成した Wasm と `.gz` / `.br`、正確なコマンド・バージョン・import 一覧・手書き版との比較結果・nbio の利用可否を含む `results.json`、一覧表 `results.md`、比較表 `features.md` を `build/wasm/` に保存します。ツールチェーンやコンパイラのパスによって結果は変わり得ます。

`just test-wasm` はビルドした全52種類を検証します。[基本テスト](../scripts/wasm.test.mjs) では add の公開関数を Node.js から呼び、正負・ゼロ・32 bit 整数の折り返しを確認します。WASI を使う例は Wasmtime で実行して終了コードと標準出力を確認します。I/O を模したホストで、直接書き込みの部分書き込み・I/O エラー・書き込みが進まない場合も検証します。[機能の比較テスト](../scripts/wasm-features.test.mjs) では、機能版と手書き版をそれぞれ仕様に基づく期待値と照合します。[非同期テスト](../scripts/wasm-async.test.mjs) を含め、合計45テストです。nbio の型検査プローブは、これらの実行テストとは別に成否を記録します。
