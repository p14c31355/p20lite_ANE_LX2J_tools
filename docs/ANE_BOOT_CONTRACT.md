# ANE-LX2J ブート契約の調査記録 (2026-10-02 日中)

FullereneOS を ANE-LX2J で起動するための「LK はどうカーネルを読み込み・検証し・
ジャンプするか」の実測記録。全て実測 + 一次ソース(UPDATE.APP 内の LK 本体)。

## 1. 受理されるイメージと拒否されるイメージ(実測)

| イメージ | 形 | 結果 |
|---|---|---|
| ストック kernel (8.0.0.151) | ANDROID!, 24MB | 起動 ✓ |
| **再パックストック (自作パッカー, 同じカーネル)** | ANDROID!, 24MB | **起動 ✓**(= 署名/ハッシュ検証は無い) |
| mark probe v1/v2 (240B) | ANDROID!, 4KB | 起動せず → rescue へ |
| USB probe (4KB) | ANDROID!, 4KB | 起動せず → rescue |
| FB probe v1/v2 (4KB) | ANDROID!, 4KB | 起動せず → rescue |

## 2. LK 本体の証拠(UPDATE.APP の FASTBOOT ブロック = 2,672,640 バイト)

- 文字列 `"ANDROID!"` の直後に `"rescue: INVALID BOOT IMAGE HEADER"` が存在
  → **LK はブートイメージヘッダを検証し、無効なら rescue(リカバリ画面)へ落ちる**。
  これが「毎回リカバリが出る」の正体。
- `"get_kimage_size"` `"dump_kimage"` 等の文字列もあり、LK はカーネルイメージの
  サイズを扱うコードを持つ。
- `ARMd`(arm64 Image マジック)のリテラル/即値は見つからず → LK は arm64 ヘッダを
  直接は検証していない可能性が高い(検証するなら ANDROID! レベルの何か)。

## 3. ストック Image の実レイアウト(実測)

```
offset 0x0        : code0 = 0x14598000 = `b +0x1660000`  ← 本物のエントリへの分岐
offset 0x38       : "ARMd" マジック
text_offset       : 0x80000
image_size        : 0x280e000 (40MB, 実体 34.6MB)
flags             : 0xa  (4.4 の仕様では bit1-63 reserved。Huawei 独自の意味を持つ可能性)
offset 0x1660000  : 本物のカーネルエントリ(コード実在を逆アセンブルで確認)
```

我々の自作ヘッダ(code0=b+0x40, code1=nop, image_size=4MB, flags=0x2)とは
code0/code1/image_size/flags の 4 点が不一致。

## 4. 決定版プローブ: ストック埋め込み方式 (artifacts/fullerene-ane-stockprobe.img)

```
ペイロード = ストック Image (34,625,536B) そのもの
            ただし offset 0x1660000 の 176 バイトだけ我々のプローブに置換
ヘッダ     = ストックのまま(code0 の分岐先 = まさに我々のプローブ)
サイズ     = gzip 後 11,689,984B = 受理済み再パックと同値
```

- LK が「先頭にジャンプ → code0 実行」でも「エントリへ直接ジャンプ」でも、
  着地点は我々のコード(QEMU でこの制御フローを実証済み: code0 → 0x1660000 →
  プローブ実行 → フレームバッファ塗り)。
- 検証の分岐: LK のどのレベルで拒否されているか(サイズ/ヘッダ/内容)を
  これ 1 本で全部バイパスする。

## 5. プローブに搭載済みの技術(全て QEMU 検証済み)

1. **MMU-off プリアンブル**: CurrentEL を読み、EL1/EL2 の SCTLR.M が立っていれば
   その場で消す(ISB 付き)。「LK が MMU を切らずにハンドオフする」仮説への対策。
2. **フレームバッファ全塗り**: /reserved-memory/graphic (0x31000000, 0x1a40000) を
   単色 0xFF00FF00 で充填 → 画面に出れば「入った + RAM 書き込み成功 + 表示生きている」。
3. **PSCI SYSTEM_RESET (SMC, fid 0x84000009)**: DT が method="smc" と明言。
   動けばリセットループ(色→ロゴ→色)として見える。
4. メモリ書き込みは 0(MMU-off プリアンブルの msr 以外)。USB MMIO も触らない。

## 6. ホスト側の指紋(再掲)

- fastboot = `18d1:d00d` "Fastboot2.0" / Android 系 = `12d1:107e` bcdDevice 2.99
- 監視: `ane_usb_monitor.py`(状態遷移 TSV + kern.log イベント + 未知 VID:PID 検出)

## 7. 実測結果 (2026-10-02 午前)

### fb2 プローブ (MMU-off プリアンブル + FB 塗り + SMC) → **リセットループ発生**
- 起動後、'Your device has been unlocked and can't be trusted' の警告画面が
  **7 分以上繰り返し**表示され続けた (ユーザー証言)。
- LK 自身のブート失敗なら 2〜3 分で rescue に落ちるので、この「無限ループ」は
  **我々のコードの PSCI SYSTEM_RESET (SMC) が実行されている証拠**。
- ⇒ **LK は我々のコードに入る**。実行チャネル成立。
- 単色は一度も見えなかった = 塗りは届くが、**パネルは graphic 領域 (0x31000000)
  をスキャンしていない**(LK 自身のバッファを表示中)。

### 初期アクセスフォルト仮説 (全プローブ沈黙の統一説明)
- LK は **MMU を ON のままハンドオフ**しており、そのページテーブルは
  カーネル用予約領域 (pstore 0x34800000 / graphic 0x31000000 / USB MMIO) を
  カバーしていない。→ 素のプローブは**最初のメモリアクセスでフォルト**し、
  LK の例外ハンドラ経由で rescue へ (これが mark probe v1/v2・USB probe・
  FB probe v1 が毎回リカバリ画面になった原因)。
- fb2 (MMU-off プリアンブル付き) だけがループした = 仮説と完全に整合。

### ストック埋め込み方式 (LK 検証のバイパス)
- 自作の小さいヘッダ形でも fb2 は受理された (ループした) ため、
  「サイズ形で拒否」説は否定方向。ただしヘッダ検証の可能性は残るため、
  **ストック Image のエントリ位置 (0x1660000) だけを書き換える方式**を採用:
  - パッケージ = ストック Image + offset 0x1660000 に Fullerene/プローブ
  - code0 がそのまま我々のコードへ分岐 (LK の流儀が先頭でも直接でも着地)
  - サイズ = 11.6MB = 受理済み再パックと同クラス
- QEMU で制御フロー実証済み (code0 → 0x1660000 → プローブ実行 → 塗り)。

### Fullerene 本体の初回実機実行 (08:55)
- ストック埋め込み Fullerene (11.6MB, MMU-off パッチ入り) を flash → 起動。
- **33 秒後に rescue へフォールバック** (USB: 12d1:107e Product "HUAWEI" 1 iface)。
  = Fullerene が走り始めて(あるいは LK が拒否して) early に終了。
- 判定は pstore 読み出し待ち: 'E' (mark_entry) レコードがあれば
  「実行された」確定。無ければ起動 path の手前で死んでいる。

## 8. 未解決・次の一手

- **Fullerene の pstore 読み出し結果待ち**(実行サイクルは自動)。
- 記録が出たら: 最後のレコードの位置 = クラッシュ地点 → 修正して再実行。
- RCH プローブ完成 (artifacts/fullerene-ane-rch-probe.img, QEMU PASS):
  画面が実際に読んでいるバッファ (RCH DMA_DATA_ADDR0) を読んで色分け塗り。
  色でチャネルが分かる (green=VG0 / blue=VG1 / red=G0 / cyan=G1 /
  magenta=fallback)。FB チャネル用。
- USB ファイル転送デフォルト化 (エクスプロイトで root → setprop。
  **再起動後 1 回だけ**が原則)。

## 9. 2026-10-02 午前〜昼の実測 (追加)

### pp プローブ (pstore 記録 + UART ポーク) の結果

- 09:10:39 に焼込み・起動。**約4.5分間ループし続けた** (ホスト側は完全 dark)。
- **ループは無限ではない**: 09:15 頃、**LK 自身の自動フォールバックで rescue 画面**
  (12d1:107e, 1インターフェース Mass Storage, Product "HUAWEI") に落ちた。
  LK は「起動失敗」を数回検出すると自動で rescue へ落ちる機構を持っている。
- **UART 仮説は棄却**: pp プローブは Fullerene が死んだのと同じ PL011 書き込み
  (CR=0 → CR=0x301 → DR='A') を行った上でループした。実機で UART 書き込みは
  **無害**である。→ Fullerene の死因は UART ではない。
- pstore 記録 ("\nP3:U") の読み出しはデバイス復帰後 (待ち受けスクリプトが自動実行)。

### pstore は Android のユーザー空間が消費する (2026-10-02 昼の測定 — 09:05 判定の撤回)

09:23 に Android (8.0.0.151) 上で読み出して**完全に空**だった (pmsg/console とも 0)。
一方、今朝 02:58 起動分の console 240KB は 07:21 まで生存していた。両者の差は
「その間 Android が正常起動したかどうか」で、**Android のユーザー空間 (クラッシュ
レポート収集) が起動時に pstore を読み出して消去する**と結論できる。

**⟹ Android 起動を挟んだ「空 = 書けなかった」判定はすべて無効。**
09:05 の「Fullerene は mark_entry を書けていない」もここで**撤回**する。

読み出しが成立する条件:
- (a) プローブ自身が実行中に前回のゾーンを読む (次のプローブに持ち越し表示)
- (b) USB 再列挙など Android を介さないチャネル (2026-10-02 昼から試行中)
- ストック復元 → Android 起動 → 読み出し、は**必ず空になるので使えない**。

### Webカメラ検証 (2026-10-02 昼)

P20 Lite の画面は Webカメラで**読める**ことを確認 (アプリグリッドの並んだ
ホーム画面が明瞭。露出が合うまで数枚必要 — バースト撮影が有効)。
マゼンタ等の色検出はこのチャネルで自律実行できる。照準は端末向き。

### 空の pstore 読み出し (09:05) — 旧解釈 (無効、上記で撤回)

02:58 起動分の console ゾーン 240KB が 07:21 まで**複数ブートを跨いで生存**していた
実測があるため、「rescue ブートが pstore を消費する」説は否定される。
→ 09:05 の完全空 = **Fullerene は mark_entry の記録を書けていない**。
つまり死は「mark_entry 到達前 or その書き込み失敗」。

### QEMU での再確認 (ストック埋め込み Fullerene)

`fse_stock_image.bin` (ストック Image + Fullerene @0x1660000) を QEMU virt で実行:
- 最初の fault は **ELR 0x41731724 = 0x1660000 + 0xd1724** (コンソールの PL011 書き込み)
  のまま。**初期列 (プリアンブル→リロケーション→BSS→EL設定→mark_entry→コンソール)
  は完走している**。
- デバイス側では UART が無害と判明したため、**死因は「デバイスにしか無い差」の
  さらに後段**に絞られた → ステップマークで特定する。

### ステップマーク実装 (Fullerene entry.rs)

`aarch64_bootstrap` の5段に **pstore 直接追記** (リロケーション前でも安全な
「即値と adr のみ」のコード、ヘッダは初回に valid-and-empty で作成、size 最後):

| マーク | 意味 |
|---|---|
| `1` | bootstrap 到達 (entry shim + スタック確立) |
| `2` | boot state 読了 (CurrentEL / _start) |
| `3` | リロケーション完了 |
| `4` | BSS 消去完了 |
| `5` | EL1 設定完了 |

- 実装は `ane_step_byte()` (静的メモリ不可の局面で動くよう、静的参照ゼロ)。
- **QEMU 実証済み** (`ane_marks_qemu_proof.sh`): ゾーンを QEMU RAM (0x42000000) に
  リターゲットして実行 → QMP `xp` で `44 42 47 43 | 00*4 | 05 00 00 00 | "12345"` =
  **5段すべてがこの順で実行される**ことを機械的に確認 (PASS)。ソースは byte 単位で
  復元済み。
- デバイス用パッケージ: `artifacts/fullerene-ane-stepmarks-stock.img` (11,620,352 B)。

### ボタン不要サイクルへの道 (次の仕掛け)

LK の文字列に標準 BCB コマンド (`boot-recovery` / `bootloader`) と
misc 操作の痕跡 ("write misc cmd failed!" 等) が存在する。加えて
`set_reboot_reason()` (PMIC HRST_REG0 = +0x18B, 下位バイトがフラグ) により
**`adb reboot bootloader` が fastboot に入る**ことは実証済み。

1. **BCB 方式** (`ane_bcb_test.sh`): Android+root から misc に `bootloader` を書き、
   再起動 → fastboot に入るか / fastboot 入場後もフラグが残るか (sticky か) を
   2回の再起動だけで検証 (無害)。
   - sticky なら: プローブが SMC リセット → LK が BCB を読んで fastboot → 完全自動サイクル。
2. 非 sticky の場合: プローブから PMIC の理由レジスタを書く (SPMI 転送、
   ベンダーカーネルの `hisi_pmic_reg_read/write` と LK の読出しを一次ソースに実装)。
3. ループ→rescue 自動フォールバックも既知の逃げ道 (確認済み)。

### ツール追加 (p20-root)

- `ane_marks_qemu_proof.sh` — ステップマークの QEMU 実証 (リターゲット+QMP)。
- `ane_catch_recover.sh` — デバイスが (何時間後でも) fastboot/adb に現れたら
  ストック復元 + pstore 読み出しまで自動で行う待ち受け。
- `ane_bcb_test.sh` — BCB sticky テスト (上記)。
- Webカメラ解禁: 画面観察チャネル (マゼンタ検出など RCH 色分けの読み取りに使う。
  現在の照準は端末ではなくキーボード向き — 要再調整)。

### 確定した因果 (現時点)

1. LK は我々のコードに入る (リセットループ実証) — **確定**
2. MMU-off プリアンブルは必須で有効 — **確定**
3. ストック埋め込み形式は健全 (fb2 が同形式でループ) — **確定**
4. UART 書き込みは無害 — **確定** (棄却)
5. Fullerene は mark_entry の記録を書けていない — **確定** (生存実測に基づく)
6. 死因は「QEMU には無い、実機固有の差」のどこか — **ステップマークが特定する**

### 検証環境の注意 (今回ハマった点)

- QEMU virt の 0x348e0000 は **PCIe MMIO 窓内**で、アクセスはエラーにならず
  **黙って捨てられる**。デバイス用アドレスへの書き込みは QEMU で「無害に消える」ので、
  QEMU 検証は必ず RAM へリターゲットして行うこと。
- `test -e` / `ls` の misc 検出は by-name の実在に依存する。
- GNU grep 3.11 の `-E` は `\t` をタブと解釈しない (デバイス検出は `-P`)。

## 10. USB L1: ベンダーの起動手順によるコントローラ立ち上げ (2026-10-02 昼)

### なぜ DCTL トグルだけでは足りなかったか

前回の USB プローブ (MMU-off 修正済み) は DCTL.SftDiscon を正しくトグルしたが
ホストは完全沈黙 (`dark x1`、kern.log でもイベント 0)。原因は **PHY/コントローラの
クロックとリセットがローダ (LK) の時点で閉じたまま**であること。LK は fastboot を
終えると USB を畳んでカーネルへジャンプする。

### ベンダー一次ソースの起動手順 (そのまま実装)

`drivers/usb/susb/dwc_otg_hi6250.c` の `init_usb_otg_phy_hi6250()` が正解:

| # | 書き込み | 値 | 出典 |
|---|---|---|---|
| 1 | CRG+0x40 (\|OR) | bit6(pll)+bit2(ref)+bit1(hclk\=0x46) | DT の clkgate 3 つ + `hi3xxx_clkgate_enable` |
| 2 | PCTRL+0x64 bits24-26 | =5 (abb クロック設定) | `hi6250_enable_abb_clk` |
| 3 | CRG+0x94 (\|OR) | bit27(ADP)+bit14(32K)+bit11(AHBIF)+bit10(MUX) | `dwc_otg_hi6250.h` |
| 4 | AHBIF+0x00 (\|OR) | acaenb_sel\=bit2 + id_sel\=bit4 (0x14) | `hisi_usb_otg_type.h` |
| 5 | AHBIF+0x0C (=) | 0x06b866db (device eye pattern、DT 値) | DT |
| 6 | CRG+0x94 (\|OR) | bit13 (PHYPOR) + 待ち | 同上 |
| 7 | CRG+0x94 (\|OR) | bit12 (PHY) + 待ち | 同上 |
| 8 | CRG+0x94 (\|OR) | bit9 (OTG) | 同上 |
| 9 | AHBIF+0x08 (\|OR) | vbusvldsel\=bit2 + vbusvldext\=bit3 (0x0C) | `hisi_usb_otg_type.h` |
| 10 | DCTL (0xff100000+0x804) | bit1 クリア = attach | DWC2 |

レジスタ bases: CRG\=0xfff35000 / PCTRL\=0xe8a09000 / AHBIF\=0xff200000 /
DWC2 core\=0xff100000。RMW で書くのは、ベンダーコードが単独ビットを直接
書いているため (隣接クロックを壊さない)。

### 実装物

- `ane_usb_l1_probe.S` + `.sh` — 上記 10 ステップ。
  **QEMU 実証済み** (trace 20 words、全ステップ意図値どおり)。
  QEMU 検証が `movk #0xb866` の誤り (正: `#0x06b8`) を検出した — 計器の価値。
- `artifacts/fullerene-ane-usb-l1.img` = **hang 版** (SMC なし)。
  attach 後は停止したままなので、**ホストから安定して見える**。hung ブートは
  LK の自動フォールバック (~6-7分) で rescue に落ち、復旧はボタン1回。
- `artifacts/fullerene-ane-usb-l1-loop.img` = SMC ループ版 (生きたループが必要な時用)。
- `ane_usb_l1_run.sh` — 画面点灯 → flash → 480 秒監視 → 復元待ち受け。

### 判定の意味

- **attach が出る** → USB コントローラは生きており、**ホスト可視チャネル確立**。
  以降の読み出し (pstore の代わり) とユーザー目標「USB 再列挙ハーネス」が前進。
- **出ない** → さらに PHY 内部 (0xfe000000 の PHY レジスタ) や abb PLL の調査へ。

## 11. PMIC は MMIO 窓だった — 再起動理由をペイロードから書く道 (2026-10-02 昼)

### 発見

デバイス自身の DT とベンダーカーネルから:

- `/pmic@FFF34000` = `hisilicon,hisi-pmic` (**MMIO ノード**)
- `/clocks@0/clk_pmuctrl@0xfff34000` = `hisilicon,hi6421pmic` → クロックドライバは
  **`of_iomap`** でアクセス (clk-kirin-common.c, HS_PMUCTRL ケース)
- blackbox の `set_reboot_reason()` は FPGA 分岐で `readl(pmu_reset_reg)` (直接アクセス)。
  非 FPGA の `hisi_pmic_reg_read/write(reg)` も同じ「レジスタ番号 = 窓内オフセット」
  の形 (呼び出し側は 0x18B / 0x010F といった番号をそのまま渡す)。

**⟹ `hisi_pmic_reg_read/write(reg)` = `0xFFF34000 + reg` への load/store**。
「SPMI 実装が必要」という以前の評価は**撤回**。

### 再起動理由 (ボタン不要化の鍵)

| 項目 | 値 | 出典 |
|---|---|---|
| レジスタ | PMIC `0x18B` (HRST_REG0、下位バイトのみ有効) | `mntn_public_interface.h` |
| マスク | `RST_FLAG_MASK = 0xFF` | 同上 |
| BOOTLOADER | `0x01` | 同上の enum |
| 書き手 | `set_reboot_reason()` | rdr_hisi_ap_adapter.c |

**「理由プローブ」= `strb 0x01 → 0xFFF34000+0x18B` + SMC リセット** を作成・QEMU 検証済み
(`ane_reason_probe.S` / `artifacts/fullerene-ane-reason-probe.img` / `ane_reason_run.sh`)。
**成功すればプローブ終了 → LK が自力で fastboot**。失敗時は通常リセットでループ
(可視・安全)。→ **次の fastboot 到達で自動投入待ち**。

### USB の残り部品も PMIC だった

`clk_abb_192` (USB PHY の親クロック) のゲートも **PMIC 経由**:

- DT の `hisilicon,clkgate` をデコード: `gdata=[0x010F, 0x0]` → **PMIC 0x010F の
  bit0** (`ebits = BIT(gdata[1])`, `pmu_clk_enable = gdata[0]`)。
- abb 固有の手順 (clk-kirin-common.c `hi3xxx_multicore_abb_clkgate_prepare`):
  [sctrl (`0xfff0a000`、`hisilicon,sysctrl`、status ok ✓) の `SCBAKDATA12` の
  AP_ABB_EN(bit0) を見る → LPM3_ABB_EN(bit1) が 0 なら PMIC 0x010F |= bit0 →
  AP_ABB_EN を立てる] + hwspinlock 9 (**ペイロード単独実行なら省略可**)。
- **⟹ L1-v2 = L1 + この abb ゲート**。L1 (クロック3ゲート+PHY+リセット+DCTL) は
  実機で attach が出なかった (2026-10-02 09:38、沈黙) ため、abb が本命の欠け。

### リカバリ自動復帰の仕組み (実装済み)

- `ane_revive_watch.sh` — リカバリ (12d1:107e 1インターフェース) を検知したら、
  `tools/ane_usb_revive_root.sh` (authorized 0→1 の論理抜き差し) を sudo -n で
  段階的に試行。fastboot/adb は run 尾部に任せ、二重操作を避ける。
- 有効化には sudoers 1 行 (NOPASSWD、この1ファイル限定) が必要。
  未設定の間は監視ログのみ (passive)。

## 12. フォールバックの行き先は「終わり方」で決まる + 高速捕捉 (2026-10-02 午後)

### 実測 (本日2例)

| プローブの終わり方 | LK のフォールバック先 | 所要 |
|---|---|---|
| **ハング** (wfe、リセットなし) — L1 (09:38:06) | **fastboot** (18d1:d00d, 09:42:46) | ~4.5 分 |
| SMC リセットループ — fb2 / pp (午前) | rescue (12d1:107e 1if) | ~4.5-5 分 |

**⟹ 規則 (実測ベース): ハングしたブートは LK の watchdog 経由で fastboot に、
SMC リセットで「正常リブート」を繰り返すブートは rescue に落ちる。**
自走させたいプローブは **SMC を付けずハングで終える**こと。これで
「プローブ実行 → ~4.5 分待つ → fastboot → 自動復元 → Android」が
**ボタン不要**で回る (09:42:46 の fastboot を実際に捕捉して復元フローに入った)。

### 捕捉は高速化が必要

フォールバックの fastboot 窓は **1.6 秒** (09:42:46.265 → 09:42:48.675) しかなかった。
5-10 秒ポーリングでは取り逃す → `ane_fast_catch.sh`:
**カーネルログを `journalctl -k -f` で監視し、`idVendor=18d1` の出現で即復元**
(検知 ~0.2 秒、フラッシュ ~0.5 秒)。1 時間窓で稼働。

### 理由プローブの結果 (負の結果 — 記録)

`strb 0x01 → 0xFFF34000+0x18B` + SMC: **fastboot は出なかった** (90 秒待ち)。
⟹ 「MMIO 窓に直接書けば届く」仮説は**この形では不成立**。
考えられる原因と次の検証:

1. **アクセス幅/オフセット**: PMIC レジスタが窓内で 4 バイト間隔 (0x18B → 0x62C) の可能。
2. **SPMI / メールボックス経由** (FPGA 分岐の直接 readl は FPGA 専用の可能性)。
3. 隠れたプロテクト/シーケンス。

**次の一手 (Android 復帰後、root 1回で決着):**
`devmem` で `0xFFF34000+0x18B` を読み、書いて読み戻す —
窓が直接 R/W なら通る。通らなければ 0x62C や SPMI 系を順に。
(書き込む値は理由バイトなのでリスクは低い。)

## 13. ステップマーク v2 = 専用スクラッチ + 描画プローブ (2026-10-02 昼)

### v1 (pmsg 直書き) を捨てた理由
- Android ユーザー空間が起動時に pmsg ゾーンを消費するため読めない。
- 黒箱の耐久テキストログが同じ pmsg ゾーンのデータ領域へ追記されるため、
  生マークとテキストが混在し両方の解釈を汚す。

### v2 の構造 (実装・QEMU 証明済み)
- マーク先 = ramoops コンソールゾーンの未使用テール:
  **0x34800000 + 0x60000 (コンソールゾーン) + 0x7F000 = 0x348DF000**
  (コンソールミラーはゾーン先頭 1KB しか書かず、pmsg ログは隣のゾーン。
   どの pstore リーダーもこの領域を解釈しない)
- レイアウト: magic `ANEM` / count / バイト列。count を最後に書く。
- 各ブート冒頭で `ane_step_begin` が magic+count=0 へリセット
  (前回ブートのマークへの追記を防ぐ)。
- 段階 (計 12): 1=ブートストラップ到達, 2=boot state 読了, 3=リロケ完了,
  4=BSS 消去, 5=EL1 設定 (entry.rs)。6=Rust entry, 7=UART+例外ベクタ,
  8=DT 走査+黒箱確保, 9=UFS 契約段, a=MMU, b=タイマ, c=アーリーブート完了
  (main.rs)。
- **読み出し = 描画プローブ** (`ane_paint_probe.S`): 次のブートでスクラッチを
  読み、RCH 候補バッファ 4 本 + 固定フォールバックに色帯で描画。
  帯 0 = 白 (プローブ生存)、帯 k = マーク k (色は PAL[k%8] の巡回:
  白 緑 青 黄 シアン マゼンタ 赤 オレンジ)。カメラ + `ane_cam_read.py` で
  帯数を数える = どこで死んだか。ハング終わり (fallback→fastboot 自走可)。
- QEMU 証明 (`ane_marks_qemu_proof.sh`): スクラッチを RAM 0x42000000 へ
  リターゲットして `ANEM`+count=6+`123456` を読戻し (QEMU は PL011 が無く
  UART 初期化でフォールトするため 6 で止まる。実機では c まで進む想定)。
- パッケージ: `artifacts/fullerene-ane-stepmarks2-stock.img` (byte-exact 検証済み)。

### 副産物: RCH プローブの実バグ修正
- `movz w19, #(BASE>>16), lsl #16` の直後に `movk` が無く、VG1/G0 が
  **誤ったアドレス** (0xE8620000 / 0xE8630000) を読んでいた。
  QEMU の defsym が 64KB 整列 (0x440x0000) だったため証明をすり抜けた。
- 再発防止: `tools/verify_base_loads.py` — ビルド済み ELF を逆アセンブルし、
  レジスタがロード/ストアのベースとして使われる時点の値集合が期待と
  **厳密一致**するか検査する。RCH と描画プローブのビルドに組込み済み。
  QEMU 側のベースも非整列 (0x44xx8000) にして movk 経路を強制。
- 監査 (`tools/audit_movz_movk.sh`) で他の全プローブは問題なしと確認。

## 14. ソフトリセットは PHY 選択も消す — GUSBCFG の再書き込み

一次ソース: `drivers/usb/dwc2/core.c`。

- `dwc2_hs_phy_init()` は PHY パラメータ (UTMI+ 8bit / force-device) を書いた
  **後**にコアソフトリセットを掛ける ("Reset after setting the PHY parameters")。
- `dwc2_core_reset()` はリセット自己解除を待ってから **GUSBCFG をもう一度**書く
  (dr_mode に応じた force-device / force-host)。
- 正しい順序: [GUSBCFG] → [CSftRst] → [GUSBCFG 再書き] → [settle] → [DCFG]。

L1c は再書き込みが無かった (リセット前のみ)。リセットが PHY 選択を戻すなら
attach しない説明がつく。trace 14 として再書き込みを追加し QEMU で値検証済み。

## 15. L2 = EP0 応答器 — attach を「見える USB デバイス」に

一次ソース: `drivers/usb/dwc2/gadget.c` (s3c_hsotg_handle_rx / start_req /
stall_ep0) + `drivers/usb/susb/dwc_otg_cil.c` (ep0_activate) + `hw.h`。

- SETUP 受信 = RXFIFO の status entry 経由: GINTSTS.RXFLVL(bit4) ポーリング →
  GRXSTSP(0x020) pop、PKTSTS=6 (SETUPRX) なら DFIFO0(0x1000) から 8B 読む。
- 転送開始: [DIEPTSIZ0 = xfersize | pktcnt(1)<<19] → [DIEPCTL0 |= usbactep(15)
  | cnak(26) | epena(31)] → パケット語を FIFO0 へ書き込み (slave=ソフト書込み)。
- 応答: GET_DESCRIPTOR(device/config 18B)、SET_ADDRESS (status 完了後に DCFG 適用、
  DIEPINT0.xfercompl ポーリング)、SET_CONFIGURATION (0 長 ACK)、他は STALL
  (DIEPCTL0.stall bit21 + cnak)。提示 = vendor-specific (class 0xff)、
  interface 1・endpoint 0 = ドライバがバインドされない最小構成。VID 0x12d1/PID 0x0001。
- 判定 = ホストの `lsusb`/dmesg が唯一 (QEMU に DWC2 モデルは無い)。
  QEMU 証明は preamble 14 段 + cgnpinnak/EP0 mps/応答器到達の 3 段の trace のみ。
- 副修正: `.set` でデフォルトを与えると `--defsym` を上書きし、QEMU ビルドが
  実機アドレスへ書いて全ゼロ trace になった (今回の FAIL の原因)。L2 は .set なし。

## 16. 早期コンソールのクロックゲート (仮説つき先行修正)

- 観測: Fullerene は実機でマーク 6 (Rust entry) の後、7 (UART+例外ベクタ) の前で
  死ぬ可能性が高い (QEMU でも同じ区間で止まる。プローブの描画リーダで検証中)。
- 一次情報: ANE の uart ノード (`arm,pl011`, 0xfdf02000, status ok) の
  `hisilicon,hi3xxx-clkgate = <0x00000020 0x00000400>` → CRG (0xfff35000) +0x20 の
  bit10 がゲート。USB プローブで使っている vendor エンコーディングと同じ。
- 修正: `platform::ane::prepare_console()` = CRG+0x20 bit10 を立ててから
  `uart::init_at` へ。開いていれば no-op、閉じていれば最初の PL011 書込みが
  「誰も応答しないバスアクセス」になるのを防ぐ。
- 検証: ANE ビルド PASS + QEMU マーク証明 PASS (「ANEM」+count=6+「123456」。
  死点は 6-7 間のまま = 期待通り)。成果物
  `artifacts/fullerene-ane-stepmarks2-stock.img` を修正版で再生成 (byte-exact)。
  夜間ループの次パスから実機で検証される (マーク 7 が出れば仮説確定)。

## 17. 早期パークベクタ = FullereneOS の eRecovery 落ち殺し (2026-10-04 05:2x)

### 動機 (ユーザー実測)
- Fullerene 本体は mark 6→7 の間 (コンソールのクロックゲート + UART 初期化) で死ぬ
  (仮説、paint-probe 読み待ち)。**その時点ではまだ独自ベクタが無い**ため、フォルトは
  LK の残置ベクタ経由で処理されて rescue 系 (eRecovery 行き) になりやすい。
- 「FullereneOS でいくと ERECOVERY 落ちする」(ユーザー) = この窓のフォルト行き先。

### 設計 (entry.rs)
- `aarch64_bootstrap` の先頭、`ane_step_begin()` より前に `ane_install_early_vectors()`:
  - `.text.ane_early_vectors` (`.balign 2048`) に 16 スロット、全部 `b ane_early_vector_hang`
  - ハンドラ: `msr daifset, #0xf` → マークブロック (0x348DF000) に 'F' (0x46) を追記
    (count<16 ガード) → `wfe; b .` のパーク (リセットしない)
  - インストーラ: `adr x9, table` → `msr vbar_el1, x9` → EL2 なら `msr vbar_el2, x9` → `isb; ret`
  - register-only (リロケーション前・スタック不要で安全)。mark 7 で exceptions::install() が
    本ベクタに差し替えるため、本ベクタの担当区間 = bootstrap 冒頭〜mark 7。
- 根拠則 = §12: ハング終わり → LK watchdog → fastboot / リセット反復 → rescue。
  本ベクタはフォルトを「パーク (ハング)」に変え、fastboot 側へ落とす。
- 注意 (2026-10-04 05:1x 実測): 行き先は「終わり方」だけでなく LK の連続失敗カウンタの
  状態にも依存する。カウンタが熱いと fastboot 窓なしで直接 eRecovery (RCH run-2 実測:
  起動+154s、窓はログに出現せず)。完全電源 OFF でカウンタを冷ますこと。

### 検証 (ホスト側)
- `tools/verify_ane_early_vectors.py` — ELF はシンボルテーブルが剥がれている (.dynsym のみ) ため、
  **Image (生 arm64) のバイト走査 + 生逆アセンブル**で検証する:
  - 16 スロットが 128B 間隔 + ゼロ詰め + 全スロット同一ターゲット (2KB 整列)
  - ハンドラ窓に daifset / #0xf000 / movk #0x348d / strb / wfe
  - `msr vbar_el1` 窓に vbar_el2 + currentel (本体の例外設置と区別) → adr がテーブルを指す
  - 注意: objdump は movz を mov エイリアスで印字し、adrp+add は近距離なら単一 adr に折畳む
- 実測 (stepmarks3 ビルド): テーブル 0x12000、ハンドラ 0x12800、インストーラ adr → 0x12000 = PASS
- 成果物: `artifacts/fullerene-ane-stepmarks3-stock.img` (11,620,352 B, byte-exact)

### 実機テスト (結果)
- 2026-10-04 05:36 stepmarks3 実機ラン: カウンタ冷却 → flash → fastboot 窓出現 (05:44:42) = 殺しの実機成立。
  以降の失敗ブートは毎回「窓 or eRecovery 着地」で自動捕獲復元 (10+ 回) ⇒ パーク設計は機能している
- マーク読出 (08:22 写真): 記録 = count=9 "123456789"。'F' (0x46) は無し = 今回の停止は
  フォルト経由でない (ハンドラ未発火のハング)。読み出し系の全体確定とブート現在地は §18

## 18. 読み出し系の完成 — スキャン元 0x31000000 とブート現在地 (2026-10-04 朝)

### テキストコンソール (新・読み出しの主役)
- 8x8 フォント (0-9 A-F V R C 空白 の 19 グリフ) を 4x スケールで 12 行 x 33 字の
  ビットマップ (1080x496, 0x210000 B) に描画 → 黒地に字 (色 0xFFFFFF00、パネル上は黄緑に写る)
- blit 先: 全 10 チャネル x 3 スロット (+0x60/+0x84/+0xA8 = DATA_ADDR0/1/2 = LK の 3 枚回転 FB)
  + 固定 0x31000000。blit 後はスピンして画面保持 (そのままハング → §12 の fastboot 経路)
- 生成器: `ane_text_probe.S` + `ane_text_probe.sh` (byte-exact 埋め込み)。QEMU 全 PASS
- 成果物: artifacts/fullerene-ane-text-fix-stock.img

### 確定事実 (このランで得た)
1. スキャン元 = 0x31000000 (fallback)。実機で画面に出た (ユーザー写真で全行読取)
2. ランタイムの DSS DATA_ADDR は概ね 0 (LK がクリア済み)。チャネル値に依拠しない
3. 読取は MJPEG 1920x1080 (eMeet C960) で。640x480 YUYV は 12 行を解像できない

### 記録の実読取 (08:22 写真)
- count=9, マーク "123456789" (+9 バイト目に前回残骸 0x61 AE E2...)。ステップ表:
  1-5 entry.rs ブートストラップ / 6 Rust エントリ / 7 コンソール+ベクタ /
  8 UFS 契約ステージ / 9 同ステージ戻り (main.rs:843) / a MMU 初期化完了 (main.rs:857) / b,c 続く
- 死点 = main.rs:843-857 間 = mmu::init() 内のハング。'F' なし = フォルト経由でない
- 次の一手 = mmu::init() の一次ソース確認 (アイデンティティマップ範囲・属性・DSB/ISB 待ち)

### レジスタベース誤りの記録 (06:13-08:19 の全プローブ無効)
- 誤: 0xE8643000 系 / 正 (vendor tree, rch_probe2 正典):
  VG0=0xE8620000 VG1=0xE8628000 G0=0xE8638000 G1=0xE8640000
  D0..D3=0xE8650000/0xE8651000/0xE8652000/0xE8653000 WCH0=0xE865A000 WCH1=0xE865C000
- この期間の「値」と消去法 (WCH0 シロ等) は全て無効

### 付録: 微小カーペット (クリップ式スタンプ)
- コード島の直下/直上を安全に塗るには「部分スタンプ」: 島手前で長さを島境界にクリップ、
  島内開始はスキップ。範囲 [0x1840000, 0x1C60000) を 256KB 刻みで被覆
  (ane_text_carpet.S、QEMU でクリップ経路も証明済み)
- 教訓: スタンプ長 > 刻みにしないと「島込み判定で周辺ごとスキップ」の盲点ができる
  (v1/v2 の実例: [0x1840000, 0x1C60000) が丸ごと盲点化)
