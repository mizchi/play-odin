# Odin の暗号と同梱 vendor ライブラリ

## 暗号はどこまで揃い、どこに境界があるか

### Takeaway

暗号はハッシュだけでなく AEAD・KDF・公開鍵・耐量子暗号・X.509 まで広い API を持つ。一方、実装範囲と安全性評価は区別が必要で、公式 README 自体が非スレッド安全・第三者レビュー未実施・Wasm のタイミング特性上の制約を明記している。[暗号索引](https://pkg.odin-lang.org/core/crypto/)、[README の実装上の制限](https://github.com/odin-lang/Odin/blob/master/core/crypto/README.md#L10-L27)

### Cited Findings

- 対象のローカル版は 2026-11-03 配布の macOS ARM64 版、既存会話で確認済みの `dev-2026-11-nightly:9a69916`。`core/crypto` の実ファイルを一覧し、`tls/` がないことを確認した。同じ配布に `x509/`、`mldsa/`、`mlkem/`、`noise/`、各暗号プリミティブは存在する。[ローカル暗号ソース](https://github.com/odin-lang/Odin/tree/9a6991685ddf663956d9836602eb421e141fc443/core/crypto)
- SHA-2 / SHA-3 / BLAKE2、AES-GCM、ChaCha20-Poly1305 / XChaCha20-Poly1305、AEGIS、Deoxys-II、HMAC / HKDF / PBKDF2 / Argon2id、RSA / ECDSA / Ed25519 / ECDH / X25519 / X448 / Ristretto255、Noise が個別パッケージとして用意されている。ルート README はアルゴリズムが Odin 実装であると説明している。[暗号 API 索引](https://pkg.odin-lang.org/core/crypto/)、[実装の説明](https://github.com/odin-lang/Odin/blob/master/core/crypto/README.md#L4-L8)
- 耐量子の ML-KEM と ML-DSA も手元版に実装ディレクトリと API がある。doc.odin がそれぞれ FIPS 203 / 204 を参照する。認証や第三者適合性評価を受けたという意味ではない。[ML-KEM API](https://pkg.odin-lang.org/core/crypto/mlkem/)、[ML-DSA API](https://pkg.odin-lang.org/core/crypto/mldsa/)、[ローカル ML-KEM doc](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/crypto/mlkem/doc.odin)、[ローカル ML-DSA doc](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/crypto/mldsa/doc.odin)
- `core:crypto` にはシステムの暗号学的エントロピー、定数時間比較、明示的ゼロクリアのヘルパーがあり、`HAS_RAND_BYTES` でエントロピー源の提供可否を確認する。また `-define:ODIN_CRYPTO_COMPACT=true` の設定は、大きな事前計算テーブルを省いて速度とサイズを交換する設計。[crypto.odin](https://github.com/odin-lang/Odin/blob/master/core/crypto/crypto.odin)、[ローカル同ファイル](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/crypto/crypto.odin#L8)
- **安全性・対象環境についての一次資料は必ず最終報告でも残すこと**。README の Implementation considerations は、(1) thread-safe ではない、(2) 64 bit 整数演算を前提にする、(3) タイミングサイドチャネル対策の前提に適さない例に WASM を明示、(4) ハードウェアサイドチャネルは対象外、(5) 独立第三者レビューを受けていない、と明記する。ローカルと現 master の記載を照合した。原文を長く引用せず、このように要約する。[README L10–L27](https://github.com/odin-lang/Odin/blob/master/core/crypto/README.md#L10-L27)、[ローカル README](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/crypto/README.md#L10)
- MD5 / SHA-1 / 旧 Keccak は `crypto/legacy` に分離され、旧システムとの相互運用のためにのみ同梱される。これらがあることを一般用途の推奨と解釈しない。[legacy README](https://github.com/odin-lang/Odin/blob/master/core/crypto/legacy/README.md)
- X.509 は DER の解析だけでなく証明書・CSR・PKCS#8 等の marshal、ホスト名検証、署名検証、信頼アンカーと中間証明書を明示的に渡すチェーン検証を持つ。RSA、ECDSA P-256/P-384、Ed25519 などの署名を扱う。ローカルでも `parse.odin` / `verify.odin` / `marshal.odin` / `pkcs8.odin` を確認した。[X.509 API](https://pkg.odin-lang.org/core/crypto/x509/)、[ローカル doc](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/core/crypto/x509/doc.odin)
- X.509 は CRL / OCSP の失効確認を行わず、証明書ポリシーや Public Suffix List による制約などにも明示的な限界がある。読み取りに成功することと、証明書が信頼できることは別だと doc が説明する。[X.509 の Overview / LIMITATIONS](https://pkg.odin-lang.org/core/crypto/x509/#overview)
- **重要な版差**：2026-11-18 に閲覧した公式 API は `core:crypto/tls` を掲載する。ページの生成情報は 2026-11-17 の dev-2026-11。前述の手元 11月3日配布には TLS ディレクトリがないため、最新公式の TLS を手元版の機能と表記しない。公式 core 一覧には TLS がある一方、個別 crypto 索引は 34 packages と TLS なしの古い一覧を返す場合があり、ページ間の更新・キャッシュ時点が一致していない。[TLS API と generation information](https://pkg.odin-lang.org/core/crypto/tls/#generation-information)、[現 core 索引](https://pkg.odin-lang.org/core/)、[個別 crypto 索引](https://pkg.odin-lang.org/core/crypto/)、[手元ソースのルート](https://github.com/odin-lang/Odin/tree/9a6991685ddf663956d9836602eb421e141fc443/core/crypto)
- 現公式 TLS の公開関数は `client_handshake` / `close` / `recv` / `send` / `socket_error` / `to_stream`。**サーバーハンドシェイク API は掲載されていないので、TLS サーバー用途も標準で充足すると表記しない**。クライアントは接続済み TCP ソケットと `trust_roots` を呼び出し側から渡し、ALPN を指定できる。[TLS 公開 API](https://pkg.odin-lang.org/core/crypto/tls/)
- 現 master の TLS パラメータに列挙された暗号スイートは TLS 1.3 の AES-128-GCM / AES-256-GCM / ChaCha20-Poly1305。クライアント実装は証明書チェーンを `x509.verify_chain` に渡し、DNS名と Server_Auth EKU を指定する。API・実装は thread / sync / chan に依存し、ソケットを blocking に設定する。ここでは TLS 1.2 フォールバック対応を確認していない。[TLS パラメータ](https://github.com/odin-lang/Odin/blob/master/core/crypto/tls/tls_params.odin)、[TLS クライアント](https://github.com/odin-lang/Odin/blob/master/core/crypto/tls/tls_client.odin#L24-L63)、[検証への接続](https://github.com/odin-lang/Odin/blob/master/core/crypto/tls/tls_client.odin#L1115-L1123)、[TLS の保持状態と同期依存](https://github.com/odin-lang/Odin/blob/master/core/crypto/tls/api.odin#L61-L87)

### Inferences

- 暗号の「API・実装範囲の広さ」は、Odin の標準 core の目立つ充実点と評価できる。特に耐量子や X.509 まで含むことが具体的な根拠になる。一方で README の明示制限から、成熟した監査済みセキュリティ基盤として一括評価することはできない。[API 索引](https://pkg.odin-lang.org/core/crypto/)、[明示制限](https://github.com/odin-lang/Odin/blob/master/core/crypto/README.md#L10-L27)
- Wasm サイズを小さくできても、暗号のタイミング安全性が確保されるという結論にはならない。これは前のサイズ調査から独立した評価軸である。[WASM を含む制限](https://github.com/odin-lang/Odin/blob/master/core/crypto/README.md#L10-L17)

### Gaps

- 暗号実装の正しさ・サイドチャネル・実運用安全性の監査は行っていない。現 master の TLS は手元版に存在しないため、フルビルドや外部サーバーとの相互運用も未検証。[TLS の版境界](https://pkg.odin-lang.org/core/crypto/tls/#generation-information)
- TLS について、サーバー実装、相互 TLS、セッション再開などを充実点として挙げる根拠は今回得ていない。API で確認したクライアント接続に範囲を限る。[公開 API の範囲](https://pkg.odin-lang.org/core/crypto/tls/)

## vendor はどの分野を充実させているか

### Takeaway

同梱 vendor は、描画だけでなくウィンドウ・入力・物理・画像・フォント・音声・ゲーム通信まで広く、ゲーム／ビジュアルツール開発を支える連携面が特に厚い。ただし多くは既存 C ライブラリへのバインディングで、core の Odin 実装と区別する。[vendor 公式索引](https://pkg.odin-lang.org/vendor/)、[vendor README](https://github.com/odin-lang/Odin/blob/master/vendor/README.md)

### Cited Findings

- `vendor:` はこの Odin 実装に付属するパッケージコレクションで、バインディングと関連バイナリを Odin チームが管理する。一部は Odin への移植実装である。[vendor README 冒頭](https://github.com/odin-lang/Odin/blob/master/vendor/README.md#L1-L6)
- 描画・ウィンドウ分野には Raylib（raygui / raymath / rlgl も同梱）、SDL2 / SDL3、GLFW、OpenGL、Vulkan、Direct3D 11 / 12、wgpu、WebGL、NanoVG、microui がある。OpenGL には Odin 実装のローダー、microui には Odin-native なソース移植という違いもある。[vendor 索引](https://pkg.odin-lang.org/vendor/)、[Raylib API](https://pkg.odin-lang.org/vendor/raylib/)、[microui](https://pkg.odin-lang.org/vendor/microui/)
- アセット処理には glTF の cgltf、stb/image の画像読み込み・書き出し・リサイズ、stb/truetype、fontstash、kb_text_shape、OpenEXRCore がある。文字描画だけでなく Unicode segmentation / OpenType shaping までバインディングを用意する。[vendor README の用途一覧](https://github.com/odin-lang/Odin/blob/master/vendor/README.md)、[stb/image](https://pkg.odin-lang.org/vendor/stb/image/)、[kb_text_shape](https://pkg.odin-lang.org/vendor/kb_text_shape/)
- 音声には miniaudio（再生・録音）、PortMidi（MIDI）、SDL mixer、stb/vorbis、Windows 音声 API 連携がある。物理は Box2D / Box3D、ゲーム通信は ENet / GGPO、スクリプト埋め込みは Lua、一般ネット転送は curl が同梱される。[用途と対応ライブラリ](https://github.com/odin-lang/Odin/blob/master/vendor/README.md)、[miniaudio](https://pkg.odin-lang.org/vendor/miniaudio/)、[Box2D](https://pkg.odin-lang.org/vendor/box2d/)、[Box3D](https://pkg.odin-lang.org/vendor/box3d/)
- 手元の vendor には Lua 5.1 / 5.2 / 5.3 / 5.4 / 5.5 があり、公式の vendor 索引が 5.4 だけを表示する場合でも、それが同梱版の全範囲とは限らない。このため総評で細かなバージョン数を強調する必要はない。[ローカル Lua ソース](https://github.com/odin-lang/Odin/tree/9a6991685ddf663956d9836602eb421e141fc443/vendor/lua)、[vendor README の Lua 一覧](https://github.com/odin-lang/Odin/blob/master/vendor/README.md#L26-L30)

### Inferences

- 標準配布を入れた時点でゲームや描画ツールから使う代表的 C API の型・関数宣言を多数参照できるため、ゲーム／ネイティブビジュアル用途は充実領域と評価できる。ただし、完成した高水準 GUI アプリフレームワークやゲームエンジンを core が一体で提供するという意味ではない。[用途一覧と binding の定義](https://pkg.odin-lang.org/vendor/)
- 「Odin の標準ライブラリ」を core だけに限定すると、このゲーム方面の強みを見落とす。一方で vendor をすべて Odin-native な標準実装として合算すると実体を誤るため、core と同梱 vendor を別列で示すのが適切。[vendor コレクションの位置付け](https://github.com/odin-lang/Odin/blob/master/vendor/README.md#L1-L6)

### Gaps

- すべての vendor API の完全性・各 upstream バージョンとの差分・全機種でのビルドは調べていない。個別に版と対象環境を読む必要がある。[各パッケージと版の一覧](https://github.com/odin-lang/Odin/blob/master/vendor/README.md)

## native と Wasm で何が変わるか

### Takeaway

vendor の充実はそのまま全ターゲットでの使用可能性を意味しない。ブラウザ向けには wgpu / WebGL の明示的な連携がある一方、native ライブラリ・追加 JS・コールバック表・allocator などの準備が機能ごとに異なる。[wgpu の対象と依存](https://pkg.odin-lang.org/vendor/wgpu/#overview)、[vendor README](https://github.com/odin-lang/Odin/blob/master/vendor/README.md)

### Cited Findings

- wgpu は native では wgpu-native、Wasm ではブラウザの WebGPU を JS ラッパーから呼ぶ。`js_wasm32` / `js_wasm64p32` を明示的にサポートする。[wgpu Overview](https://pkg.odin-lang.org/vendor/wgpu/#overview)、[ローカル doc](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/vendor/wgpu/doc.odin)
- wgpu の native 用バイナリは別途用意する必要があり、所定の `lib` 配下になければソース中で `#panic` する。Wasm はコールバック用の `--export-table` と、一部 API のための割り当て機能を要求する。したがって「バインディングが同梱」だけで全用途のリンクが完了するわけではない。[wgpu のセットアップ説明](https://pkg.odin-lang.org/vendor/wgpu/#overview)、[ローカル foreign import / #panic](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/vendor/wgpu/wgpu.odin#L16)
- `vendor:wasm/WebGL` はブラウザの WebGL 向け API で、Odin の `foreign import "webgl"` に対するホスト実装が必要。ローカルには js 側ファイル群も付属する。[WebGL API と例](https://pkg.odin-lang.org/vendor/wasm/WebGL/)、[ローカル WebGL 宣言](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/vendor/wasm/WebGL/webgl.odin#L1)
- Raylib の手元版には `wasm/libraylib.web.a`、macOS / Linux 等のバイナリと OS/ARCH 別 foreign import がある。`RAYLIB_WASM_LIB` は設定可能。これを一般の WASI command 向け標準 I/O API と同列には扱わない。[Raylib ソース](https://github.com/odin-lang/Odin/blob/master/vendor/raylib/raylib.odin)、[手元の設定](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/vendor/raylib/raylib.odin#L100)
- curl の手元ソースでは Windows は同梱 `.lib` 群、Darwin / その他は `system:curl` や `system:z` へリンクする。バインディングがあっても外部リンク条件が OS ごとにある、という具体例になる。[curl の foreign import](https://github.com/odin-lang/Odin/blob/master/vendor/curl/curl.odin)、[ローカル curl](https://github.com/odin-lang/Odin/blob/9a6991685ddf663956d9836602eb421e141fc443/vendor/curl/curl.odin#L1)
- 暗号も Wasm に単にコンパイルできることとタイミング特性が適切なことは分ける必要がある。公式 README が WASM を実装上の注意対象として明示する。[暗号 README](https://github.com/odin-lang/Odin/blob/master/core/crypto/README.md#L10-L17)

### Inferences

- 前の会話の freestanding 最小 Wasm と、ブラウザ GPU / 入力 / 音声を含むアプリでは、ホスト JS・外部バイナリ・allocator まで含めた別の評価が必要。標準配布内の宣言の充実と最小ファイルサイズは両立し得るが、今回この担当では vendor のサイズ測定をしていない。[wgpu の依存説明](https://pkg.odin-lang.org/vendor/wgpu/#overview)

### Gaps

- ブラウザ実機での描画・音声・GPU 動作確認、全 vendor の Wasm 対応表、バイナリサイズ測定は実施していない。確認済みはソースと公式 API の明示事項まで。[公式 vendor 一覧](https://pkg.odin-lang.org/vendor/)
