# ANE-LX2J USB 立ち上げ: 現状と次の手 (2026-10-02 08:00 時点)

## あなたの指示への回答: SD カード案について

結論から言うと、SD への文字列出力は「FullereneOS が動いているから無理」というより
**「SD/MMC ドライバスタック一式 (コントローラ初期化 + カードプロトコル + ブロック書き込み)
が必要で、プローブ規模の話ではない」** という理由で後回しが正解です。

- FAT は不要 (生セクタ書き込みなら CMD24 一発) ですが、そこに至るまでに
  DW MSHC のレジスタ初期化 + SD カードの初期化列 (CMD0/CMD8/ACMD41/CMD2/CMD3/CMD7/ACMD6)
  が必要で、数百行 + LK が残したクロック状態の知識が要ります。
- しかもこれは「LK が我々のコードに入っているか」という**最初の疑問には答えられません**。
  7 命令の PSCI リセットプローブの方が 100 倍安く同じ疑問に答えます。
- ただし長期の出力チャネルとしては正当です (Fullerene のドライバ作業として)。
  LK 自身が SD から dload を読むので、LK の SD ドライバ状態を引き継ぐ handoff も
  将来の選択肢です (Bramble の USB handoff と同じ構図)。

## 方針転換 (あなたの指示): USB 再列挙ハーネス

### 判明した ANE の USB 構成 (デバイスツリー + 一次ソース)

```
/usb@fe000000          hisilicon,hisi-usb2phy      (USB2 PHY, 1MB)
/hisi_usb@ff100000     hisilicon,hi6250-usb-otg    (コントローラ核, 256KB)
/usb_otg_ahbif@ff200000 hisilicon,usb-otg-ahbif    (AHB IF, 256KB)
/pmic@FFF34000/usbvbus hisilicon,usbvbus
CRG @0xfff35000: clk_usb2phy_pll / clk_usb2phy_ref / hclk_usb2otg / clk_abb_usb
```

カーネルソース (OpenKirin/android_kernel_huawei_hi6250) を取得し、
`drivers/usb/susb/dwc_otg_hi6250.c` を読了。**コアは Synopsys DWC2 (dwc_otg) 系**で、
Huawei グルーの初期化列はこれで完全に手に入りました:

1. HCLK_USB2OTG を PERI_CRG_CLK_EN4 で有効化
2. AHBIF のアンリセット (ADP | 32K | MUX | AHBIF ビットを PERI_CRG_RSTDIS4 へ)
3. ahbif ctrl0: id_sel=1, acaenb_sel=1, acaenb=0
4. ahbif ctrl3: eyePattern (device モード値)
5. PHY POR アンリセット -> udelay(50) -> PHY clk アンリセット -> udelay(100)
6. HCLK ドメインアンリセット
7. ahbif ctrl2: vbusvldsel=1, vbusvldext=1 -> msleep(1)
8. ABB クロック: PCTRL_PERI_CTRL24 のビット[26:24] = 5、その後 clk_abb_usb 有効化

DWC2 の device モード初期化は Linux の `drivers/usb/dwc2/` (上流) がそのまま参照できます。
Bramble の DWC3 コードは使えませんが、**観測規律 (ホスト側で測る) と ツール類は流用**できます。

### ハーネス構築状況

- ホスト側監視ツール `ane_usb_monitor.py` を実装・**実データで校正済み**。
  校正中に分類バグ (12d1:107e を fastboot と誤認) を自分で検出・修正しました。
  - 正しい指紋 (kern.log 実測): fastboot = `18d1:d00d` "Fastboot2.0" /
    Android 系 = `12d1:107e` bcdDevice 2.99 (インターフェース数で段階分類)
  - 未知の VID:PID が出たら「UNKNOWN-CANDIDATE」= **我々の USB が出た合図** として
    機械的に検出します
  - ホスト側 kern.log のアタッチ/切断/デスクリプタエラー (-71 系) も時系列で記録
- 既存資産: `tools/usbmon_parse.py` ほか Bramble の usbmon ツール群 (そのまま流用可)

### 現在の未解決点 (測定中)

前回の一連のプローブ (v1/v2/リセット) について、
**どのイメージが実際に kernel パーティションに焼かれたか / LK が我々のコードに入ったか**
が未確定です。今、`/proc/version` と kernel パーティションのハッシュ突合で特定中です
(端末は現在 Android 系が起動中、adb 待ち)。

## あなたへの確認 (2 点)

1. さっきの **リセットプローブ実験のとき、画面はどうでしたか?**
   (HUAWEI ロゴが繰り返し出るループ / 暗いまま / その他)
   — ループしていたら「LK が我々のコードに入っている」の決定的証拠になります。
2. 今の画面は何でしょう? (Android の起動画面 / リカバリのメニュー)

次の一手: 特定が済み次第、fastboot セッションでリセットプローブを正式に 1 回やって
「LK エントリ」の可否を確定 -> その後 USB アタッチ実験 (SftDiscon トグル) に進みます。
