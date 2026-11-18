---
name: odin-practice
description: "Write, review, and debug Odin code using the installed compiler and matching core/vendor sources. Use for Odin syntax/type/API errors, allocator and ownership handling, or native/Wasm builds and size checks."
---

# Odin practice

Odin を書く際の、実際に遭遇した誤解と回避方法。Go/C/JS から構文やランタイムの性質を推測せず、使用するコンパイラで確かめる。

## 最初に見るもの

```sh
"${ODIN:-odin}" version
"${ODIN:-odin}" root
"${ODIN:-odin}" build -help
```

`odin root` 以下の `core` / `vendor` / `base/runtime` を、使用版と一致する API・実装の根拠にする。ファイル名を決め打ちする前に `rg --files` で探す。公式 API は [pkg.odin-lang.org](https://pkg.odin-lang.org/)、構文は [Overview](https://odin-lang.org/docs/overview/) を使うが、現行 Web と手元配布版の差を確認する。

- パッケージ全体は `odin check path/to/package -vet`。単独ファイルなら `-file` を付ける。
- API の overload エラーは、表示された候補の引数数・必須 allocator・戻り値を先に確認する。型変換だけを足して解決しようとしない。
- `ODIN` が指定されている作業ではそれを使い、コンパイラの追加導入を先に行わない。

## 構文・型・所有権

該当するエラーが出たら [構文・API の失敗と解決](references/pitfalls.md) を読む。

- `:=` の整数リテラルは通常 `int`。`i32` / `u32` の API 境界では必要な幅を明示する。
- `transmute` は型が確定した式に使う。文字列から `[]u8` への view は元データを借りるもので、コピーや所有権移譲ではない。
- `or_return` の伝播先は名前付き戻り値で定義する。戻り値の最後がエラーなのか成功 bool なのかも確認する。
- `defer` はスコープ終了時に逆順で実行され、式中の変数は実行時の値を読む。名前付き戻り値への代入や、ネストした proc によるローカル変数の capture を Go と同じに扱わない。
- enum の `switch` は全ケースを列挙する。意図的に省略するなら `#partial switch` を検討する。
- `distinct` は明示変換する。scratch/stack のメモリに依存する slice/string を返すなら、呼び出し側の allocator に複製する。

## Wasm の場合

ビルド前に [Wasm の環境・初期化・対応範囲](references/wasm.md) を読む。

- `js_wasm32`、`wasi_wasm32`、`freestanding_wasm32` はホスト契約が異なる。ブラウザ、WASI、独自ホストのどれが必要か先に決める。
- ホストへ公開する scalar API は `@(export)` と `proc "c"`、固定幅の整数で契約を定義する。Odin の暗黙 context をホストから渡せる前提にしない。
- コンパイル成功、到達可能なコードの存在、実行成功、対象 API の実装有無を別々に確認する。小さな生成物が処理の削除によるものではないか確かめる。
- `-no-rtti`、境界チェック無効化、初期化の省略を一律のサイズ最適化として加えない。

## 検証と追記

ストリームを処理する CLI、ビルド時間・サイズ・実行時間の計測では [アプリ開発で使ったツールチェイン](references/toolchain.md) を参照する。

このリポジトリでは `ODIN=/path/to/odin just verify`、Wasm は `just test-wasm` と `just test-wasm-stdlib` を使う。別のプロジェクトへ移植する場合は、そのプロジェクトの実行手順へ合わせる。

新しい落とし穴を追記するときは「最初の失敗 → 動いた解決 → 次回の判断」の組にし、コンパイラ版・ターゲットと、検証例またはソースを残す。特定版のライブラリ不具合を、言語全体の恒久的な禁止事項にしない。
