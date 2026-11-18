# Odin の基礎 数値 データ処理ライブラリ

## メモリとコンテナの充実は何に表れているか

### Takeaway

特に充実しているのは、メモリの寿命・配置・割り当て方を用途ごとに選ぶ仕組み。単にmallocのラッパーがあるという水準を超え、固定バッファArena、scratch/stack、動的Arena、buddy、TLSF、trackingが同じAllocator契約に接続される。コンテナもゲームやツールで扱いやすい、固定容量・ハンドル・プールなどの選択肢がある。

### Cited Findings

- 調査対象のローカル版は 2026-11-03 配布の macOS ARM64 版、コンパイラ表示は `dev-2026-11-nightly:9a69916`。以下のローカルソース確認と、2026-11-18に閲覧した公式APIの内容は区別した。APIページにはキャッシュや生成日時の差があるため、公式Webの全APIをこの配布版が持つとは限らない。— [配布済みコンパイラ](https://github.com/odin-lang/Odin/releases/tag/dev-2026-11a)、[core API](https://pkg.odin-lang.org/core/)
- `mem.Arena` は呼び出し側から `[]byte` を渡して初期化できる。`arena_alloc_bytes` はalignmentを指定でき、通常版ではゼロ初期化、`*_non_zeroed` ではゼロ埋めを省略する。`arena_free_all`、一時領域のbegin/endもあり、短い寿命のデータをまとめて捨てる設計ができる。— [mem API](https://pkg.odin-lang.org/core/mem/)、[ローカル実装 allocators.odin:186](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/mem/allocators.odin#L186)
- 基本のArena以外に `Scratch`、`Stack`、`Small_Stack`、`Dynamic_Arena`、`Buddy_Allocator`、`Rollback_Stack`、nil/panic allocatorを実装。`context.allocator` の差し替えが呼び出し先へ伝播する設計と、明示的なallocator引数の両方が使える。— [mem API](https://pkg.odin-lang.org/core/mem/)、[ローカル allocators.odin](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/mem/allocators.odin)、[Rollback Stack](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/mem/rollback_stack_allocator.odin)
- `Tracking_Allocator` は、backing allocatorへ委譲しながらポインタ別の割り当て情報をmapに記録する。総割り当て量・解放量・回数・現在量・ピーク量を保持し、未知のポインタへのfreeをcallbackで扱える。実装にはmutexと内部用allocatorもあり、「検査機構も無料ではない」ことがソースから分かる。— [Tracking_Allocator API](https://pkg.odin-lang.org/core/mem/#Tracking_Allocator)、[ローカル tracking_allocator.odin:45](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/mem/tracking_allocator.odin#L45)
- `mem/tlsf` はTwo Level Segregated FitのOdinソース実装。固定バッファからの初期化、backing allocatorからの初期化、必要時の追加プール、割り当て・resize・freeを提供する。全モードを無条件にサポートする契約ではなく、例えばQuery_Infoは未実装を返す。— [TLSF API](https://pkg.odin-lang.org/core/mem/tlsf/)、[公式実装](https://github.com/odin-lang/Odin/blob/master/core/mem/tlsf/tlsf.odin)、[ローカル tlsf.odin](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/mem/tlsf/tlsf.odin)
- `handle_map` は静的配列と動的Xarの2実装を持つ。ハンドルにはindexとgenerationがあり、スロット再利用時に世代を進める。参照時はハンドル全体を照合し、削除済みハンドルを検出できる。静的版はindex 0をsentinelに使うため、要素数Nに対して容量はN−1。— [handle_map API](https://pkg.odin-lang.org/core/container/handle_map/)、[ローカル static_handle_map.odin:30](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/container/handle_map/static_handle_map.odin#L30)
- `Queue(T)` は動的な両端queue/ring bufferで、allocatorを指定した初期化に加え、固定の `[]T` をbackingとする初期化も持つ。固定backingで容量を超えるpushは失敗する。AVL/red-black tree、intrusive list、LRU、priority queue、pool、bit array、topological sortなどもある。— [Queue API](https://pkg.odin-lang.org/core/container/queue/)、[ローカル queue.odin:42](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/container/queue/queue.odin#L42)、[container一覧](https://pkg.odin-lang.org/core/)
- `container/small_array` は現在、組み込みの固定容量動的配列 `[dynamic; N]T` を推奨する非推奨パッケージ。名前が残っていることと、現行の推奨APIであることは別。— [small_array API](https://pkg.odin-lang.org/core/container/small_array/)、[ローカルdoc](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/container/small_array/doc.odin)
- `mem/virtual` はOSのreserve/commit/decommitやmmapを扱う別の層。Wasmなどの `virtual_other.odin` ではreserveがnil、protectがfalse、map_fileがMap_Failureとなる。Wasmで使える固定バッファArenaと、OS仮想メモリArenaを混同しない。— [virtual API](https://pkg.odin-lang.org/core/mem/virtual/)、[ローカル virtual_other.odin](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/mem/virtual/virtual_other.odin)、[公式フォールバック実装](https://github.com/odin-lang/Odin/blob/master/core/mem/virtual/virtual_other.odin)

### Inferences

- ゲームのフレーム単位の一時データ、コンパイラのフェーズ単位のデータ、オブジェクトのハンドル管理など、寿命や容量をアプリ側で決めたい処理に向く。これはArena・世代付きハンドル・固定backing queueの組み合わせからの評価で、速度のベンチマーク結果ではない。— [Arena](https://pkg.odin-lang.org/core/mem/#Arena)、[handle_map](https://pkg.odin-lang.org/core/container/handle_map/)、[Queue](https://pkg.odin-lang.org/core/container/queue/)

### Gaps

- allocator間の速度・断片化・実運用での成熟度は、この調査ではベンチマークしていない。
- 全コンテナのWasm動作を実行検証したわけではない。固定容量とOS依存の少なさは、Wasm対応の一律保証ではない。

## 数学はどの用途に深いか

### Takeaway

`math/linalg` は3D空間変換に特に深い。ベクトル基本演算から、quaternion、カメラ行列、射影、Euler角変換、逆行列まで実装があり、ゲーム・可視化・グラフィックスの計算部を自前で一式揃える負担を減らせる。

### Cited Findings

- パッケージの目的は3D空間変換用の線形代数。f16/f32/f64のvector・matrix・quaternion系と、GLSL/HLSL風のAPIがある。公式APIの宣言数は型・精度別展開も含むので、その数字だけで機能の深さを評価していない。— [linalg API](https://pkg.odin-lang.org/core/math/linalg/)、[GLSL風API](https://pkg.odin-lang.org/core/math/linalg/glsl/)、[HLSL風API](https://pkg.odin-lang.org/core/math/linalg/hlsl/)
- dot/cross/normalizeなどは型パラメータを用いる `proc "contextless"` として実装。quaternion normalizeやvector slerp、逆行列などの処理が、単なる外部Cライブラリ宣言ではなくOdinコードとして入っている。— [linalg general.odin](https://github.com/odin-lang/Odin/blob/master/core/math/linalg/general.odin)、[ローカル general.odin:78](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/math/linalg/general.odin#L78)
- quaternionの球面線形補間 `quaternion_slerp_f32` には、内積が負なら向きを反転する処理、ほぼ平行な場合の線形補間、通常の三角関数を使う補間がある。API名だけでなく回転補間を実際に実装している。— [quaternion_slerp API](https://pkg.odin-lang.org/core/math/linalg/#quaternion_slerp)、[ローカル specific.odin:822](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/math/linalg/specific.odin#L822)
- 変換行列のtranslate/scale、look_at、perspectiveなどをf16/f32/f64で提供し、Euler角の順序別変換もある。カメラ・投影・回転の接続部分まで揃う点が特徴。— [linalg API](https://pkg.odin-lang.org/core/math/linalg/)、[ローカル specific.odin:1992](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/math/linalg/specific.odin#L1992)、[Euler角実装](https://github.com/odin-lang/Odin/blob/master/core/math/linalg/specific_euler_angles_f32.odin)
- 逆行列は定サイズ専用の実装に加え、任意のN×Nに対するGauss-Jordanと部分ピボット付きLU分解の実装がある。Gauss-Jordan版は特異行列をboolで返す。— [linalg general.odin](https://github.com/odin-lang/Odin/blob/master/core/math/linalg/general.odin)、[ローカル general.odin:1033](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/math/linalg/general.odin#L1033)
- 周辺に `math/noise` の2D〜4Dノイズ、`math/ease` の補間曲線・逆関数、fixed point、複素数、任意精度整数・有理数などがある。数学の中でも、空間変換やアニメーションに直接使える構成が目立つ。— [math API](https://pkg.odin-lang.org/core/math/)、[noise API](https://pkg.odin-lang.org/core/math/noise/)、[ease API](https://pkg.odin-lang.org/core/math/ease/)、[big API](https://pkg.odin-lang.org/core/math/big/)
- 行列・quaternion・SIMD・SOAは言語側にも表現がある。ライブラリ独自のheap objectとしてしか扱えないという構造ではない。— [言語Overviewのmatrix](https://odin-lang.org/docs/overview/#matrix-type)、[SIMD](https://odin-lang.org/docs/overview/#simd-vector-types)、[SOA](https://odin-lang.org/docs/overview/#soa-data-types)

### Inferences

- 「ゲーム・グラフィックス向け数学が特に充実」と評価できる。これは射影行列、視点変換、回転補間、ノイズ、easingが一緒に提供されることからの評価。— [linalg](https://pkg.odin-lang.org/core/math/linalg/)、[noise](https://pkg.odin-lang.org/core/math/noise/)、[ease](https://pkg.odin-lang.org/core/math/ease/)
- 純粋な算術中心の処理はOSとの結び付きが小さい一方、最終的なWasmサイズは三角関数・型展開・選択した操作によって異なる。前のbit_field等の0 B増分を数学全般に外挿すべきではない。— [quaternion slerpの実装](https://github.com/odin-lang/Odin/blob/master/core/math/linalg/specific.odin)

### Gaps

- BLAS/LAPACK相当の範囲、疎行列、最適化・統計・数値解析全般の網羅性は評価していない。3D数学の充実と科学計算環境全体の充実を同一視しない。
- 数値精度・SIMD化・各精度の処理速度をベンチマークしていない。

## 文字列 エンコーディング 圧縮はどこまで揃うか

### Takeaway

JSON/CBOR/CSV、文字列Builder、UTF変換、正規表現、Deflate/LZ4など、ファイル形式やアセット処理の道具は広く揃う。ただし形式ごとの対称性は異なる。XMLは読み取り中心、旧gzip/zlibパッケージは非推奨で、公式Webの新しい圧縮実装は手元版に未同梱のものもある。

### Cited Findings

- JSONは `Value` としてのparse/unparseと、Odin型へのmarshal/unmarshalの双方を持つ。出力先はbytes/Builder/Writerを選べ、JSON5/MJSONの設定や整形などもある。型のmarshal/unmarshal実装は `core:reflect` と `type_info_of` を利用する。— [JSON API](https://pkg.odin-lang.org/core/encoding/json/)、[ローカル marshal.odin:1](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/encoding/json/marshal.odin#L1)、[ローカル unmarshal.odin:1](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/encoding/json/unmarshal.odin#L1)
- CBORはValue系encode/decodeと型のmarshal/unmarshal、Writer/Reader、診断表現、拡張tagを持つ。数値の最小表現とmapキー順序を制御するdeterministicモードを用意し、mapのソートには一時メモリと時間のコストがあると明示。通常のdecode時の割り当て先も指定できる。— [CBOR API](https://pkg.odin-lang.org/core/encoding/cbor/)、[ローカルdoc](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/encoding/cbor/doc.odin)
- CSVはReader/Writer双方を提供し、INIには文字列からのloadと文字列へのsave、HXAにはread/writeがある。base32/base64/hex/endian/varint等の低レベル変換もcoreにある。— [CSV API](https://pkg.odin-lang.org/core/encoding/csv/)、[INI API](https://pkg.odin-lang.org/core/encoding/ini/)、[HXA API](https://pkg.odin-lang.org/core/encoding/hxa/)、[encoding一覧](https://pkg.odin-lang.org/core/)
- XMLはパーサ中心。ローカルdocは仕様の実用的なsubsetと説明し、UTF-16非対応・DTDのELEMENT/ATTLIST非対応を記す。現在の公式master docはXML 1.0第5版の整形式検査を説明する内容へ変わっているが、入力UTF-8、DOCTYPE内部subsetのスキップ、writerとOdin型のserialize/deserializeは今後候補という制約は残る。HTMLパーサでもない。— [XML API](https://pkg.odin-lang.org/core/encoding/xml/)、[現在の公式doc](https://github.com/odin-lang/Odin/blob/master/core/encoding/xml/doc.odin)、[ローカルdoc](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/encoding/xml/doc.odin)
- strings.Builderは通常の動的bufferだけでなく、slice backingによる初期化も持ち、write_string/write_rune/整数出力などを提供。UTF-8/UTF-16変換とUnicode属性・case foldingもある。i18nはgettext MOやQt TS等のcatalogを読み、数量に応じた翻訳形をユーザー指定pluralizerで選べる。— [strings API](https://pkg.odin-lang.org/core/strings/)、[unicode API](https://pkg.odin-lang.org/core/unicode/)、[i18n API](https://pkg.odin-lang.org/core/text/i18n/)、[ローカルi18n doc](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/text/i18n/doc.odin)
- regexは選択・文字クラス・繰り返し・capture/non-capture・非貪欲・anchor等を実装。ただし `\d`/`\s`/`\w` はUnicodeモードでもASCII相当と明示。パーサ・コンパイラ・optimizer・VMの各実装があるが、PCRE全互換などを宣言したものではない。— [Regex API](https://pkg.odin-lang.org/core/text/regex/)、[ローカルdoc](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/text/regex/doc.odin)
- ローカル `compress/deflate` はraw Deflate/zlib/gzipの圧縮・展開を持つ。圧縮先は事前確保sliceとdynamic arrayを選べ、圧縮levelを指定できる。`compress/lz4` はblock/frame双方を圧縮・展開、shocoは短い文字列向け。旧 `compress/gzip` と `compress/zlib` のdocは `compress/deflate` への移行を推奨する。— [Deflate API](https://pkg.odin-lang.org/core/compress/deflate/)、[ローカル deflate.odin:7](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/compress/deflate/deflate.odin#L7)、[LZ4 API](https://pkg.odin-lang.org/core/compress/lz4/)、[gzip doc](https://github.com/odin-lang/Odin/blob/master/core/compress/gzip/doc.odin)、[zlib doc](https://github.com/odin-lang/Odin/blob/master/core/compress/zlib/doc.odin)
- **版差は重要**：ローカルcore/compressのサブディレクトリは deflate/gzip/lz4/shoco/zlib の5つ。閲覧日の公式APIにはBZip2、LZMA/LZMA2、PPMd、legacy PKZIP、filtersも掲載される。BZip2はcompress/decompress API、LZMAは`.lzma`/raw LZMA/raw LZMA2のread/write、PPMdは7z/zip系raw streamのread/writeを公式docで確認した。これらが手元の11月3日配布版で使えるとは言えない。— [compress索引](https://pkg.odin-lang.org/core/compress/)、[BZip2 API](https://pkg.odin-lang.org/core/compress/bzip2/)、[LZMA API](https://pkg.odin-lang.org/core/compress/lzma/)、[PPMd API](https://pkg.odin-lang.org/core/compress/ppmd/)、[ローカルcompress](https://github.com/odin-lang/Odin/tree/9a6991685ddf663956d9836602eb421e141fc443/core/compress)

### Inferences

- 「ゲーム用アセット、設定、バイナリ通信形式、ツールの入出力に使う道具が広い」という評価が妥当。読み書き、割り当て先、buffer/stream、決定的出力を選べるAPIが揃う一方、XMLのように読み取りに寄ったものもある。— [CBOR](https://pkg.odin-lang.org/core/encoding/cbor/)、[CSV](https://pkg.odin-lang.org/core/encoding/csv/)、[Deflate](https://pkg.odin-lang.org/core/compress/deflate/)、[XML](https://pkg.odin-lang.org/core/encoding/xml/)
- JSON/CBORの便利な型marshalは反射と動的な割り当てを含むため、以前測った数百Bの純粋整数演算と同じサイズ特性とは限らない。固定bufferやWriter指定はメモリ制御の選択肢であり、自動的な小バイナリ保証ではない。— [JSON marshal実装](https://github.com/odin-lang/Odin/blob/master/core/encoding/json/marshal.odin)、[CBOR unmarshal実装](https://github.com/odin-lang/Odin/blob/master/core/encoding/cbor/unmarshal.odin)

### Gaps

- この担当では上記APIの網羅的な動作・適合性・performanceテストを行っていない。API/実装を読んだ充実度の評価で、成熟度やバグの少なさを保証しない。
- Unicode正規化、言語ごとのcollation、完全なtext shapingなどは網羅調査していない。regexにUnicodeモードがあることだけで、すべての文字処理が揃うとは判断しない。
- 現在の公式APIは11月17日生成と表示されるページと古いキャッシュのページが混在した。版差を比較する際は、パッケージ数ではなく対象APIがローカルに存在するかを基準にした。
