
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

### 空の pstore 読み出し (09:05) の解釈 — 判定は有効

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
