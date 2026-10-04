
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
