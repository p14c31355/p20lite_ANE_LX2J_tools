## Host staging carried over

- `~/dev/potatonv` = PotatoNV-crossplatform with `bootloaders/hisi65x_a` populated from the
  Windows release zip (xloader @0x00020000, fastboot @0x10000000). Entry point `python -m usrlock`.
- `~/dev/huawei-unlock-tool` = partial C# source drop (werasik2aa). `DIAGNOS/DIAG.cs`
  `SW_PCUI_TODIAG()` = `AT$QCDMG=115200\r`; its DIAG side is **dongle-based**
  (`REWRITE_BOOTLOADER_KEYQC(key, donglename, dongledatarsaoraespksx)`, `AUTH_PHONE` -> `CCEE`,
  `READ_SECRET_KEY` -> `EDEE` replies `Please Auth`), so only its HISI half is relevant and that
  half is PotatoNV's, which needs VCOM.
- `~/dev/huawei-brute` = brute-force tool; **not viable** (walks the 16-digit space from
  1e15 with step `sqrt(IMEI)*1024`, ~2-4 s per attempt, reboot every 4 failures).
- `~/dev/usbtool-*.py` + `~/dev/usbtool-env` (pyusb) for PCUI/AT probing.
- FYI a naive `python -c "import fastboot"` check fails even with fastbootpy installed; verify by
  running the tool.

## 2026-10-02 未明: dload 5% の壁と「無改造しか勝てない」法則

### dload が 5% で止まる正体(最有力)
- 進行バーが出る = バージョン検査は通過している(原本は「Incompatibility」でバー以前に拒否、
  こちらはバーが出て 5% 停止)。5% は検証段階。
- ZIP エントリの CRC-32 は正しく更新済み(実測: stored == actual を全3ファイルで確認)ので CRC 説は否定。
- 残る最有力 = SigApk の whole-file 署名。署名は「コメント手前まで」を覆うため、本体や
  セントラルディレクトリを 1 バイトでも変えた時点で署名が壊れる。コメントのパディングも
  EOCD の comment length フィールドを変えるため署名対象に入る。→ 修正パッケージは原理的に不可。
- EOCD-smuggle(原本+追記)も失敗。frankenZIP の読み手/書き手の向きは未確定。

### エクスプロイトの競合に勝てる条件(重要)
- 無改造ビルド: 勝つ(再現性あり)。
- 定数の即値のみ変更: 勝つ(3回連続、minimal-delta で確認)。
- コード構造の変更: 全敗。以下すべて敗退:
  - 呼び出し先の差し替え(overwrite_avc_cache → set_sid、バイナリサイズ同一 96552B でも敗退)
  - argv 対応、g_delay 実行時化、printf 追加
- 解釈: リンカ配置(.text のレイアウト)が変わると負ける。参照関数が変わると配置が動く。
- 結論: エクスプロイトにできる変更は「定数の即値」だけ。SID 書き換え等のロジック変更は不可。

### 151 カーネルのシンボルが無いことの帰結
- 151 の fair_sched_class / avc_cache が不明。110 の値は別ビルド(KASLR 2MiB 整列が合わない)。
- F_old(公開エクスプロイトの定数)は 151 と 2MiB 剰余が一致(整列する)→ 少なくとも合同。
  高々 m*2MiB のずれだが、avc_cache のずれは別途不明。
- 定数しか変えられないので、AV キャッシュのアドレスを正しくするには 151 のカーネル画像が必要。
- 入手候補: HalabTech の ANE-LX2JC636B151(要アカウント)、HiSuite で 9.1 に上げてから
  8.0.0.151 へ戻すと再ダウンロードされる(その場で ROM をコピーする必要がある)。

### 端末の現状
- ANE-LX2J 8.0.0.151(C635) のまま(dload 失敗でデータは消えていない/USBデバッグも生存)。
- root は取れる(競合勝利時)。ただし SELinux ドメインは u:r:shell:s0 のままでブロックデバイス拒否。

### 検証済みパイプライン(2026-10-02 未明)
ファーム package → KERNEL → シンボル → エクスプロイトの定数2つ、が自動で出る。
- 入口: `~/dev/p20-root/fw_to_constants.sh <pkg.rar|.zip|.app> [workdir]`
- 実体: `scan_app_all.py <app> <outdir>` (マジック全出現走査、hdr上限 65536、
  KERNEL/RAMDISK/RECOVERY_RAMDISK を抽出 → vmlinux-to-elf → nm で2定数)
- vmlinux-to-elf は `/tmp` ではなく `~/dev/p20-root/.venv-sym/` に常設(このホストの /tmp は消える)。
- **検証済み(陽性対照)**: 8.0.0.110(C635) の update_sd.zip から
  fair_sched_class=ffffff8008f48408 / avc_cache=ffffff800a276c40 を再現(記録値と一致)。
  復元シンボル数 128,105、ヘッダ 32 個(KERNEL/RAMDISK/RECOVERY_*/MODEM_FW/CUST/DTS 等)。
- 注意: 内側の update_sd_ANE-L22J_hw_jp.zip には KERNEL が無い(7ブロック)。
  KERNEL は外側 UPDATE.APP 側(32ヘッダ)にある。
- 大型パーティション像はヘッダが 4096 バイトを超える(65536 上限が必要)。
  4096 で切ると KERNEL 以降を取りこぼす。

## 2026-10-02 未明〜早朝: BLU 目前までの全記録(ANE-LX2J 8.0.0.151 C635)

### エクスプロイトが要求するのは「差」1つだけ(ソースで確定)
~~~c
kaslr_offset   = kernel_read_ulong(task_struct + SCHED_CLASS_OFFSET) - FAIR_SCHED_CLASS;
avc_cache_addr = kaslr_offset + AVC_CACHE;
~~~
→ 有効なのは `AVC_CACHE - FAIR_SCHED_CLASS` の一致のみ。絶対アドレスも KASLR 整列も不要。
この理解で掃引が可能になった(下記)。

### 候補カーネルの実測表(azrom から4本取得して復元)
| ビルド | カーネル日付 | avc_cache - fair_sched_class |
|---|---|---|
| 8.0.0.110(C635) | 2018-04-18 | 0x132e838 |
| L22J 8.0.0.202(C719) | 2018-05-16 | 0x134a838 |
| TL00 8.0.0.151(C01) all cn | 2018-06-11 | 0x134a838 |
| LX2J 8.0.0.127(C719) / kddi_jp | 2019-04-25 | **0x134c838** |
| (エクスプロイト内蔵) | ? | 0x135c838 (否定済み) |
| **端末 (C635B151)** | **2019-03-01** | **0x134c838 と一致 → 成功** |
差はビルド日付に単調とは限らない(.text/.bss レイアウト次第)。日付が近いだけでは不十分。

### SELinux 迂回成功の構成(凍結済み)
- `working/cve-2019-2215_0x134c838` (96552B, md5 5296630b1610bd132c65b4f070c63d06)
- FAIR_SCHED_CLASS=0xffffff8008f48408 / AVC_CACHE=0xffffff800a294c40 / DELAY=25
- 成功の観測: `dd if=/dev/block/bootdevice/by-name/nvme` が読める + policy-pairs=1
  (live_with_selinux の "Could not load policy" が1回だけ = 2回目が成功)

### 競合の勝ち負けの法則(重要)
- 無改造: 勝つ。定数の即値のみ変更: 勝つ(今回も一発で勝った)。
- コード構造の変更(呼び出し差し替え・argv・printf 追加): 全敗。リンカ配置が動くため。
- システムが静かなときのみ勝つ。再起動直後や adb 連打中は負ける(loadavg が目安)。
- fastboot モードのまま adb を叩くと「競合に負けた」と誤判定するので、必ず状態を先に確認する。

### nvme / FBLOCK / USRKEY(hisi-nve)
- nvme = /dev/block/mmcblk0p7 (by-name/nvme)。FBLOCK は各 0x20000 ブロックに7コピー。
- `hisi-nve r FBLOCK` → ツールは 0=unlocked / 1=locked と表示(コード準拠)。
- `w FBLOCK 0` で全7コピーが 0 になり、再起動後も保持された(書き込みは成功)。
- ただし LK は FB LockState: LOCKED のまま。→ FBLOCK=0 だけでは LK は解除しない。
- 効果はあった: `oem unlock` の "check password failed" が消え、USRKEY 照合を通過した。
- `w USRKEY <16文字>` は hi6250 で SHA256 ハッシュ化して書き込む(nve_hashed_key=1)。
  書き込み後 `fastboot oem unlock <同じ文字列>` が次のゲートまで進む(実測)。
- 次のゲート: `Necessary to unlock FRP! Navigate to Developer options, and enable "OEM unlock"!`

### OEM ロック解除トグルのグレーアウト(未解決の最終ゲート)
- 端末: `sys.oem_unlock_allowed`=0 → root で 1 に変更(持続確認済み)、settings global も 1。
- `ro.oem_unlock_supported`=1 / `ro.frp.pst`=/dev/block/bootdevice/by-name/frp。
- `persistent_data_block` サービスは**存在しない**(service list に無い)→ PDB 経由の書き手がいない。
- oemlock HAL も無し(lshal 空)。liboeminfo.so → /dev/socket/oeminfo_nvm 経由(実体は別物)。
- device owner / device admin 無し、MDM 無し、アカウント無し。Wi-Fi 接続済み(INTERNET 検証済み)。
- → 上記すべて満たしてもトグルはグレーのまま、`oem unlock` も同メッセージで拒否。

### frp パーティションの形式(解読済み)
- 786,432 バイト。データは 0x00-0xb7 と 0xbfc1b-0xbfc7d の2領域のみ(残りはゼロ)。
- **先頭32バイト = SHA256(パーティション全体、先頭32バイトを0にして計算)** ← 一致確認済み。
- 0x20: マジック 0x73189019 (AOSP PDB)。0x24: 4バイトのゼロ(フラグ候補)。
- 0x24 を 1 にし、ダイジェストを再計算して書き込み → **再起動後 adb/fastboot 両方無応答**
  (USB は 12d1:107e で MTP+Mass Storage の2インターフェースのみ)。要復旧。
- 復旧手順: `restore_frp.sh`(Android が戻れば root で原本を dd)。原本は保全済み。

### 保全済みバックアップ(ホスト側)
- firmware/partitions/frp.bin (786,432) / frp_flagged.bin(書いたもの)
- firmware/partitions/oeminfo.bin (67,108,864) / misc.bin (2,097,152)
- firmware/nvme_backup_20261002_012858.bin (6,291,456, md5 ddf84baa5da43f6c0e157866ff72f0dc)
- nvme のバックアップは書き込み前の状態(全 FBLOCK=1)。

### 端末状態の見分け方
- Android 正常: 12d1:107e, 6インターフェース(Mass Storage/ADB Interface/HDB Interface), adb 応答
- fastboot: `fastboot devices` が応答(製品名は "Bluetooth Radio" と表示される)
- 今回の停止: 12d1:107e, 2インターフェース(MTP/Mass Storage)のみ, adb も fastboot も無応答

## 2026-10-02 早朝: アンロック達成

### 最終的に効いた手順
1. SELinux 迂回(エクスプロイトの定数差 0x134c838)で root を得る。
2. `hisi-nve w FBLOCK 0` → 全7コピーが 0 に(nvme は /dev/block/mmcblk0p7、6,291,456 バイト)。
3. USRKEY に自分の解除コードの SHA256 を書く。**hisi-nve の write は効かない**
   (「Hashing USRKEY...」と表示されるが保存値は工場出荷時のまま)。
   → **nvme イメージを直接 dd で書くのが正解**:
   - エントリ配置: 名前(8バイト)+12 = 値オフセット。値は104バイト。
   - USRKEY 7コピー @0x29d84 + k*0x20000 (k=0..6)。
   - 値の先頭32バイトに SHA256("0123456789ABCDEF") を書く。
   この方法なら読み戻しで検証できる(7 copies correct を確認)。
4. 端末側で 設定 → 開発者向けオプション → **OEM ロック解除を有効化**
   (Wi-Fi 接続後しばらくで有効化できた。グレーアウトはインターネット接続で解除)。
5. `fastboot oem unlock 0123456789ABCDEF`
   → `(bootloader) The device will reboot and do factory reset... OKAY`
   **= アンロック成功**(README の P10 Lite の例と同一応答)。

### 各ゲートの通過順(実測)
1. `check password failed` → FBLOCK=0 で解消(まず FRP ゲートが表示されるようになる)
2. `Necessary to unlock FRP! Navigate to Developer options, and enable "OEM unlock"!`
   → 開発者向けオプションの「OEM ロック解除」有効化で解消
3. `check password failed`(再度) → USRKEY を直接 dd で正しい SHA256 にして解消
4. アンロック成功

### 学び
- この ROM に persistent_data_block サービスは無い。OEM ロック解除トグルの実体は
  Android 側で完結しない(ブートローダーへは NV 経由で伝わる)。
- frp パーティション: 先頭32バイト = SHA256(全体、先頭32バイトを0にして計算)。
  0x20 に AOSP PDB マジック 0x73189019。0x24 はゼロ。**この2箇所は触らなくてよい**
  (実際 0x24 への試験書き込みは実行されておらず、frp は無傷だった)。
- USRKEY 書き込みは必ず読み戻しで検証する(ツールの成功表示は信用できない)。
- nvme のエントリは 0x20000 ごとの7コピー。1つ直せば全コピー直すこと。

## 2026-10-02 日中: Fullerene 起動の試行(プローブ3種)と計測器

### ホスト側の指紋(実測)
- fastboot = `18d1:d00d` Product "Fastboot2.0"
- Android 系 = `12d1:107e` bcdDevice 2.99(早期起動 2 インターフェース → 6 で正常。
  eRecovery は + File-CD Gadget)
- 計測器: `~/dev/p20-root/ane_usb_monitor.py`(状態遷移 + カーネルログを TSV 記録、
  未知の VID:PID を機械検出)

### プローブ3種の結果(いずれも可視化されず)
- pstore 3 ゾーン書き(mark probe v2): 全ゾーン空のまま。07:21 の読み出し自体が
  読取り消去していたこと + 中間ブートが pmsg を消費した可能性で判定不能。
- USB DCTL トグル(SftDiscon 0/1 = ホスト可視を狙う): ホスト側完全沈黙(60 秒窓)。
- フレームバッファ全塗り(/reserved-memory/graphic 0x31000000 の 27.5MB): 画面変化なし。
- 共通の解釈: 「LK が我々のコードに入っていない」or「書き込みが届かない(MMU 等)」の
  どちらとも整合。区別にはまだ成功していない。

### LK のフォールバック挙動(重要)
- ブート失敗時、LK は約 2〜4 分で **recovery パーティション**を起動する
  (画面に「再起動/データ初期化」のメニューが出る)。以前の観測では 6 分後に
  eRecovery が USB に列挙。
- したがって「沈黙時間」だけでは「入った/入っていない」を区別できない。
- recovery 画面が「プローブ実行中の窓」に出たという証言 = フォールバックは
  2〜3 分で起きた計算になる。

### カーネルパーティションへのプローブ焼き(再確認)
- `fastboot flash kernel <自作 ANDROID! イメージ>` は通る(4KB でも 24MB でも)。
- `fastboot boot` は依然 `Command not allowed`。

### エクスプロイト連打の副作用(再確認・重要)
- 8〜10 回連打したらデバイスが USB から消えた(高速再列挙×3 → バスから消滅)。
  「再起動後 1 回だけ」の原則(上記)を厳守。連打は系を壊し、復旧にボタン操作が必要になる。

### USB 既定モードの変更(作業中)
- 現在: `persist.sys.usb.config = hisuite,mtp,mass_storage,adb`(hisuite が先頭 =
  毎回手動で「ファイル転送」を選ばされる原因)。
- 目標: `mtp,adb` に変更(root 必要 → 再起動後 1 回のエクスプロイトで setprop)。
- 副次効果: adb が常時自動で上がり、実験サイクルからボタン操作が消える。

## 2026-10-02 午後: ブート契約の解明(重大)

### LK は MMU を ON のままハンドオフする(全プローブ沈黙の真因)
- カーネル用予約領域(pstore 0x34800000 / graphic 0x31000000 / USB MMIO)は
  LK のページテーブルに無い → **素のプローブは最初のメモリアクセスでフォルト**し、
  LK の例外ハンドラ経由で rescue(リカバリ画面)へ落ちる。
- 証拠: MMU-off プリアンブル(CurrentEL を見て SCTLR_EL1/EL2 の M を消す)
  を付けた fb2 プローブだけが**リセットループ**(unlocked 警告の繰り返し、7分以上)
  を起こした = 我々のコードの PSCI SYSTEM_RESET が実行されている。
- **Fullerene entry.rs に同プリアンブルを適用済み**(実ビルド + QEMU PASS)。

### ストック埋め込み形式(自作小イメージは実際は受理される)
- 小さい自作イメージ(code0=b+0x40, image_size=4MB)でも fb2 は受理された。
- さらに確実な形式: **ストック Image のエントリ位置(0x1660000)だけを
  書き換える**(code0 がそこへ分岐するため、LK が先頭実行でも直接ジャンプでも
  着地する)。パッケージ 11.6MB = 受理済み再パックと同クラス。
- 0x1660000 = ストック自身のエントリ(逆アセンブルでコード実在確認)。
- ツール: `mkane_stock_embed.py` + `ane_fb_probe2.S`/`ane_rch_probe.S` 等。

### Fullerene 初回実機実行(08:55)と未解決点
- ストック埋め込み Fullerene → 起動 33 秒で rescue へ。
- 同じ形式の小プローブ(fb2)はループしたので、原因は Fullerene 自身の
  早期 path(relocation/BSS/コンソール/DTB)の公算。
- 次: pstore 読み出しで 'E'(mark_entry)の有無を確認 → 有れば実行確定、
  無ければ entry 前の死。RCH プローブ(同形式, 色分け)で形式自体も検証可。

### ホスト側ツールの落とし穴
- GNU grep 3.11 の `-E` は `\t` をタブと解釈しない → `adb devices` 等の
  device 検出は `-P`(PCRE)か awk を使う。8 本のスクリプトが空回りした。

