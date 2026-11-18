# Odin 実践プラクティス集

Go の構文を読める人が、Odin で小さなライブラリを書くときの手元用メモです。例は [practice/](../practice/contracts.odin) にあり、`just verify` で実行時の挙動、意図したコンパイルエラー、本文とソースの一致を確かめられます。

検証環境は macOS ARM64、配布タグ [dev-2026-11a](https://github.com/odin-lang/Odin/releases/tag/dev-2026-11a)、コンパイラ表示は `dev-2026-11-nightly:9a69916`。確認日は 2026-11-18 です。本文中の `testing.expect_value(t, ...)` はテストの抜粋です。完全なテストは [practice_test.odin](../practice/practice_test.odin) にあります。

## 1. 外部表現の契約を先に決める

試作用のパケットヘッダを 16 bit とし、次の配置を契約にします。これは Rex のプロトコルを再現したものではありません。

| ビット位置 | 内容 | 許可する値 |
| --- | --- | --- |
| 0–2 | メッセージ種別 | `Data = 1`、`Ping = 2` |
| 3 | 圧縮フラグ | `false`、`true` |
| 4–15 | payload のサイズ | 0–4095 |
| バイト順 | wire 上の配置 | little endian |

<!-- snippet: practice/contracts.odin#header -->
```odin
Header :: bit_field u16 {
	kind:         Message_Kind | 3,
	compressed:   bool         | 1,
	payload_size: u16          | 12,
}
```
<!-- /snippet -->

`Header` の定義と `Error` の定義は [contracts.odin](../practice/contracts.odin)、変換処理は [headers.odin](../practice/headers.odin) に分けています。利用者が知る必要のあるサイズ、値域、エラー、所有権を先に固定し、その内側の実装を変更できる形です。

この例には `#assert(size_of(Header) == 2)` も入れています。C の bit-field との互換性は別途検証が必要です。[公式 Bit fields](https://odin-lang.org/docs/overview/#bit-fields)

### 切り詰めを入力検証に使わない

フィールドに書く `u16` は読み書きに使う型で、`| 12` が保存する幅です。12 bit の符号なし整数の最大値は 4095 なので、実行時の値 4096 は切り詰められて 0 になります。5 bit の符号付きフィールドの範囲は -16–15 です。実行時の値 31 を格納すると、下位 5 bit がすべて 1 となり、読み出すと -1 になります。

コンパイル時に分かる不正な定数については診断が入る場合があります。ここでテストしているのは変数経由の書き込みです。外部データの検証は代入の前に行います。

<!-- snippet: practice/headers.odin#make-header -->
```odin
make_header :: proc(kind: Message_Kind, compressed: bool, payload_size: int) -> (h: Header, err: Error) {
	if kind != .Data && kind != .Ping {
		return {}, .Unknown_Kind
	}
	if payload_size < 0 || payload_size > 4095 {
		return {}, .Payload_Too_Large
	}
	h = Header{kind = kind, compressed = compressed, payload_size = u16(payload_size)}
	return
}
```
<!-- /snippet -->

`payload_size` を先に `u16` へ変換すると、それより大きな入力の情報を失います。入力を受け取る `int` の段階で `-1`、`4096`、`65536` を拒否し、`0` と `4095` を受理するテストを置いています。

### ビットの順序とバイト順を分ける

`transmute` は同じサイズの表現を読み替える操作です。値を変換する cast と区別します。ここでは `Header` と `u16` の間だけに使用し、byte 列との変換は明示的に行っています。

<!-- snippet: practice/headers.odin#wire -->
```odin
encode_header :: proc(h: Header) -> [2]u8 {
	word := transmute(u16)h
	return {u8(word & 0xff), u8(word >> 8)}
}

decode_header :: proc(bytes: []u8) -> (h: Header, err: Error) {
	if len(bytes) < 2 {
		return {}, .Too_Short
	}
	word := u16(bytes[0]) | (u16(bytes[1]) << 8)
	h = transmute(Header)word
	if h.kind != .Data && h.kind != .Ping {
		return {}, .Unknown_Kind
	}
	return
}
```
<!-- /snippet -->

`decode_header` は先頭 2 byte を読みます。後続の byte を許す契約です。完全に 2 byte だけを受理したい用途なら長さ条件を `len(bytes) != 2` に変え、余分な入力を拒否するテストも足します。

decode 後も enum の値を検証しています。3 bit の領域には 0–7 を表せますが、プロトコルが認めるのは 1 と 2 だけだからです。型とビット幅だけでは、外部入力が意味的に妥当かまでは保証できません。

書き込む途中で同じ基底整数を読み替える処理が入るので、複数スレッドから異なるフィールドを更新する場合も同期が必要です。フィールドごとに独立した atomic 変数になるわけではありません。

## 2. フラグの集合には bit_set を使う

権限は、`Permission :: enum { Read, Write, Execute }` と `Permissions :: bit_set[Permission; u8]` で定義しています。

<!-- snippet: practice/practice_test.odin#bit-set -->
```odin
allowed := Permissions{.Read, .Write}
testing.expect(t, .Read in allowed)
testing.expect(t, .Execute not_in allowed)
readonly := allowed & Permissions{.Read}
testing.expect_value(t, readonly, Permissions{.Read})
names := [Permission]string{.Read = "r", .Write = "w", .Execute = "x"}
testing.expect_value(t, names[.Write], "w")
```
<!-- /snippet -->

`in` と `not_in` が包含判定、`&` が積集合です。enum を添字にする `[Permission]string` も使え、表示名のような固定の対応を map にしなくて済みます。

サイズや種別のような複数 bit の値を詰めたいなら `bit_field`、名前の付いた要素の集合なら `bit_set`。用途を先に決めると選びやすいです。

## 3. エラーの意味と伝播の規約をそろえる

この例の `Error` は `.None` が 0 の enum です。`parse_count` は整数を読み、入力の末尾まで消費したか、非負か、上限 1,000,000 以下かを確認します。下流で 2 倍する処理の前に上限を決め、overflow を避けています。

<!-- snippet: practice/errors.odin#or-return -->
```odin
doubled_count :: proc(text: string) -> (result: int, err: Error) {
	n := parse_count(text) or_return
	return n * 2, .None
}
```
<!-- /snippet -->

`or_return` が呼び出し結果の末尾を検査し、失敗なら現在の procedure の末尾の戻り値に設定して戻ります。複数戻り値では**すべてに名前が必要**です。

成功したときの `n` は `int`。戻り値が `(int, int, Error)` なら、成功時は先頭の 2 値を受け取れます。エラー値だけを返す呼び出しにも使えます。[公式 or_return](https://odin-lang.org/docs/overview/#or_return-operator)

途中まで出力を組み立ててから失敗した場合、他の名前付き戻り値にはそれまでの値が残りえます。「失敗時の出力は使わない」「失敗時は必ず空を返す」などの契約は自分で決めます。

### bool の成功判定にも使える

<!-- snippet: practice/errors.odin#bool-return -->
```odin
increment_if_integer :: proc(text: string) -> (result: int, ok: bool) {
	n := strconv.parse_int(text) or_return
	if n == max(int) {
		return 0, false
	}
	return n + 1, true
}
```
<!-- /snippet -->

この場合の失敗は `false` です。上限の加算には別途明示的な検査を入れています。この procedure は `strconv.parse_int` の既定の基数推論を使い、10 進数を指定する `parse_count` とは受け入れる文字列の契約が異なります。[core:strconv](https://pkg.odin-lang.org/core/strconv/)

エラー enum と bool の間などで、意味を自動で変換してくれるわけではありません。境界では `if` で変換します。`parse_counts` では allocator のエラーを `.Allocation_Failed` に変換しています。一方、返すエラーの union に元の型が含まれていれば、元の型を保って格納できます。

### 段階の異なる検証をつなぐ

[parse_packet](../practice/packets.odin) は `decode_header`、`take_payload`、`validate_payload` をそれぞれ `or_return` で呼びます。構造、長さ、アプリの許可する内容を分け、最初に失敗した段階のエラーを返します。返す payload は入力の借用で、失敗時には空です。

[parse_dimensions](../practice/dimensions.odin) は、区切り文字を探す処理、幅と高さを 10 進数として変換する処理、値域検証を bool の成功判定でつないでいます。`split_dimensions` の `(string, string, bool)` から先頭の 2 値を受け取れる例でもあります。

### ライブラリごとに違うエラー型を保つ

[load_settings](../practice/settings.odin) は、一時 arena の初期化、`os.read_entire_file`、`json.unmarshal`、設定値の検証を組み合わせています。[Load_Error](../practice/settings_contracts.odin) は allocator、OS、JSON、設定検証のエラーを列挙した union です。

`or_return` は失敗した呼び出しのエラーをこの union に格納します。呼び出し元は `err.(os.Error)` や `err.(json.Unmarshal_Error)` で分類できます。テストでは、ファイル不在、不正な JSON、範囲外のスレッド数とタイムアウトを個別に確認しています。

処理中の allocation は arena へまとめ、成功時にも失敗時にも破棄します。返す `Settings` は整数のコピーです。設定に string や slice を加える場合は、arena を破棄する前に呼び出し元の allocator へ複製する契約も必要になります。

### or_else とループ制御は失敗時の方針で選ぶ

map lookup の `options["threads"] or_else 4` は、キーが存在しなかった場合の既定値です。格納された値が `0` なら `0` のままで、truthiness による判定ではありません。

`or_continue` は失敗した項目をスキップし、`or_break` はループを終了します。これらはエラーの伝播をしません。失敗を記録・集計すべき処理なら、明示的な `if` を使ってログや戻り値へ残します。

## 4. defer をブロックの資源管理に使う

<!-- snippet: practice/practice_test.odin#defer -->
```odin
trace := make([dynamic]int)
defer delete(trace)
{
	value := 10
	defer append(&trace, value)
	defer append(&trace, 20)
	value = 30
	testing.expect_value(t, len(trace), 0)
}
testing.expect_value(t, len(trace), 2)
testing.expect_value(t, trace[0], 20)
testing.expect_value(t, trace[1], 30)
```
<!-- /snippet -->

内側の `{}` を出る前に 20、30 の順で追加されます。procedure 全体の終了まで待たず、`value` は登録時の 10 から変更後の 30 になっています。

| 観点 | Go | Odin の検証例 |
| --- | --- | --- |
| 実行時点 | 関数が戻るとき | 現在のブロックを出るとき |
| `defer f(value)` の引数 | 登録時点で評価 | defer した文を実行するときに評価 |
| 名前付き戻り値の書き換え | defer で変更できる | コピー済みの戻り値には反映されない |

Go 側の引数評価と戻り値の扱いは [Go 言語仕様の Defer statements](https://go.dev/ref/spec#Defer_statements) にあります。

名前付き戻り値へ直接 `defer value = 2` と代入する [反例](../examples/compile-errors/deferred-return/main.odin) はコンパイルで拒否されます。`defer` ブロック内の代入が常に診断されるとは限りませんが、それを戻り値の変更に使う設計にはできません。

登録時の状態を残したい場合は、別のローカル変数へコピーしておきます。その変数自体を後で変更しないようにします。

通常の早期 return と `or_return` では `defer` が実行されます。panic や範囲外アクセスからの後始末まで同じように扱う前提にはできません。テストで必要なら `testing.cleanup` の契約を確認します。[公式 Running Tests](https://odin-lang.org/docs/testing/#testingcleanup)

## 5. 成功時に所有権を渡し、失敗時は手元で片付ける

`parse_counts` の契約は、成功時には呼び出し元が `delete` する dynamic array を返し、失敗時は空を返すことです。

<!-- snippet: practice/errors.odin#owned-array -->
```odin
// Success transfers the backing allocation to the caller. Failure returns nil.
parse_counts :: proc(texts: []string, allocator := context.allocator) -> (items: [dynamic]int, err: Error) {
	buffer, alloc_err := make([dynamic]int, 0, len(texts), allocator)
	if alloc_err != nil {
		return nil, .Allocation_Failed
	}
	defer if err != nil {
		delete(buffer)
	}
	for text in texts {
		n := parse_count(text) or_return
		_, append_err := append(&buffer, n)
		if append_err != nil {
			return nil, .Allocation_Failed
		}
	}
	return buffer, .None
}
```
<!-- /snippet -->

作業用の `buffer` と名前付き戻り値 `items` を分けているのが要点です。途中の `parse_count` が失敗すると、`err` が設定され、`items` は初期値のまま返ります。その後 `defer if err != nil` が `buffer` を解放します。

成功時は `buffer` を返し、callee での解放を行いません。利用例の [tour](../examples/tour/main.odin) が `defer delete(counts)` で片付けています。

返す値に作業中の配列を直接入れておき、失敗時に `defer` で解放してから空にする設計だと、呼び出し元へ解放済みの descriptor を返しかねません。戻り値が defer より先に確定する点と、所有権を同時に考える必要があります。

テストは、正常な複数要素、途中の不正入力、空入力、小さな allocator での確保失敗を含みます。`ODIN_TEST_FAIL_ON_BAD_MEMORY=true` で、検出されたリークと不正な解放もテスト失敗にしています。[公式テストランナー](https://odin-lang.org/docs/testing/)

## 6. allocator の寿命を API に書く

`context.allocator` を上書きすると、そのスコープから呼ぶ通常の Odin procedure の既定の確保先を切り替えられます。`new`、`make`、allocator 引数を持つライブラリの多くがこの仕組みを使います。スコープや呼び出し元に戻ると、そちらの context が使われます。

この仕組みは Odin calling convention のものです。C ABI の callback に同じ context が自動で渡るとは考えず、必要な状態を明示的に受け渡します。[公式 Context system](https://odin-lang.org/docs/overview/#implicit-context-system)

### 一時 arena からの結果は所有する領域へコピーする

<!-- snippet: practice/memory.odin#scratch -->
```odin
clone_via_scratch :: proc(input: string, output_allocator: mem.Allocator) -> (result: string, err: mem.Allocator_Error) {
	buffer: [1024]byte
	arena: mem.Arena
	mem.arena_init(&arena, buffer[:])
	context.allocator = mem.arena_allocator(&arena)

	scratch := strings.clone(input) or_return
	// Copy into caller-owned storage before the local buffer's lifetime ends.
	return strings.clone(scratch, output_allocator)
}
```
<!-- /snippet -->

この arena はローカルの固定長 buffer を使います。buffer の寿命が procedure 内に限られるので、`scratch` をそのまま返すと無効なメモリを参照します。最後に `output_allocator` へ複製して、返す文字列の寿命を呼び出し元へ移しています。

`output_allocator` の渡し手も、その allocator と返された allocation の寿命を守る必要があります。返す allocator 自体が短命な arena なら、結果もその arena の寿命を越えられません。通常の heap allocator へ確保した文字列は、呼び出し元が `delete(result)` します。[core:mem の Arena](https://pkg.odin-lang.org/core/mem/)、[strings.clone](https://pkg.odin-lang.org/core/strings/#clone)

入力が長くて 1024 byte の一時領域に収まらなければ、この例は allocator エラーを返します。実アプリで必要なら、[core:mem/virtual](https://pkg.odin-lang.org/core/mem/virtual/) の growing arena などを選びます。固定 buffer の例と、OS から領域を取る arena では初期化・破棄の契約が違います。

`context.temp_allocator` も無期限に有効な保存先には使いません。リセットするタイミングを決め、そこから作った string や slice を長く保持しないようにします。

## 7. slice と dynamic array のコピーを所有権のコピーと混同しない

| 型 | この例での役割 |
| --- | --- |
| `[N]T` | 要素を持つ固定長の値 |
| `[]T` | 連続した要素の借用 view |
| `[dynamic]T` | 要素領域、長さ、容量、allocator を管理する可変長配列 |

<!-- snippet: practice/practice_test.odin#dynamic-alias -->
```odin
owner := make([dynamic]int, 0, 4)
defer delete(owner)
append(&owner, 10)
alias := owner
append(&owner, 20) // within capacity: intentionally does not reallocate
testing.expect_value(t, len(owner), 2)
testing.expect_value(t, len(alias), 1)
alias[0] = 99
testing.expect_value(t, owner[0], 99)
view := owner[:]
view[1] = 88
testing.expect_value(t, owner[1], 88)
```
<!-- /snippet -->

`alias := owner` は要素を複製しません。長さなどの descriptor がコピーされ、要素領域を共有します。この例では再確保しないよう容量を 4 に固定しており、`owner` の長さが 2 になっても `alias` の長さは 1 のままです。

`alias` から要素を書き換えると `owner` からも見えます。両方を `delete` すると二重解放になります。容量を越える `append` で再確保が起きたら、既存の alias、slice、要素へのポインタは無効になりえます。

自分が使う API では、所有する dynamic array を一か所で管理し、読み書きだけをする procedure には `[]T` を渡す方針にします。要素が struct や string の場合も、コンテナを解放すれば中身の所有する領域まで再帰的に解放されるとは限りません。

## 8. union と distinct で API の状態を表す

`Resize :: struct { columns: int }`、`Input :: struct { bytes: string }`、`Event :: union { Resize, Input }` を定義しています。

<!-- snippet: practice/data.odin#tagged-union -->
```odin
event_amount :: proc(event: Event) -> int {
	switch e in event {
	case Resize:
		return e.columns
	case Input:
		return len(e.bytes)
	case nil:
		return 0
	}
	return 0
}
```
<!-- /snippet -->

この `union` はタグ付きで、variant とそのデータをまとめます。未設定の `Event` は `nil` なので、空のケースも扱っています。`#raw_union` は別物で、C の union のようにタグを持たない表現です。[公式 Unions](https://odin-lang.org/docs/overview/#unions)

`Input.bytes` の string は所有権を表しません。ここでは借用です。イベントをキューに長く保持するなら、文字列の保存先と寿命も別に決めます。union に入れるだけで元のメモリの寿命が延びることはありません。

`User_ID :: distinct u64` は基底表現が `u64` の別型です。既に型が付いた `u64` の変数を代入するには明示的な変換が必要です。`User_ID :: u64` なら単なる alias になります。なお、型を持たない整数リテラルまで必ず明示的 cast が必要になる、という意味ではありません。

## 9. データ配置はアクセスする列から考える

`Particle :: struct { x, y, z: f32 }` を使って、`#soa` の列と要素の記法が同じ領域を参照することをテストしています。

<!-- snippet: practice/practice_test.odin#soa -->
```odin
// snippet: soa-access
particles: #soa[2]Particle
particles[0] = Particle{1, 2, 3}
particles[1] = Particle{4, 5, 6}
particles.x[0] += 10
```
<!-- /snippet -->

通常の `[N]Particle` は Particle 単位でデータが並び、`#soa[N]Particle` は x、y、z の列ごとに並びます。x だけを大量に処理するなら SoA が候補になります。一つの要素の全フィールドを使うなら、通常の配列が扱いやすい場合もあります。

レイアウトの違いはこのテストで確認できますが、速度は測っていません。採用判断では、実際の処理とデータ数を使って AoS と SoA を比較します。`#soa` は所有権や並行アクセスの保証を追加する機能ではありません。

### 配列演算と行列演算は区別する

<!-- snippet: practice/practice_test.odin#array-matrix -->
```odin
a := [3]f32{1, 2, 3}
b := [3]f32{4, 5, 6}
testing.expect_value(t, a * b, [3]f32{4, 10, 18})
testing.expect_value(t, swizzle(a, 2, 0), [2]f32{3, 1})
m := matrix[2, 2]f32{1, 2, 3, 4}
n := matrix[2, 2]f32{5, 6, 7, 8}
product := m * n
testing.expect_value(t, product[0, 0], 19)
testing.expect_value(t, product[1, 1], 50)
```
<!-- /snippet -->

配列の `*` は各成分の積、matrix の `*` は行列積です。`swizzle(a, 2, 0)` は 3 番目と 1 番目の成分を選びます。matrix の初期化子はこの例のように行を順に書き、`[行, 列]` で参照します。内部表現の配置と初期化子の記述順は分けて考え、FFI に渡す場合はサイズ・alignment・列方向の配置を確認します。[公式 Matrix](https://odin-lang.org/docs/overview/#matrix-type)

## 10. 型パラメータとオーバーロードの候補を明示する

<!-- snippet: practice/data.odin#polymorphism -->
```odin
identity :: proc(value: $T) -> T {
	return value
}

twice_i32 :: proc(value: i32) -> i32 { return value * 2 }
twice_f32 :: proc(value: f32) -> f32 { return value * 2 }
twice :: proc{twice_i32, twice_f32}
```
<!-- /snippet -->

`$T` は入力から推論される型パラメータです。`identity(User_ID(42))` の戻り値も `User_ID` になり、基底の `u64` に消えません。`twice` の候補は `proc{...}` の中で列挙しています。

数値型に限定するような制約には `where` と型情報を使えます。まずは必要な型の範囲を決め、実際に呼ぶ型でテストを用意するところから始めます。[公式 Parametric polymorphism](https://odin-lang.org/docs/overview/#parametric-polymorphism)

Go の interface とメソッド集合をそのまま移す設計にはせず、必要に応じて型パラメータ、タグ付き union、procedure の引数を使い分けます。procedure を値として渡すことはできますが、外側のローカル変数を捕捉する closure はありません。[捕捉に失敗する例](../examples/compile-errors/captured-local/main.odin) も検査対象です。

## 11. 小さな開発ループを固定する

```sh
odin check examples/tour -vet
odin run examples/tour
odin test practice -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true
```

このワークスペースでは `just verify` にまとめています。新しい処理を足すときは、入力と失敗時の契約を決め、テストが落ちることを確認してから実装します。メモリを返す API には、成功時の解放方法と失敗時の出力を併記します。

`@(test)` の procedure は `^testing.T` を一つ受け取ります。テストランナーにはメモリ追跡があり、`-define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true` を付けることで検出した問題を失敗にできます。arena 内部の論理的な寿命違反までこの追跡だけで網羅できるわけではないので、arena の所有者とリセット地点はコードでも分かるようにします。[公式 Running Tests](https://odin-lang.org/docs/testing/)

依存を追加するときは、公式 [core](https://pkg.odin-lang.org/core/) と [vendor](https://pkg.odin-lang.org/vendor/) をまず確認します。外部依存は取得元、固定した revision、license、更新方法を記録します。コンパイラにも core/vendor が同梱されるため、コンパイラの更新も依存の更新として扱います。

## 12. 次に手を動かすなら

1. ヘッダに version を加え、旧版と新版を decode する。未対応版の拒否を先にテストする。
2. `decode_header` と payload をつなぎ、長さ不足と余剰 byte の契約を決める。
3. `parse_counts` を richer なエラー型へ変え、失敗した要素の index と元の原因を保持する。
4. arena をリクエスト単位にし、長期保存する値だけ別 allocator へ複製する。
5. 同じ更新ループを AoS と SoA で書き、対象の件数・アクセス方法で測定する。

学習時の索引には公式 [demo.odin](https://github.com/odin-lang/Odin/blob/master/examples/demo/demo.odin) を使い、API の引数・戻り値は [パッケージドキュメント](https://pkg.odin-lang.org/) と利用中の配布版のソースで確認します。
