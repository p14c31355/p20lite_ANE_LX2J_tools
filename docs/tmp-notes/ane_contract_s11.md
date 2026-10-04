
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
