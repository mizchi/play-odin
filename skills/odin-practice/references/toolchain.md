# CLI 開発と計測

[ログ集計 CLI](../../../docs/log-summary.md) で確認した手順。使用版は `dev-2026-11-nightly:9a69916`。

## 入力とメモリ

- `os.to_reader(os.stdin)` でファイルハンドルを `io.Reader` に変換する。WASI の標準入力をホストのリダイレクトで供給すると、ゲスト側でファイルのパスを開く必要がない。
- `bufio.reader_read_slice` は次の読み込みで無効になる借用スライスを返す。EOF の前に返った末尾のデータも処理する。最大行長を定義し、`.Buffer_Full` を受けたら改行まで断片を破棄する。
- 一時領域をレコード内で使い切れるなら `mem.Dynamic_Arena` を再利用し、各レコードで `dynamic_arena_reset` する。 `dynamic_arena_free_all` は再利用用のブロックも返す。残す集計には所有権のある値だけを入れる。
- JSON Lines の契約では `spec=.JSON` を明示する。この版の既定は JSON5。入力全体を消費したかとフィールド値が範囲内かを確認する。構造体のフィールド型だけで検査を代用できない。 [Odin 側の再現メモ](../../../docs/odin-issues.md)

## 何の時間を測るか

- 実行時間は `-o:minimal`、`-o:size`、`-o:speed` で同じ入力・結果を比較する。ターゲットごとに最速設定が変わる。プロセス起動や Wasmtime のウォームアップを含めたか記録する。
- ビルド時間は `-show-timings` を使う。機械比較が必要なら `-export-timings:json` と `-export-timings-file:<path>` を追加する。 `-show-more-timings` も手元の `build -help` で確認できる。
- `-export-dependencies:json -export-dependencies-file:<path>` はソース依存の確認に使う。 `-print-linker-flags` は別の呼び出しにする。この版では両者の併用が拒否された。

## サイズを変えた原因を確かめる

- 固定キーと整数だけの出力なら、`fmt.bprintf` と `strconv.write_uint` を同じ出力で比較できる。 `write_uint` の戻り値は渡したバッファのスライスなので、十分な容量を確保し、結果を使い終えるまでバッファを維持する。
- `#config` と `-define:NAME=value` で比較する部分を切り替える。両版の境界値テストを実行してから測る。
- `wasm-opt -Oz --strip-debug --strip-producers` 後も同じ入力の実行を確認する。 `wasm-tools objdump` でセクション別のサイズ、`wasm-tools print` で追加された imports / exports を見る。生サイズと gzip / Brotli を別々に記録する。
- Odin 側の不具合を疑う場合はアプリを切り離し、最小ソース、コンパイラ版、ターゲット、コマンド、期待値と実測を保存する。手元の不具合と upstream の修正・追加オプションは別々に確認する。
