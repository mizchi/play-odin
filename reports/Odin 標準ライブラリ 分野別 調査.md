# Odin の標準はメモリ制御と制作ツールを厚く支える

Odin の標準ライブラリは、**メモリの寿命・配置を制御する処理、ゲーム・3D向け数学、ネイティブの制作ツール**に特に強いと評価できる。根拠はパッケージ数より、allocator の差し替え、固定バッファ、世代付きハンドル、空間変換、ソース解析まで踏み込んだ API と実装にある。同梱の `vendor:` まで含めると、描画・入力・音声・物理・アセット処理の連携も厚い。一方、HTTPサービスやDB利用を高水準の統一 API まで標準だけで完結させる方向は薄い。暗号は実装範囲が広いが、安全性評価や対象環境には明示的な制約がある。本調査は **2026-11-18** に、手元の11月3日配布版 `dev-2026-11-nightly:9a69916` のソースと公式 API を確認したもので、両者を同一の版として扱っていない。以下の「充実」は機能範囲と設計の深さの評価であり、性能・バグ率・全ターゲットでの成熟度の評価ではない。

## メモリとデータ配置を決める部品が深い

| 層・領域 | 評価 | 実装から分かる強みと境界 |
| --- | --- | --- |
| core：メモリ | 特に厚い | 固定バッファArena、scratch/stack、dynamic arena、buddy、trackingが同じAllocator契約に接続する。TLSFもOdin実装で提供。([mem](https://pkg.odin-lang.org/core/mem/)、[TLSF](https://pkg.odin-lang.org/core/mem/tlsf/)) |
| core：数学・3D | 特に厚い | quaternion補間、視点・射影行列、Euler角変換、逆行列まで揃う。周辺にnoise/easingもある。([linalg](https://pkg.odin-lang.org/core/math/linalg/)、[noise](https://pkg.odin-lang.org/core/math/noise/)、[ease](https://pkg.odin-lang.org/core/math/ease/)) |
| core：コンテナ | 容量・寿命の制御に強い | 世代付きhandle_map、固定sliceをbackingにできるqueue、pool、AVL/RB treeなど。([handle_map](https://pkg.odin-lang.org/core/container/handle_map/)、[queue](https://pkg.odin-lang.org/core/container/queue/)) |
| core：データ入出力 | 広いが形式ごとに差がある | JSON/CBORは型への読み書きとallocator制御、CSVはReader/Writer。XMLはparser中心。([JSON](https://pkg.odin-lang.org/core/encoding/json/)、[CBOR](https://pkg.odin-lang.org/core/encoding/cbor/)、[CSV](https://pkg.odin-lang.org/core/encoding/csv/)、[XML](https://pkg.odin-lang.org/core/encoding/xml/)) |
| core：CLI・言語ツール | 特徴的に厚い | 構造体からの引数解析、メモリ追跡付きテスト、Odinのparser/AST/formatter、命令encoder/decoderを同梱。([flags](https://pkg.odin-lang.org/core/flags/)、[testing](https://pkg.odin-lang.org/core/testing/)、[parser](https://pkg.odin-lang.org/core/odin/parser/)、[rexcode](https://pkg.odin-lang.org/core/rexcode/)) |
| core：OS・並行処理 | nativeの基盤が揃う | ファイル・子プロセス・ソケット・DNS、thread/pool、同期・チャネル、nbio。ただしWasmは別評価。([os](https://pkg.odin-lang.org/core/os/)、[net](https://pkg.odin-lang.org/core/net/)、[thread](https://pkg.odin-lang.org/core/thread/)、[nbio](https://pkg.odin-lang.org/core/nbio/)) |
| vendor：ゲーム・描画連携 | 特に厚い | Raylib、SDL、Vulkan/OpenGL/wgpu、画像・フォント・音声・物理など。多くは外部ライブラリへのバインディング。([vendor](https://pkg.odin-lang.org/vendor/)) |
| core：暗号 | 範囲は広い、採用条件は要確認 | AEAD、KDF、公開鍵、耐量子暗号、X.509まである。READMEが独立第三者レビュー等の制約を明記。([crypto](https://pkg.odin-lang.org/core/crypto/)、[README](https://github.com/odin-lang/Odin/blob/master/core/crypto/README.md#L10-L27)) |

メモリ分野では、`Arena` に呼び出し側の `[]byte` を渡せるだけでなく、alignment、ゼロ初期化の有無、一時領域の巻き戻しを選べる。`Tracking_Allocator` は現在量・ピーク量・割り当て履歴や不正なfreeを追跡する。フレーム単位の一時データ、パーサの処理段階ごとのデータなど、寿命をアプリ側で決める設計を直接支える。これは API と実装からの用途評価で、速度を測った結果ではない。([Arenaと各allocator](https://pkg.odin-lang.org/core/mem/)、[tracking実装](https://github.com/odin-lang/Odin/blob/master/core/mem/tracking_allocator.odin))

コンテナにも同じ方針が表れる。`handle_map` はindexとgenerationを照合して削除済みハンドルを検出し、queueは固定容量のbackingを指定できる。数学では、回転補間の `quaternion_slerp`、`look_at`、`perspective` から、Gauss–Jordanや部分ピボット付きLUによる逆行列まで実装されている。**ゲーム・可視化の計算基盤が厚い**という評価はできるが、科学計算環境全般の網羅性まで確認したわけではない。([handle_map](https://pkg.odin-lang.org/core/container/handle_map/)、[queue](https://pkg.odin-lang.org/core/container/queue/)、[線形代数実装](https://github.com/odin-lang/Odin/blob/master/core/math/linalg/general.odin))

## 設定・アセット処理から言語ツール制作まで届く

JSONは汎用の `Value` とOdin型へのmarshal/unmarshalの両方を持ち、CBORもReader/Writer、allocator指定、決定的な出力形式を提供する。文字列BuilderやUTF変換、正規表現も揃う。ただし、JSON/CBORの便利な型変換は反射を使う。XMLは読み取りに寄っており、writerやOdin型のserialize/deserializeは今後の候補とされる。正規表現の `\d`・`\s`・`\w` はUnicodeモードでもASCII相当という制約がある。**形式名が揃っていても、読み書きの対称性や互換範囲は一様ではない。**([JSON実装](https://github.com/odin-lang/Odin/blob/master/core/encoding/json/marshal.odin)、[CBOR](https://pkg.odin-lang.org/core/encoding/cbor/)、[XMLの仕様](https://github.com/odin-lang/Odin/blob/master/core/encoding/xml/doc.odin)、[regex](https://pkg.odin-lang.org/core/text/regex/))

圧縮は手元版でDeflate/zlib/gzipとLZ4の圧縮・展開を確認した。事前確保bufferと動的配列、圧縮levelなどを選べる。旧 `compress/gzip`・`compress/zlib` は `compress/deflate` への移行が案内される。現在の公式にはBZip2、LZMA、PPMd等も掲載されるが、**これらは手元の11月3日版にはない**。公式APIの索引・個別ページにも更新時点の差があり、利用する版のソースで存在を確認する必要がある。([Deflate](https://pkg.odin-lang.org/core/compress/deflate/)、[LZ4](https://pkg.odin-lang.org/core/compress/lz4/)、[gzipの移行案内](https://github.com/odin-lang/Odin/blob/master/core/compress/gzip/doc.odin)、[現在の圧縮索引](https://pkg.odin-lang.org/core/compress/))

CLI向けの `flags` は構造体のRTTI・タグから位置引数、必須値、enum、独自変換やヘルプを扱う。`testing` はメモリ追跡、再現用seed、JSONレポートを持つ。ただし、追跡が有効なことと、リークを自動的にテスト失敗にすることは別で、後者は設定が必要だ。さらにOdinのtokenizer/AST/parser/printer/formatや、複数ISAの命令を扱う `rexcode` もある。**変換器、アセット処理器、言語ツールを作るための部品**が標準に入る点は目立つ。([flags](https://pkg.odin-lang.org/core/flags/)、[testing設定](https://github.com/odin-lang/Odin/blob/master/core/testing/doc.odin)、[core/odin](https://github.com/odin-lang/Odin/tree/master/core/odin)、[rexcode](https://pkg.odin-lang.org/core/rexcode/))

## ネイティブのアプリ基盤とゲーム連携が厚い

`os` の子プロセスAPIは引数、環境、作業ディレクトリ、標準入出力の指定、出力の取得、待機timeoutまで扱う。`io.Stream` にはread/write/seekと合成用API、`net` にはTCP/UDP、DNS、URL処理がある。一方、今回調べた手元core全ディレクトリと公式索引には、**専用のHTTP client/serverやSQL/DBパッケージは見つからなかった**。これは調査範囲内のcoreについての判定であり、TLSや外部エコシステム、`vendor:curl` の不存在を意味しない。([process実装](https://github.com/odin-lang/Odin/blob/master/core/os/process.odin)、[io](https://pkg.odin-lang.org/core/io/)、[net](https://pkg.odin-lang.org/core/net/)、[core索引](https://pkg.odin-lang.org/core/)、[curl](https://pkg.odin-lang.org/vendor/curl/))

並行処理もnativeでは、OSスレッド・pool、Mutex/RW_Mutex、Wait_Group、Barrier、型付きチャネル、コールバック型の `nbio` がある。**macOS ARM64で実スレッドのcreate/start/join/destroyと、nbio.next_tick→runの最小例を実行し、両方exit 0を確認した。** 前回のWASI向けnbioの型検査失敗を、Odinの非同期処理全般の欠如へ一般化するのは不正確である。JS/WASI向けの `core:thread` は未対応で、OS APIにもstubがあるため、ターゲットごとの確認が必要になる。([thread](https://pkg.odin-lang.org/core/thread/)、[sync](https://pkg.odin-lang.org/core/sync/)、[chan](https://pkg.odin-lang.org/core/sync/chan/)、[nbio](https://pkg.odin-lang.org/core/nbio/)、[threadのWasm実装](https://github.com/odin-lang/Odin/blob/master/core/thread/thread_other.odin)、[実行記録](<../research_notes/Odin 標準ライブラリ 分野別 調査/platform.md>))

同梱 `vendor:` はcoreと区別したい。描画・ウィンドウだけでなく、画像、glTF、フォント、音声、Box2D/Box3D、ENet/GGPO、Luaまで連携対象が広い。多くはCライブラリのバインディングで、一部にOdinへの移植もある。wgpuはブラウザWebGPU連携を提供するが、nativeバイナリの準備、Wasmの関数テーブルやallocator等の条件がある。「配布に入っている」は「Odin実装だけで全ターゲットのリンクが完了する」と同義ではない。([vendorの位置付け](https://github.com/odin-lang/Odin/blob/master/vendor/README.md)、[wgpuの準備と対応](https://pkg.odin-lang.org/vendor/wgpu/))

## 暗号の広さとWasmへの適性は別に評価する

暗号はSHA系だけでなく、AEAD、KDF、RSA/ECDSA/Ed25519、Noise、ML-KEM/ML-DSA、X.509までOdin実装がある。サイズ調整の観点では、大きな事前計算テーブルを省く `ODIN_CRYPTO_COMPACT` もある。ただしREADMEは、非スレッド安全、64 bit整数演算の前提、独立第三者レビュー未実施を明記し、タイミング対策の前提に適さない例としてWasmも挙げる。**APIの広さは確認できるが、監査済みのセキュリティ基盤という評価はできない。**([crypto](https://pkg.odin-lang.org/core/crypto/)、[compact設定](https://github.com/odin-lang/Odin/blob/master/core/crypto/crypto.odin)、[実装上の制約](https://github.com/odin-lang/Odin/blob/master/core/crypto/README.md#L10-L27))

X.509は解析・生成・署名検証・チェーン検証を持つが、CRL/OCSPの失効確認などには制約がある。TLSには大きな版差があり、手元版には `core/crypto/tls` がない一方、現在の公式APIにはクライアント接続用の `client_handshake`・send/recv等が載る。信頼ルートは呼び出し側から渡す設計で、公開APIからサーバー対応まで充足すると扱う根拠は得られなかった。([X.509の制約](https://pkg.odin-lang.org/core/crypto/x509/#overview)、[TLS APIと生成情報](https://pkg.odin-lang.org/core/crypto/tls/))

Wasmでは、固定バッファArenaや算術処理と、OS仮想メモリ・スレッド・外部I/Oを同じ可搬性で扱えない。たとえば仮想メモリのfallbackには失敗を返すAPIがある。先の[サイズ実測](../docs/wasm-size.md)でも、言語の整数演算・制御フローと、fmtや起動処理を含む構成では結果が違った。JSONの反射、allocator、OSバックエンド、ホストJSまで、何を取り込むかを用途ごとに見る必要がある。([仮想メモリのfallback](https://github.com/odin-lang/Odin/blob/master/core/mem/virtual/virtual_other.odin)、[JSONの反射依存](https://github.com/odin-lang/Odin/blob/master/core/encoding/json/marshal.odin))

## 採用時は用途とターゲットを先に固定する

この構成から、Odinはメモリ所有権やデータ配置を自分で決めるゲーム、可視化、ネイティブの制作ツールで、標準の強みを使いやすいと判断する。Wasmの小ささが目的なら、純粋な計算・データ変換とホスト側のI/Oを分担し、必要なパッケージだけを同じビルド条件で測るのが次の評価になる。今回の実行検証はmacOSの小さな並行処理例に限られ、性能測定、暗号監査、全OS・全vendorの動作検証は行っていない。利用前には、公式Web上の存在だけでなく、採用する配布版の実装と対応バックエンドまで確認したい。
