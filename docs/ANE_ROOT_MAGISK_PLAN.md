# ANE root 取得計画 — Magisk ramdisk 方式 (Phase 2 → Phase 1)

前提: ANE-LX2J は **解錠済み (BLU, verifiedbootstate=orange)**。よって通常の
「解錠済み端末の root 化」= Magisk パッチ ramdisk が使える。エクスプロイト勝負
(CVE-2019-2215 ループ) を恒久的に置き換えるのが狙い。

出典: XDA [ROOT][UNLOCK][ANE-LX1/L01/L21][Stock EMUI 8/9] P20 Lite ほか
  "fastboot flash ramdisk patched_boot.img" → root + 純正 ROM + OTA 維持、
  stock ramdisk に戻せば原状回復。

## 資材 (確保済み)

| 品目 | 場所 | 備考 |
|---|---|---|
| stock ramdisk (8.0.0.110 C635) | firmware/stock_ramdisk_110C635.img | 16MB, "Android bootimg" KERNEL_SZ=0, OS 8.0.0, patch 2018-04, gzip ramdisk, sha256 a92bb4737f10300f8fe46f03fc9a5bbeb96e6e01f5dabbed1c8232c5b36c89f6 |
| stock recovery_ramdisk (同) | firmware/stock_recovery_ramdisk_110C635.img | 32MB |
| Magisk v23.0 APK (本命) | firmware/magisk/Magisk-v23.0.apk | EMUI8 世代の定番 |
| Magisk v30.7 APK (予備) | firmware/magisk/Magisk-v30.7.apk | 最新 |
| magiskboot (host) | firmware/magisk/magiskboot | v30.7 から抽出。unpack 動作確認済み |
| magiskinit 等 arm64 | firmware/magisk/v23-arm64/ v307-arm64/ | host 側工作用の予備 |
| 公式 RAR 群 | firmware/ane110 (110 C635), firmware/azrom/ (127 C719, 202 C719, TL00 151) | dload 復旧の最終保険 |

| dload110 (実体) | firmware/dload110/ | 8.0.0.110 C635 の dload 実体 (update_sd.zip 2.06GB + hw_jp)。/tmp 消失対策の保全コピー (10/3 作成) |
| 候補 ramdisk 群 | firmware/cand_ramdisks/ | TL00_151C01 a788230c / LX2J_127C719 (=kddi 版と同一 sha) 1a6e7d9c / L22J_202C719 e9d36168。TL00_151 は版数一致の代替候補 |
| 7z 25.01 | ~/opt/7z2501/7zz | 公式最新 (10/3 取得)。システムの 7z 23.01 はこの RAR5 の展開が壊れており「Unsupported Method」で全メンバー失敗 → **RAR 展開は必ず 25.01 の方を使う** (t で Everything is Ok 確認済) |

バージョン差メモ: 端末は 8.0.0.151、素材は 8.0.0.110 (同一機種・同一 C635)。
まず 110 で進め、**root が入った後に現物 (151) の ramdisk を dd で保全**する。
(現物確保は「エクスプロイトが先に勝った場合」にも dd で行う)

## Phase A: パッチ + 焼き

1. exploit ループ (ane_pmsg_read32.sh) を止める
   - 勝てば自動 exit 0。負けなら attempt 5 の settle 中に kill (reboot 直後で安全)
   - **root 試行中は絶対に触らない** (heap グローミングを乱さない)
2. 端末 (Android, adb) へ配布:
   - `adb push firmware/stock_ramdisk_110C635.img /sdcard/Download/`
   - `adb install firmware/magisk/Magisk-v23.0.apk` (提供元不明アプリ許可)
3. Magisk アプリ: Install → Install → "Patch Boot Image File" → stock_ramdisk_110C635.img を選択
   → Download/ に magisk_patched-*.img が出る
4. `adb pull /sdcard/Download/magisk_patched-*.img usb_runs/ramdisk_magisk_v23.img`
5. host 検証: `firmware/magisk/magiskboot unpack usb_runs/ramdisk_magisk_v23.img`
   → ramdisk.cpio の中に magiskinit 差し替えがあること
6. fastboot へ (`adb reboot bootloader`) → 焼き:
   - `fastboot flash ramdisk usb_runs/ramdisk_magisk_v23.img`
   - `fastboot reboot`
   - ※ recovery_ramdisk / eRecovery は**触らない** (XDA の eRecovery 上書き変種は危険なので回避)
7. 検証: 起動後 `adb shell su -c id` → uid=0 ✓ / Magisk アプリの状態確認
8. 現物保全 (可能なら): `su -c "dd if=/dev/block/by-name/ramdisk of=/data/local/tmp/ramdisk_now.img"` → pull
   (エクスプロイトが先に勝った周回でも同じ dd を行う)

失敗時の復旧:
- `fastboot flash ramdisk firmware/stock_ramdisk_110C635.img` (unroot 戻し)
- 最終手段: dload (RAR 群 + SD カード)。misc BCB 機構は健在

## Phase B: root 後の本命作業

1. **pmsg 回収 (本来の目的)**: `su -c "cat /sys/fs/pstore/pmsg-ramoops-0" > usb_runs/pmsg.bin`
   → tools/ane_pmsg_scan.py で解析 → key-probe のトレース → コンボ自動化 Stage 1
2. ハーネス縮退: 捕獲器/回収ループを引退させ、[adb push + su cat] だけの軽量スクリプトに
3. persist.sys.usb.config の維持は su で簡単に (自己修復)
4. 副産物: dd による現物パーティション保全 (ramdisk/recovery_ramdisk) が自由にできる

## Phase 1 (予備ルート): renoshell 式の仕上げ移植

Magisk が通らなかった場合、または併走研究として:
- renoshell (j4nn, CVE-2019-2215 版) は「su98.c は security->sid / osid を正しく
  パッチしていなかった」ことを直し、cred 直接パッチ + KASLR バイパスで
  "nearly instant" に root を取る。現行エクスプロイトの 16 分 SELinux ポリシー段
  (call(A)/call(B)) の対極。
- 規律: 勝ちビルド 0x134c838 (md5 f42b6fad4f1aa3a612494ce592b359b2) は凍結のまま、
  別系統ビルドとして検証する。「構造変更で負ける」の実測を守る。

## 現況 (2026-10-03 18:0x)

- ane_pmsg_read32.sh: attempt 3 = no root (17:49)、attempt 4 の root 試行 17:55:28 開始、
  判定 18:20:28。勝てば pmsg 自動回収で終了、負ければ attempt 5 へ。
- 本計画はその判定後に Phase A を実行する。
