# ANE-LX2J USB 立ち上げ資料 (一次ソース由来)

2026-10-02 版。出典: OpenKirin/android_kernel_huawei_hi6250 (ベンダーツリー) +
端末実測 FDT (`firmware/ane_dtb/fdt_properties.txt`) + 上流 Linux `drivers/usb/dwc2/`。
すべてのアドレス・値は「その根拠」付きで記載する。

## 1. ブロックとアドレス (全て実測 DT + ドライバの compatible 照合で確定)

| 役割 | アドレス | 出典 |
|---|---|---|
| DWC2 コア | 0xff100000 | DT `/hisi_usb@ff100000` (hisilicon,hi6250-usb-otg), reg=0x40000 |
| AHB IF | 0xff200000 | DT `/usb_otg_ahbif@ff200000` (hisilicon,usb-otg-ahbif) |
| pctrl | 0xe8a09000 | DT `/pctrl@e8a09000` (hisilicon,pctrl), ドライバは compatible 検索 |
| CRG | 0xfff35000 | DT `/clocks@0/crgctrl@0xfff35000` (hisilicon,clk-crgctrl) |

ドライバの取得方法 (`dwc_otg_hicommon.c:284-306`): それぞれ
`of_find_compatible_node(NULL, NULL, "hisilicon,usb-otg-ahbif" / "hisilicon,pctrl" /
"hisilicon,crgctrl")` + `of_iomap(np, 0)`。つまり **DT の compatible 検索**。

## 2. AHB IF レジスタ (`hisi_usb_otg_type.h:291-315` の構造体)

struct usb_ahbif_registers は u32 の連続 (union は全て uint32_t サイズ):

| オフセット | 名前 | ビット |
|---|---|---|
| +0x00 | usbotg2_ctrl0 | acaenb_sel=bit2, acaenb=bit3, id_sel=bit4-5, vbusvalid_sel=bit9 |
| +0x08 | usbotg2_ctrl2 | vbusvldsel=bit2, vbusvldext=bit3 |
| +0x0C | usbotg2_ctrl3 | eye pattern 値そのもの |
| +0x18.. | bc_ctrl0..8 | (バッテリチャージ検出) |
| +0x3C.. | bc_sts0..4 | |
| +0x50 | usbotg2_ctrl6 | |
| +0x54 | usbotg2_sts | |

## 3. CRG / PCTRL レジスタ (`dwc_otg_hi6250.h`)

| オフセット | 名前 | 備考 |
|---|---|---|
| CRG+0x40 | PERI_CRG_CLK_EN4 | BIT_HCLK_USB2OTG=bit1, BIT_CLK_USB2OTG_REF=bit2, BIT_HCLK_USB2OTG_PMU=bit0 |
| CRG+0x44 | PERI_CRG_CLK_DIS4 | |
| CRG+0x48 | PERI_CRG_CLK_CLKEN4 | |
| CRG+0x4C | PERI_CRG_CLK_STAT4 | |
| CRG+0x90 | PERI_CRG_RSTEN4 | |
| CRG+0x94 | PERI_CRG_RSTDIS4 | |
| CRG+0x98 | PERI_CRG_RSTSTAT4 | |
| pctrl+0x64 | PCTRL_PERI_CTRL24 | ABB クロック設定: bit[26:24]=5 (書込み時)、bit24=消灯 (OFF 時) |

リセットビット (RSTDIS4 に書いて解除 / RSTEN4 に書いてリセット):
- BIT_RST_USB2OTG_MUX = 1<<10
- BIT_RST_USB2OTG_AHBIF = 1<<11
- BIT_RST_USB2OTG_ADP = 1<<27
- BIT_RST_USB2OTG_32K = 1<<14
- BIT_RST_USB2OTG = 1<<9 (HCLK ドメイン)
- BIT_RST_USB2OTGPHY = 1<<12
- BIT_RST_USB2OTGPHYPOR = 1<<13

## 4. PHY 初期化列 (`dwc_otg_hi6250.c:49-114` をそのまま)

```
1.  ctrl0 の id_sel=1, acaenb_sel=1, acaenb=0
2.  ctrl3 = eyePattern (device) / host_eyePattern (host)   ← 端末実測値: 0x06b866db / 0x073f679f
3.  RSTDIS4 |= RSTUSB2OTGPHYPOR ; udelay(50)
4.  RSTDIS4 |= RSTUSB2OTGPHY    ; udelay(100)
5.  RSTDIS4 |= RSTUSB2OTG
6.  ctrl2 の vbusvldsel=1, vbusvldext=1 ; msleep(1)
```
※ 手順 1 の前に: CLK_EN4 |= BIT_HCLK_USB2OTG、RSTDIS4 |= (ADP|32K|MUX|AHBIF) が要る
(`dwc_otg_hi6250.c:61-67` の順序)。つまり完全な順序は
「HCLK 有効化 → AHBIF アンリセット → ctrl0 → ctrl3 → PHY POR リセット解除 (+50us)
→ PHY clk リセット解除 (+100us) → HCLK ドメイン リセット解除 → ctrl2 vbusvld 設定 (+1ms)」。

## 5. クロック (`dwc_otg_hicommon.c`)

- `devm_clk_get(base_dev, "clk_abb_192")` → ABB クロック。PCTRL_PERI_CTRL24 の後
  `clk_prepare_enable` する。DT 側 `clock-names = "clk_abb_192\0hclk_usb2otg"`。
- `devm_clk_get(base_dev, "hclk_usb2otg")` + `clk_set_rate(..., USB2OTG_HCLK_FREQ)`。
  **USB2OTG_HCLK_FREQ = 240000000 (240MHz)** (`dwc_otg_hicommon.h:11`)。
- 端末 DT のクロック供給: crgctrl 内の `clk_usb2phy_pll` / `clk_usb2phy_ref` /
  `hclk_usb2otg` / `clk_abb_usb` (fixed-factor / gate)。

## 6. DWC2 コアの device モード立ち上げ (参照: 上流 drivers/usb/dwc2/)

コアは DWC2 系 (Synopsys)。レジスタは上流 `dwc2/hw.h` のマップが使える
(ベンダーの CIL でも DCTL=+0x804, sftdiscon=bit1 と一致)。

立ち上げ順 (上流 `dwc2/core.c` / `gadget.c` の該当箇所):
1. `GRSTCTL.csftrst=1` → 0 待ち  (コアのソフトリセット)
2. `GUSBCFG.forcedevmode=1`      (device モード固定)
3. `DCFG` に device speed (HS=3) / devaddr=0
4. `GAHBCFG` (割込み/DMA 設定。最最小構成なら DMA なしでも EP0 は動く)
5. `GINTMSK` 有効化 (USBRST, ENUMDONE, RXFLVL, OUTEPINT...)
6. `DCTL.sftdiscon=0`           ← ここでホストに connect が見える
7. USBRST 割込み後に `DFIFO` / `DOEPCTL0` / `DIEPCTL0` を設定して EP0 を開く

最小実験順序 (我々のラダー):
- L0: SftDiscon トグルだけで attach/detach がホストに見えるか (LK の残置状態の検証)
- L1: 上記 1-6 を自前で実行して attach させる (LK が畳んでいた場合)
- L2: EP0 setup/descriptor 応答 (完全な列挙)

## 7. 未確定事項 (測定で埋める)

- LK はハンドオフ時に USB コアを「畳んで」いるか (クロックゲート / SftDiscon のみ) か。
  → USB プローブ (DCTL トグルのみ) が直接答える。ホストにイベントが出れば「残置されていた」。
- LK の MMU 状態 (on/off)。on の場合、pstore 予約域はそのテーブルに無い可能性が高く
  メモリ書込みが落ちた説明がつく。USB ブロックは LK 自身が使っていたので、
  どちらの状態でも到達できる可能性が高い (だから USB 経路が先)。
- PSCI の SMC が EL1 から EL3 に届くか (TSC 設定次第)。
  → USB プローブの SMC リセット部が答える (リセットループの有無)。

## 8. 関連ファイル (p20-root)

- `ane_usb_probe.S` / `ane_usb_probe.sh` / `ane_usb_probe_run.sh` — USB プローブ本体と検証・実行
- `ane_usb_monitor.py` — ホスト側 USB 監視 (再列挙ハーネス)。校正済み指紋:
  fastboot=18d1:d00d "Fastboot2.0" / Android 系=12d1:107e bcdDevice 2.99
- `firmware/ane_dtb/fdt_properties.txt` — 端末実測 FDT 全プロパティ (15,121 件)
- `~/dev/hi6250-src` — ベンダーカーネルソース (sparse checkout: drivers/usb, drivers/phy 等)
