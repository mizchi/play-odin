# Wasm の環境・初期化・対応範囲

確認環境: Odin `dev-2026-11-nightly:9a69916`、LLD 21.1.8、wasm-opt 116。具体的な制約はこの版の観測であり、将来の版を一律に制限しない。

## ターゲットと公開 API

| ターゲット | ホスト契約 | 先に確認するもの |
| --- | --- | --- |
| `js_wasm32` | `odin.js` の imports とブラウザ/JS API | `core/sys/wasm/js/odin.js`、必要な DOM/GPU/イベント API |
| `wasi_wasm32` | WASI Preview 1 | ホストの実装、preopen、stdin/out、clock 等 |
| `freestanding_wasm32` | 必要な imports・初期化を自分で定義 | C ABI、export の到達性、context・allocator・runtime 初期化 |

```odin
@(export)
add :: proc "c" (a, b: i32) -> i32 {
	return a + b
}
```

`@(export)` だけで通常の `proc` を出すと、Odin の暗黙 context を含む呼び出し規約になる。ホスト向けの契約には固定幅の scalar 型と `proc "c"` を使い、u32 の戻り値は JS 側で必要なら `>>> 0` で解釈する。

## リンカを追加導入する前に探す

- 最初の失敗: `wasm-ld` 不足へ `brew install lld` を実行し、Homebrew と無関係な依存の更新・ソースビルドまで始まった。
- 動いた解決: 導入を停止し、既存の `zig wasm-ld --version` を確認して、作業用の `wasm-ld` wrapper を PATH の先頭に置いた。
- 次回の判断: 既存ツールで足りるか確認する。リンカ1個の不足を、ツールチェーン全体の更新が必要という意味にしない。

作業用ディレクトリの wrapper 例:

```sh
#!/bin/sh
exec "${ZIG:-zig}" wasm-ld "$@"
```

このリポジトリのビルドスクリプトにも同じフォールバックがある。一般の利用環境で Zig を必須にせず、既存 `wasm-ld` があればそれを使う。

## freestanding で処理が消える場合

- 最初の失敗: 通常の `main` 内へ標準ライブラリの検証処理を書き、freestanding の生成物337 Bを見た。しかし export は常に0を返し、`main` が到達不能として消えていた。
- 動いた解決: ホストから実際に呼ぶ `proc "c"` を export して処理へ到達させ、戻り値まで検証する。
- 次回の判断: コンパイル成功と小さなファイルだけでは、必要な処理が残った証拠にならない。`WebAssembly.Module.exports/imports` や WAT を見て、実際に呼ぶ。

次の段階では、処理を export して `runtime.default_context()` を設定しても、実行時の bounds check で trap した。今回の例は、freestanding の entry point で通常・一時 allocator を明示し、`runtime._startup_runtime()` と後始末も行うことで、JSON/CBOR/regex を含む検証が通った。

通常の起動処理も省略した場合は、標準 context を作るだけで十分とは限らない。使用するライブラリに応じて通常・一時 allocator と runtime の初期化を確認する。`base/runtime/default_temporary_allocator.odin` では freestanding のデフォルト一時 allocator は nil allocator。`base/runtime/core.odin` の `_startup_runtime` / `_cleanup_runtime` は明示的な entry point 用として説明されているが、一般の API 呼び出しごとに初期化を繰り返す用途ではない。反射を使うコードで `-no-rtti` を追加して解決しようとしない。

## サイズ計測で遭遇した罠

| 最初の失敗・誤解 | 動いた解決 | 次回の判断 |
| --- | --- | --- |
| WASI の全例に `-no-rtti` を付けた | 対応 target のみに使用 | この版では freestanding または bedrock 専用。JSON/CBORの型変換等は反射も使う |
| ファイル全体の7 B差を機能の差と見る | 名前セクションを除去して比較 | `-manual` など出力名もメタデータへ入る |
| 小さい例なら最適化設定は無関係と思う | 同じAPI・runtime入力で `-o:size` と wasm-opt 後を比較 | bit_field は `-o:minimal` の code 529 Bが `-o:size` で64 Bになった |
| `fmt` の例を言語の最低コストとみなす | 計算、直接I/O、通常startup、fmtを別々に測定 | 大きい依存処理と構文の費用を分ける |

基準例は [サイズ実測](../../../docs/wasm-size.md) と [比較テスト](../../../scripts/wasm-features.test.mjs)。数値を別版・別プログラムの保証値にしない。

## API が存在しても使えるとは限らない

- WASI の `os.read_entire_file` 等は、ホストから必要な preopen を渡して試す。相対パスの fixture を読む最小例なら、専用作業ディレクトリで `wasmtime run --dir=. app.wasm`。`/sandbox` 等へ割り当てる場合はホスト側の対応付けも確認する。ブラウザに任意のファイルアクセスをそのまま移植しない。
- `core:thread` の JS/WASI 実装はこの版では `IS_SUPPORTED == false`。
- `core:nbio` は native では動作したが、この版の WASI 利用例は標準ライブラリ内で型検査に失敗した。未計測を0 Bと扱わない。
- `core:net` の Wasm 向け socket は `.Network_Unreachable`、プロセス操作は `.Unsupported` を返す stub がある。
- `core:mem/virtual` の reserve/commit は fallback に空実装がある。固定バッファの `mem.Arena` と OS の reserve/commit を同じ機能として扱わない。
- `core:time` の JS向け `sleep` は、この版の `odin.js` では正の時間を渡しても待機処理が空。非同期待機はホストのイベントループに依頼する。
- `vendor:wgpu` は JS/Wasm 向け backend を持つが、関数テーブルと allocator 等が必要。同梱C binding全般を自動的にWasm対応とみなさない。
- crypto README の Wasm のタイミング特性・未独立レビュー等の明示制約を確認する。「ビルドできる」と「用途に安全」は別。

参照:

- [公式Wasm README](https://github.com/odin-lang/Odin/blob/master/core/sys/wasm/README.md)
- [Wasm と標準ライブラリの実行検証](../../../examples/wasm/stdlib/main.odin)
- [公式 wgpu API](https://pkg.odin-lang.org/vendor/wgpu/)
- [crypto の制約](https://github.com/odin-lang/Odin/blob/master/core/crypto/README.md)

## 採用範囲と重複確認

2026-11-18 に、リポジトリ内と `~/.agents/skills` / `~/.claude/skills` の SKILL.md、該当する CLAUDE.md/AGENTS.md・rules を `Odin`、`transmute`、`wasm-ld`、`no-rtti` 等で確認し、同じ Odin 用スキルは見つからなかった。手順・版差・APIの判断が必要な事項として新規スキルにまとめた。グローバルのルールや lint は追加していない。

非採用: ドキュメントのディレクトリリンクを `readFileSync` で読むと失敗する問題は、Odin 固有ではないためスキルの手順に加えず、このリポジトリのリンク検査を修正した。
