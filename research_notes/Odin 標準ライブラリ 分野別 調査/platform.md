# Odin 標準ライブラリのOS 通信 並行処理 開発ツール

## OSと通信の基盤はどこまで揃っているか

### Takeaway

ネイティブのファイル・ディレクトリ・プロセス・ソケットを扱う部品は一通りあり、CLIやデスクトップツールの基盤として厚い。一方、HTTPサービスやDB利用を高水準の統一APIまで標準で完結させる構成は、今回調べた索引と配布版には見つからなかった。

### Cited Findings

- 調査対象は 2026-11-03 配布の macOS ARM64 版、`dev-2026-11-nightly:9a69916`。併せて2026-11-18に公式APIを閲覧した。公式ページはページごとのキャッシュ時点が異なり、配布版と同一コミットとしては扱っていない。例えばAPIのサイドバーにTLSが載るページと載らないページがあるため、索引の瞬間的な見え方を全ライブラリの確定版とみなさない。— [ローカル配布版](https://github.com/odin-lang/Odin/releases/tag/dev-2026-11a)、[core索引](https://pkg.odin-lang.org/core/)、[os API](https://pkg.odin-lang.org/core/os/)、[chan API](https://pkg.odin-lang.org/core/sync/chan/)
- `core:os` は、共通のOS APIを提供し、共通化しない機能を `core:sys` のOS別パッケージへ分ける設計。`create/open/read/write/read_at/write_at/seek/truncate/sync`、rename/link/symlink、権限・時刻操作、存在判定などが実装されている。— [os API](https://pkg.odin-lang.org/core/os/)、[file.odin](https://github.com/odin-lang/Odin/blob/master/core/os/file.odin)、[手元のfile.odin](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/os/file.odin#L151)
- `Process_Desc` は引数配列、作業ディレクトリ、環境、stdin/stdout/stderrを指定できる。`process_start/process_wait/process_kill/process_terminate` のほか、`process_exec` はstdout/stderrをバイト列として取得する実装を持つ。`process_wait` にはtimeoutがある。— [process.odin](https://github.com/odin-lang/Odin/blob/master/core/os/process.odin)、[手元のProcess_Desc](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/os/process.odin#L377)、[手元のprocess_exec](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/os/process.odin#L445)
- 便利なAPIでも所有権と制約は明示的。`process_exec` の返す出力は呼び出し側が解放し、エラー時にも返却済みスライスは自動解放しない。`process_start` の説明にはハンドル継承の変更に関する非スレッド安全性が書かれている。— [process.odin](https://github.com/odin-lang/Odin/blob/master/core/os/process.odin)、[手元の説明と実装](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/os/process.odin#L424)
- `core:io` の `Stream` は手続きポインタと `rawptr` の2フィールドを持ち、read/write/seek等を抽象化する。copy/read_full/limited_reader/section_reader/tee_reader/multi_reader/multi_writerなどの合成用APIがあり、`core:bufio` がバッファリングを提供する。— [io API](https://pkg.odin-lang.org/core/io/)、[bufio API](https://pkg.odin-lang.org/core/bufio/)、[手元のStream](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/io/io.odin#L86)
- `core:net` はTCP/UDPソケット、bind/listen/accept/dial、送受信、ソケットオプション、IPv4/IPv6等のアドレス、URLの処理、DNSを備える。DNSはOS経由と独自resolverの選択肢がある。中心はBerkeley sockets層であり、`Connection` の高水準抽象等はOverviewのplanned項目にも残る。— [net API Overview](https://pkg.odin-lang.org/core/net/)、[socket.odin](https://github.com/odin-lang/Odin/blob/master/core/net/socket.odin)、[手元のsocket.odin](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/net/socket.odin#L69)
- 手元coreの全ディレクトリと閲覧時の公式core索引に、HTTP client/server、SQL/DBの専用パッケージは見つからなかった。これは「当該索引と配布版のcore内での未発見」という範囲の主張であり、外部ライブラリの不存在やTLS全般の欠如は意味しない。vendorにはcurlが別にある。— [core索引](https://pkg.odin-lang.org/core/)、[ローカルcore](https://github.com/odin-lang/Odin/tree/9a6991685ddf663956d9836602eb421e141fc443/core)、[vendor索引](https://pkg.odin-lang.org/vendor/)
- `path/filepath` と `path/slashpath`、`time` の時刻・Duration・単調時計・ISO8601/RFC3339、`time/datetime`、`time/timezone` も配布される。— [filepath API](https://pkg.odin-lang.org/core/path/filepath/)、[time API](https://pkg.odin-lang.org/core/time/)、[datetime API](https://pkg.odin-lang.org/core/time/datetime/)、[ローカルtime](https://github.com/odin-lang/Odin/tree/9a6991685ddf663956d9836602eb421e141fc443/core/time)

### Inferences

- ファイルやプロセスを操作するネイティブの制作ツール、変換器、CLIなどは標準だけで組み立てやすい。メモリ所有権とOSの差を隠し切る設計ではないため、利用者がAPIの契約を読んで組み立てる必要はある。
- 高水準のWebアプリ統合より、ソケット・I/O・プロセス等の部品を提供する方向が強い。HTTPの専用パッケージ未発見を「通信機能が弱い」「TLSがない」と言い換えないこと。

### Gaps

- 全OSのファイル・子プロセス・ネットワークAPIを実行検証したわけではない。ソースとドキュメントによる範囲確認であり、個々の機能の成熟度やバグ率は評価していない。
- TLSの版差・機能範囲は暗号担当の調査を参照する。DBの外部エコシステム、curl経由のHTTP、Webフレームワークの比較は担当範囲外。

## 並行処理とWasmの差はどの程度か

### Takeaway

nativeにはOSスレッド、プール、同期プリミティブ、チャネル、コールバック型の非同期I/Oがある。「非同期がない」と総括するのは不正確。一方、この配布版のWasmバックエンドは、同じ名前のAPIがあってもstubや未対応が多い。

### Cited Findings

- `core:thread` はcreate/start/join/destroy等のスレッド操作に加え、タスクキューを持つ `Pool`、初期化・終了フック、タスク完了管理を提供する。— [thread API](https://pkg.odin-lang.org/core/thread/)、[thread_pool.odin](https://github.com/odin-lang/Odin/blob/master/core/thread/thread_pool.odin)、[手元のPool](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/thread/thread_pool.odin#L30)
- `core:sync` はMutex、RW_Mutex、Sema、Wait_Group、Barrier、Auto_Reset_Event、One_Shot_Event、Once、atomic操作等を持つ。`core:sync/chan` は型付きの高水準 `Chan`、低水準 `Raw_Chan`、送信・受信方向の区別などを提供する。ドキュメントの例はOSスレッド間の通信である。— [sync API](https://pkg.odin-lang.org/core/sync/)、[chan API](https://pkg.odin-lang.org/core/sync/chan/)、[手元の同期実装](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/sync/extended.odin)
- `core:nbio` はスレッドごとのイベントループとoperation/callbackを基本とする。tick/run/run_untilでループを進め、callbackは後のtickに呼ぶという契約で、timeout、完了、キャンセル等を扱う。Linux版はio_uring、Windows版はIOCPを利用している。— [nbio API](https://pkg.odin-lang.org/core/nbio/)、[Linux実装](https://github.com/odin-lang/Odin/blob/master/core/nbio/impl_linux.odin)、[Windows実装](https://github.com/odin-lang/Odin/blob/master/core/nbio/impl_windows.odin)、[手元のnbio説明](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/nbio/doc.odin)
- **今回の追加実行確認**：同じnightly配布版、macOS ARM64で、(1) `nbio.next_tick` を登録し、登録直後は未実行で `nbio.run()` 後にcallbackの書き込みを観測するプログラム、(2) `thread.create/start/join/destroy` で実際の別スレッドが42を書き込むプログラムを実行した。両方exit 0、stdout/stderr空。各実行に20秒timeoutを設定し、タイムアウトは起きなかった。外部I/Oや環境変更はない。
- `core:thread` のJS/WASI/Orca用実装は `IS_SUPPORTED == false` で、create/start/join等はunimplemented。これはこのバックエンドの制約で、Wasm規格全体が並列処理をできないという主張ではない。— [thread_other.odin](https://github.com/odin-lang/Odin/blob/master/core/thread/thread_other.odin)、[手元のthread_other](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/thread/thread_other.odin#L1)
- `core:os` のJS/Wasmファイルバックエンドはstubと明記される。WASIのprocess_start/process_wait/process_kill等は `.Unsupported`、native以外を扱うnetのfallbackは `.Network_Unreachable` 等を返す。したがって「クロスプラットフォーム」は全ターゲットで全APIが動くという意味ではない。— [file_js.odin](https://github.com/odin-lang/Odin/blob/master/core/os/file_js.odin)、[process_wasi.odin](https://github.com/odin-lang/Odin/blob/master/core/os/process_wasi.odin)、[socket_others.odin](https://github.com/odin-lang/Odin/blob/master/core/net/socket_others.odin)
- 既存調査では `core:nbio` のWASI fallbackは `FULLY_SUPPORTED == false` で、手元版のnext_tick利用例も型検査でエラーになった。今回それを再測定していない。現在のWasmサイズレポートに診断と再実行手順がある。— [既存調査](../../docs/wasm-size.md)、[nbio fallbackソース](https://github.com/odin-lang/Odin/blob/master/core/nbio/impl_others.odin)

### Inferences

- native向けのゲームやツールで、ワーカースレッド、ジョブプール、producer/consumer、I/Oループを組む部品は標準に存在する。ただし、APIの存在からあらゆるOSやカーネルの動作を保証することはできない。
- Wasmでは演算やデータ処理部分をOdinに置き、ファイル・通信・非同期待機をJS/WASIホスト側に任せる分担が実用的な候補になる。これは前のサイズ検証の自作状態機械と整合するが、標準asyncランタイムの成熟度やサイズを測った結果ではない。

### Gaps

- 実行確認はmacOS ARM64の小さなcallback/スレッド例だけ。Windows/Linux/BSD、負荷時のスケジューリング、ネットワーク・タイムアウト・キャンセル全組み合わせの動作は未検証。
- Wasm上のチャネル/atomic/共有メモリを一括して「未対応」とは判定していない。明確に確認したのはcore:thread等のバックエンド制約。

## CLIと開発ツール制作では何が充実しているか

### Takeaway

RTTIを使うCLI引数パーサ、メモリ追跡を持つテストランナー、Odin自身の構文解析・整形、複数ISAの命令エンコード等まで同梱される。通常のアプリで直接使わない領域も多いが、言語ツールやネイティブ制作ツールを作る人には目立つ長所である。

### Cited Findings

- `core:flags` は構造体のRTTIとタグからCLI引数を読み込む。位置引数、bool/enum/bit_set、配列/map、必須引数、型変換、ヘルプ、独自type setterと検証callbackを備える。エラーメッセージはtemp_allocatorに置かれるため、保持するならcloneが必要と文書化されている。— [flags API](https://pkg.odin-lang.org/core/flags/)、[doc.odin](https://github.com/odin-lang/Odin/blob/master/core/flags/doc.odin)、[手元のflags文書](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/flags/doc.odin)
- `core:testing` は `odin test` のランナーとテスト用API。各テストのメモリ追跡はデフォルトで有効、リーク/不正解放を失敗扱いにする設定、スレッド数、テスト名フィルタ、再現用seed、JSONレポート、ログ制御等がある。`FAIL_ON_BAD_MEMORY` のデフォルトはfalseなので「デフォルトで必ずリークをテスト失敗にする」とは書かない。— [testing API](https://pkg.odin-lang.org/core/testing/)、[testing doc.odin](https://github.com/odin-lang/Odin/blob/master/core/testing/doc.odin)、[手元のtesting設定](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/testing/doc.odin#L8)
- `core:odin` 配下にtokenizer、AST、parser、printer、format、doc-format、tool-formatがある。parserにはfile/package/pathからの解析や式・宣言の解析APIがあり、Odinソースを扱うツールを作るための部品になっている。完全な型検査器・Odinコンパイラが標準APIであるとは今回確認していない。— [parser API](https://pkg.odin-lang.org/core/odin/parser/)、[core/odinソース](https://github.com/odin-lang/Odin/tree/master/core/odin)、[手元のcore/odin](https://github.com/odin-lang/Odin/tree/9a6991685ddf663956d9836602eb421e141fc443/core/odin)
- `core:rexcode` は複数アーキテクチャの命令encoder/decoder/printer。x86、ARM、RISC-V等だけでなく6502等も含む。caller-provided buffer、ラベル解決・relocation、機械語から構造化命令へのdecode等が設計に含まれる。Wasm/SPIR-V用IRサブパッケージも索引に存在する。— [rexcode API](https://pkg.odin-lang.org/core/rexcode/)、[手元のrexcode設計文書](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/rexcode/doc.odin)、[core索引](https://pkg.odin-lang.org/core/)
- rexcodeのドキュメントは「LLVM-verified」「hot pathはzero allocations」等を自己申告している。今回その網羅性や速度の独立検証は行っていない。パッケージ数や説明文の性能表現を、標準全体の成熟度の客観指標には使わない。— [rexcode API DesignとArchitectures](https://pkg.odin-lang.org/core/rexcode/)

### Inferences

- 「ネイティブプログラムを動かす基盤」だけでなく、「プログラミング言語や制作ツールを作るための部品」が厚い点がOdinらしい。特に標準テストのメモリ追跡は、手動メモリ管理と相性がよい。
- Wasmの小ささが優先なら、flagsのようなRTTI依存の便利機能と、単純な整数演算のようなコンパイル時に落ちる機能を分けて測るのがよい。flags自体のビルドサイズは今回は未測定。

### Gaps

- parser/formatterが最新構文に完全追随しているか、rexcodeの全ISAの実装品質、テストランナー全オプションの動作は未実行。
- CLIフレームワークの外部依存との比較、IDE/LSPツールの完成度は今回対象外。
