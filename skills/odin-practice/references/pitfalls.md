# 構文・API の失敗と解決

確認環境: 2026-11-18、Odin `dev-2026-11-nightly:9a69916`。以下はこの作業で実際に拒否されたコード・成功した比較例を元にする。将来の版で変わった場合は、診断とソースを優先する。

## 1. transmute に直接文字列リテラルを渡す

- 最初の失敗: `transmute([]u8)"Hello, Odin!\n"` は `Cannot transmute untyped expression`。
- 動いた解決:

```odin
message := "Hello, Odin!\n"
remaining := transmute([]u8)message
```

- 次回の判断: 式の型を先に確定する。view はコピーではないので、文字列由来の領域へ書き込まない。
- 検証例: [direct-write](../../../examples/wasm/direct-write/main.odin)、[stdlib](../../../examples/wasm/stdlib/main.odin)。

## 2. int と i32 を同じとみなす

- 最初の失敗: `marker := 2` を `proc(value: i32)` に渡し、`int` を `i32` に代入できないと拒否された。
- 動いた解決: `marker := i32(2)` と宣言するか、境界で明示変換する。
- 次回の判断: ターゲット上のビット数が同じでも型の一致とは別。外部 ABI と内部計算の型を確認する。
- 検証例: [defer の比較例](../../../examples/wasm/features/defer/main.odin)。

## 3. enum switch に default があれば省略できると思う

- 最初の失敗: 6ケースの enum に2ケースと `case:` のみを書き、`-vet` 付きのビルドで `Unhandled switch cases`。
- 動いた解決: 残りの enum 値も列挙する。意図的な部分分岐なら `#partial switch` を使う。
- 次回の判断: default を足して診断を消すのではなく、網羅性の契約を決める。
- 検証例: [async-host](../../../examples/wasm/async-host/main.odin)。

## 4. overload エラーを、文字列リテラルの型だけの問題だと思う

- 最初の失敗: `os.read_entire_file(path)` の候補診断に `untyped string` が出たため紛らわしかった。
- 動いた解決:

```odin
bytes, err := os.read_entire_file(path, context.allocator)
```

- 次回の判断: 使用版の `read_entire_file_from_path` は allocator が必須。候補の signature と arity を先に読む。`write_entire_file` など別APIのデフォルト引数から推測しない。
- 検証例: [WASI のファイル操作](../../../examples/wasm/stdlib/platform_wasi.odin)。定義は `$(odin root)/core/os/file_util.odin`。

## 5. Go の or_return / defer / closure を想定する

| 最初の失敗 | 動いた解決 | 次回の判断 |
| --- | --- | --- |
| 無名戻り値の proc から `or_return` | `-> (value: int, err: Error)` など名前付き戻り値 | 伝播先の型・エラーのゼロ値も定義する |
| `defer` から名前付き戻り値を書き換える | 戻り値は return 前に計算し、defer は後始末に使う | 使用版では代入自体がコンパイルエラー |
| ネストした proc から runtime のローカル変数を参照する | 引数または状態 struct を明示的に渡す | 自動 capture を前提にしない |
| `distinct u64` へ `u64` を直接代入する | `User_ID(raw)` | 同じ表現でも型は別 |

- 再現例: [compile-errors](../../../examples/compile-errors/)、[診断検査](../../../scripts/check-negative.mjs)。
- 成功例: [名前付き戻り値と or_return](../../../practice/dimensions.odin)、[defer の観測](../../../examples/wasm/features/defer/main.odin)。
- `defer` の登録時に変数の値が固定されるわけではない。後で変えた `marker` が実行時に読まれる例をテストしている。

## 6. allocator の寿命を戻り値より短くする

- 避けた失敗: ローカル固定バッファの Arena で作った string を、そのまま返す。
- 動いた解決: `strings.clone(scratch, output_allocator)` で呼び出し側へ複製する。
- 次回の判断: slice/string の表現を渡すことと、データの所有権を渡すことは別。`context.allocator` の変更範囲と、返却データの解放者を決める。
- 検証例: [clone_via_scratch](../../../practice/memory.odin)。これはコンパイラが必ず検出する誤りではなく、寿命の契約として確認する。

## 7. 公式 API の最新版を手元にもあると思う

- 最初の誤解: 現公式索引の TLS や圧縮形式を、11月3日版の同梱機能と混同しそうになった。実際に手元には該当ディレクトリがなかった。
- 動いた解決: `odin version` と `odin root` を記録し、インストール済みソースと個別 API の両方を見る。
- 次回の判断: Web 索引と個別ページにも生成時点の差がある。使う型・関数・target backend の存在を手元で確かめる。

## ドキュメントを探す順序

1. `odin build -help`: flags と対象版の制約。例: `-o:size`、`-no-entry-point`。
2. `odin root` 以下へ `rg --files` と `rg -n '関数名'`。
3. [公式 API](https://pkg.odin-lang.org/) で package の Overview・source・signature・対象 target を確認。
4. [Overview](https://odin-lang.org/docs/overview/) で言語仕様を確認。コンパイラの現在の診断と古い説明が食い違う場合は版差を明記する。

実際に迷った場所:

- runtime は `core/runtime` でなく `base/runtime`。
- WASI は `core/sys/wasi` でなく `core/sys/wasm/wasi`。
- LZ4 は `lz4.odin` という単一ファイルでなく `compress.odin` / `decompress.odin` などに分かれている。
- `foreign` や platform suffix のファイルを確認し、Odin実装・外部C binding・未実装stubを区別する。

## CLI 実装で追加で遭遇したもの

| 失敗 | 動いた解決 | 次回の判断 |
| --- | --- | --- |
| `when` の枝に `import` を置くと構文エラー | import をファイルスコープへ、`when` は処理の切り替えに使う | OS ごとに依存自体を分けるときはファイル接尾辞か `#+build` を確認する |
| 短い write の後で `proc(data: string)` の `data` に再代入 | `remaining := data` を更新する | 引数の束縛は不変。元の文字列を書き換える必要はない |
| `for input in [?]string{ ... } {` がパースエラー | 配列リテラルを変数へ束縛してから回す | composite literal の括弧とループ本体の開始位置を切り分ける |
| ソースにあった `json.unquote_token` を直接呼んで非公開エラー | 文字列トークンを公開の `json.parse_value` で読み、`json.String` を取り出す | `@(private)` と API 索引を確認する |
| `json.unmarshal` の成功で数値の範囲とレコード末尾も確認できたと考えた | トークンの型・値の範囲・EOF を個別に確認 | 同梱版の整数変換と行の境界をテストする |

[CLI の実装](../../../examples/log-summary/summary.odin) · [Odin 側の最小再現](../../../docs/odin-issues.md)

## スキル自体の検証

2026-11-18、会話履歴を渡さない別エージェントにこのスキルと壊れたソースだけを渡した。型幅、untyped literal の transmute、必須 allocator、enum switch の4診断を再現し、修正後に `-target:wasi_wasm32 -vet` でビルド、Wasmtime で実行して期待する `3 3 1` を確認した。前提を推測せず、同梱 API・Zig リンカ・preopen を確認して完了した。スキルの構造検査に加え、実際の利用でも確認した記録であり、全ての Odin コードに対する性能評価ではない。
