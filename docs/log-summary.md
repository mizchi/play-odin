# JSON Lines ログ集計 CLI

標準入力からログを1行ずつ読み、件数と処理時間を集計します。パイプラインの最後に接続でき、集計結果は機械処理しやすい1行の JSON です。

```sh
ODIN=/path/to/odin just build-log-summary
build/log-summary/log-summary < examples/data/events.jsonl

ODIN=/path/to/odin just build-log-summary-wasi
wasmtime run build/log-summary/log-summary.wasm < examples/data/events.jsonl
```

```json
{"valid":4,"invalid":1,"info":2,"warn":1,"error":1,"total_ms":70,"max_ms":30}
```

- 各行は UTF-8 の JSON オブジェクトです。必須フィールドは `level`（`info` / `warn` / `error`）と `duration_ms`（0〜4,294,967,295 の整数リテラル）です。他のフィールドは読み飛ばします。
- 空行は集計から除きます。必須項目の欠落、同じ必須項目の重複、範囲外の時間、末尾の余分なデータ、64 KiB を超える行、64段を超えるネストは `invalid` に数えます。行の長さに LF と CRLF は含めません。
- 読み書きの失敗では終了コード1、CLI 引数の誤りでは2です。不正レコードは集計内に残し、ストリームを最後まで処理できれば0で終了します。
- 標準入力をホストから渡すだけなので、この WASI 版にディレクトリの preopen を設定する必要はありません。

[集計と入力処理](../examples/log-summary/summary.odin) は `io.Reader` に対して動きます。[CLI と出力](../examples/log-summary/main.odin) は引数、標準入出力、終了コードを担当します。

## 実装で分かったこと

- `bufio.reader_read_slice` の返すスライスはバッファを借ります。次の読み込みまでにレコードを値へ変換します。`.Buffer_Full` の断片は改行まで読み捨て、不正件数を行ごとに1回だけ増やします。EOF と同時に返る最終行も処理します。行ごとにコピーを作る `reader_read_bytes` は、区切りが来るまで動的配列を増やすので、今回の行サイズ制限には借用スライスが適していました。 [bufio の API](https://pkg.odin-lang.org/core/bufio/)
- JSON のキーや文字列の一時領域には `mem.Dynamic_Arena` を使い、レコード末尾で `dynamic_arena_reset` します。使い終えた通常ブロックを次の行に再利用でき、エラー途中に確保された領域もまとめて回収できます。ネイティブと WASI で同じ実装を使っています。
- 入力の境界では、整数トークンか、値が範囲内か、行全体を消費したかを個別に確認します。標準の構造体デコードを試した段階で、範囲外の値や末尾に続く別オブジェクトが成功扱いになることを再現しました。 [Odin 側の再現メモ](odin-issues.md)

## 最適化の実測

Odin `dev-2026-11-nightly:9a69916`、LLD 21.1.8、wasm-opt 116、Wasmtime 42.0.1、macOS ARM64。生成した30万行の同じファイルを、各設定でウォームアップ1回、計測5回実行しました。表は中央値で、プロセス起動とファイル読み込みを含みます。Wasmtime はウォームアップ後の計測です。

| 設定 | ネイティブ実行 | WASI 実行 | WASI 生サイズ | Brotli 11 |
| --- | ---: | ---: | ---: | ---: |
| `-o:minimal` | 327.9 ms | 522.7 ms | 299,015 B | 118,111 B |
| `-o:size` | 88.6 ms | 393.4 ms | 106,593 B | 44,538 B |
| `-o:speed` | 71.7 ms | 423.9 ms | 112,361 B | 44,114 B |
| `-o:size`、出力に `fmt.bprintf` | — | 395.3 ms | 263,788 B | 94,660 B |
| `-o:size` → `wasm-opt -Oz` ＋メタデータ除去 | — | 404.9 ms | 86,374 B | 40,188 B |

この入力では、ネイティブの速度には `-o:speed`、WASI の実行時間と生サイズの両方には `-o:size` が向いていました。WASI の最小配布サイズは後段の `wasm-opt` を使った設定でした。Brotli では `speed` と `size` の順が逆転したので、配布サイズを重視する場合は実際に使う圧縮後の値を比較します。

固定フィールドを `strconv.write_uint` で組み立てる版は、汎用の `fmt.bprintf` を7回呼ぶ版より WASI の生サイズが157,195 B小さくなりました。集計結果の出力は1回なので、今回の実行時間への影響は小さいです。どちらも同じ出力契約と境界値テストを使っています。

## ビルドと調査を再現する

```sh
ODIN=/path/to/odin just test-log-summary
ODIN=/path/to/odin just bench-log-summary
```

ベンチはすべての実行で集計を照合し、各回の時間を `build/log-summary/bench.json` に保存します。生・gzip・Brotli のサイズは `build/log-summary/sizes.json` に出ます。WASI は `wasm-ld`、または Zig の `wasm-ld` を使います。 `WASMTIME` と `WASM_OPT` でコマンドを指定できます。

ビルドが遅いときは `odin build -help` で該当版のオプションを確認します。この例の WASI `-o:size` ビルドでは `-show-timings` が約549 msを記録し、LLVM のコード生成が約487 msを占めました。詳細を保存するなら `-export-timings:json -export-timings-file:build/log-summary/timings.json`、ソース依存の確認には `-export-dependencies:json -export-dependencies-file:build/log-summary/dependencies.json` を付けます。リンカ引数は別の呼び出しで `-print-linker-flags` を使います。この版は `-export-dependencies` と `-print-linker-flags` の併用を拒否します。

生成後は `wasm-tools objdump` でセクションのサイズ、`wasm-tools print` で imports と exports を確認できます。最小版の86,374 Bのうち、code は61,664 B、data は23,649 Bでした。
