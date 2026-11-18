# Odin 側で再現した挙動

対象は Odin `dev-2026-11-nightly:9a69916` です。以下はアプリケーションから切り離して再現した標準ライブラリの挙動です。配布版更新時は再現例で確認します。

## JSON の範囲外整数が成功扱いになる

```sh
"${ODIN:-odin}" run examples/odin-issues/json-unmarshal -vet
```

| 入力の `duration_ms` | `u32` に入った値 | 成功扱い |
| --- | ---: | --- |
| `4294967295` | 4294967295 | はい |
| `-1` | 4294967295 | はい |
| `4294967296` | 0 | はい |
| `170141183460469231731687303715884105728`（2¹²⁷） | 3435973836 | はい |

macOS ARM64 ネイティブと Wasmtime の WASI で同じ結果でした。ログの時間フィールドでは、範囲内の値はそのまま読み、範囲外ならエラーとして扱う必要があります。この版の `assign_int` は整数を対象の型へ直接変換し、`unmarshal_value` は整数変換の成否を受け取らず値だけを使います。 [再現ソース](../examples/odin-issues/json-unmarshal/main.odin) · [配布版の実装](https://github.com/odin-lang/Odin/blob/9a69916/core/encoding/json/unmarshal.odin#L189) · [配布版の整数デコード](https://github.com/odin-lang/Odin/blob/9a69916/core/encoding/json/unmarshal.odin#L496)

確認時の upstream `master` には、型の範囲外で失敗させるオプション `.Disallow_Integer_Wrap` があります。今回の配布版にはこのオプションがありません。既定の狭め変換は互換性に関わる挙動です。アプリでは数値トークンの種類、桁数、変換の成否、`u32` の範囲を検査しています。 [upstream の実装](https://github.com/odin-lang/Odin/blob/master/core/encoding/json/unmarshal.odin)

## 一つの JSON 値の後に続くデータを許す

同じ再現例で、`{"duration_ms":1} {}` を `spec=.JSON` の `json.unmarshal_string` に渡すと、`value=1 success=true` になります。JSON Lines の1行としては二つの値があるため無効です。この配布版の `is_valid` は一つの値を検証した時点の結果を返します。アプリではオブジェクトの閉じ括弧に続くトークンが EOF であることを確認します。 [配布版の validator](https://github.com/odin-lang/Odin/blob/9a69916/core/encoding/json/validator.odin#L7)

## 以前に確認した WASI の nbio 型検査エラー

`odin check examples/wasm/nbio-next-tick -target:wasi_wasm32 -vet` で、同梱 `core:nbio` の fallback 内に `Handle(-100)` と不足する `bufs` フィールドの診断が出ます。同じ版の macOS ネイティブでは `next_tick` の動作を確認しています。 [既存の記録](wasm-size.md#標準ライブラリ側の制約)
