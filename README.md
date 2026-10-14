# p20lite_ANE_LX2J_tools

**Huawei P20 Lite (ANE-LX2J, Kirin 659 / hi6250, Japan cust C635)** の
ブートローダー解除 (BLU) と、**カスタム ROM・メインライン Linux 系カーネル・
自作 OS 等の代替 OS 移植**のためのツールキット。解除手順と起動契約は OS 非依存に
整理してあり、記載の内容はすべて実機での実験により得た測定に基づく。
端末は**ソフトウェアのみ** (分解なし・テストポイントなし・有償ツールなし) で解除した。

## このリポジトリでできること

1. **ブートローダー解除 (BLU)** — 前提条件が揃った端末に対し、同手順を再実行できる。
   → [`docs/UNLOCK_RUNBOOK.ja.md`](docs/UNLOCK_RUNBOOK.ja.md) から始めること。
2. **解除済み端末への実験カーネルの投入と結果の読み取り** —
   fastboot 窓の捕捉、flash、画面プローブによる 1 写真読み取りまでの自動サイクル。
3. **ストック復帰** — `firmware/kernel_stock.bin` を flash すれば常に Android に戻る。

## Start here (用途別)

| 目的 | 読むもの |
|---|---|
| **BLU を実行する** | [`docs/UNLOCK_RUNBOOK.ja.md`](docs/UNLOCK_RUNBOOK.ja.md) (手順・検証・失敗時対処の全部) |
| BLU の背景と実録 | [`docs/ANE_LX2J_BOOTLOADER_UNLOCK_20261002.ja.md`](docs/ANE_LX2J_BOOTLOADER_UNLOCK_20261002.ja.md) |
| 実験カーネルを焼く | [`docs/ANE_BOOT_CONTRACT.md`](docs/ANE_BOOT_CONTRACT.md) (ブート契約) + 下記「サイクル」 |
| 代替 OS を移植する | [`docs/ANE_LX2J_PORT.ja.md`](docs/ANE_LX2J_PORT.ja.md) (移植記録: ブート契約の適用例) |
| 過去の実験記録を引く | [`docs/journal/INDEX.md`](docs/journal/INDEX.md) (台帳の索引) |

## 解除 (BLU) の骨子

5 つの関門を順に通過する。詳細は RUNBOOK を参照:

1. **ダウングレード** EMUI 9.1 → 8.0 (Windows + HiSuite。dload では越えられない — 実測)。
   インストーラは [Internet Archive にミラー済み](https://archive.org/details/p20lite-ane-lx2j-hisuite-tools)。
2. **root** CVE-2019-2215 ( SELinux 迂回には定数差分 `avc_cache - fair_sched_class = 0x134c838` が要る。実績ビルドを `unlock/backup/` に同梱)
3. **FBLOCK クリア** (`hisi-nve w FBLOCK 0`、`unlock/tools/hisi-nve` 同梱)
4. **OEM unlock トグル** (Wi-Fi 接続で待つと押せるようになる)
5. **USRKEY 書き込み** (`hisi-nve w USRKEY` は無効 → nvme イメージ直接編集。`tools/unlock/write_usrkey_direct.sh`)
6. `fastboot oem unlock <16桁コード>`

主要な依存物はすべてリポジトリ内に揃えてある
(exploit バイナリ・hisi-nve バイナリ・cve ソース・nvme 記録イメージ)。

## Directory layout

```
docs/       契約書・手順書 (BLU は UNLOCK_RUNBOOK.ja.md、起動は ANE_BOOT_CONTRACT.md)
  journal/      実験台帳 (夜間記録・時系列ログ)。INDEX.md が索引
tools/      端末を駆動・分析するスクリプト (役割別のサブディレクトリ)
  flows/      実行するサイクル: ane_logloop.sh, ane_autopilot.sh, ane_window_flash.sh,
              V21_LOOP.sh, ane_catcher.sh, flash_cycle.sh ...
  probes/     画面描画 .S プローブとアセンブラ (ane_log_probe が現行の読み取り器)
  builders/   boot イメージ構築: mkane_stock_embed.py, mkane_bootimg.py
  diag/       端末状態の読み取り (USB 監視, fastboot 生操作, oem log 収集)
  analyze/    ホスト側分析 (DT, パッケージ, ダンプデコード)
  unlock/     BLU 時代のスクリプト (段階別に整理済み)
  verify/     ホスト検証器 + QEMU 証明 (焼く前に実行する)
  usbtool/    PCUI/AT USB プローブ (usbtool-*.py)
  apktool/    apktool.jar (利便性のローカルコピー)
  archive_experiments/   歴代の版数付き実験スクリプト (記録保持用、実行はしない)
artifacts/  fastboot flash kernel で焼けるイメージ (gitignore 適用でローカルのみ)
  fullerene-ane-log-probe-stock.img   現行の画面読み取り器 (git 追跡)
firmware/   ストックファームウェアと基準データ
  kernel_stock.bin      25 MB 抽出済みストックカーネル (復帰用)
  ane_dtb/              端末固有の DTB + フラット化プロパティ
  azrom/                ストックファームウェアアーカイブ (13 GB, gitignore)
  ane_pstore_readback/  pstore 読み出しの記録
logs/       自動化ログと実測の証跡
  usb_runs/     USB 再列挙ログ
  forensics/    snap_* 端末状態スナップショット
  misc/         catch_lk / ダンプ / 夜間ログ
  night/        夜間ループのリングログ
unlock/     ブートローダー解除の完全記録 (ソフトのみ解除):
  backup/         ANE-LX2J_20261002 スナップショット: nvme before/after/installed,
                  frp_original, misc, oeminfo, 実績 exploit バイナリ, MD5SUMS
  tools/          hisi-nve バイナリ (aarch64/armv7)
  cve-source/     CVE-2019-2215 ソース (0x134c838 定数済み)
  working-notes/  勝利設定のメモ
  device-dumps/   nvme/USRKEY, oeminfo gamma, fastboot_LK.bin, dts_stock.bin
  lk/ lk_asm/     LK 逆アセンブル (lk_asm はローカルのみ)
  pz_poc.c        由来保持のための PoC 原本
refs/       参照ソース (hisifb ディスプレイスタック, HwProjectMenu.apk)
```

## 実験サイクルの動かし方

1. fastboot 窓を確保する: Android から `adb reboot bootloader` (コンボ不要)、
   またはコールドオフ失敗ブート後 ~2.5-7 分の窓
   (LK 失敗カウンタの挙動は `docs/ANE_BOOT_CONTRACT.md` §12)。
2. 実験を焼く: `fastboot -s <serial> flash kernel artifacts/<img>`。
3. カーネルはステップマークを書いてパークする (早期パークベクタが
   eRecovery 落ちを防ぐ)。
4. パーク後の窓で**ログプローブ** (`artifacts/fullerene-ane-log-probe-stock.img`)
   を焼いて再起動。プローブはマーク記録 + カーネルログを画面に描画し、
   スマホ写真 1 枚で読める。
5. ストック復帰: `fastboot flash kernel firmware/kernel_stock.bin`。
   次回ブートの失敗カウンタをリセットし Android に戻る。

`tools/flows/ane_logloop.sh` がこの全体を自動で繋ぐ。
注意: 多くのフローは実機シリアル `SCV7N18927000473` を `-s` で固定している前提。
自分の端末のシリアルに読み替えること。また一部のスクリプトは
`~/dev/p20-root` 作業ツリー前提 (`cd` する) のまま残している — p20-root は
巨大バイナリの現役ワークスペースであり、本リポジトリの gitignore が意図的に
外しているファイル (ファームウェアアーカイブ等) の唯一のローカルコピーがある。

## 画面コンソール (なぜ写真で読めるのか)

- ログプローブは 8x8 グリフ (3x スケール) を 14 行 x 45 列に描画する:
  カーネルログ末尾 540 文字 + 90 文字のマーク記録。
- カーネルは UART の全バイトを RAM tee にミラーし、MMU 起立後に
  ramoops pmsg ゾーンへフラッシュ、プローブはそこから読む。
- 表示予算は LK の解除告知領域の前 ~500 スキャンライン (12-14 行)。
- フォント注記: 同梱フォント (public-domain VGA 8x8) は行を LSB-first で
  格納する。レンダラが MSB-first に走査するため、生成時にビット反転が要る
  (逆にすると全グリフが鏡像になる — 実測で踏んだ落とし穴)。

## 主な発見 (詳細は docs/ANE_BOOT_CONTRACT.md)

- 起動はステップマークで追跡できる。mark `a` (MMU 起立 + 初回コンソール書込み) は
  MMIO 属性テーブルの per-platform 化で突破済み。
- MMU 到達は**確率的**に失敗することがある: 同一ビルドが mark 9 で止まったり
  mark k まで走ったりする。結論の前に 2-3 回再実行すること。
- LK は失敗連続カウンタを持つ: 最初のコールド失敗で fastboot 窓、直後の 2 度目で
  eRecovery 直行。ストック起動の成功でカウンタはリセットされる。
- `fastboot boot` は解除後も拒否される (実測)。RAM ブート不可 = 全カーネルテストは
  flash → 起動 → (停止) → ボタン復帰のサイクルになる。
- 読み取りはスマホの接写写真 1 枚。webcam はグリフ間隔を解像できない
  (解像度を上げても不可 — 実測)。

## Firmware (研究検証用リファレンス)

`firmware/azrom/` に ANE ファミリーのストックファームウェア
(Android 8.0 / EMUI 8.0: 本機の KDDI ビルド、C719 オープン市場ビルド、ANE-TL00 CN)。
`firmware/kernel_stock.bin` は抽出・sha256 検証済みのストックカーネル。

これらの巨大バイナリは git リモートに置けないため、**Internet Archive に
「検証に使ったファーム群」として保存してある**。目的は WAREZ 的な配布ではなく、
本研究の測定値を第三者が**同じファームウェアバイト列に対して独立に検証できる
ようにする**こと、および公開ミラーが消えた場合でも研究が再現可能であることの担保である:

| アイテム | 内容 |
|---|---|
| [p20lite-ane-lx2j-stock-firmware](https://archive.org/details/p20lite-ane-lx2j-stock-firmware) | 検証に使用した改変なしストックファームウェア 5 本 (8.0.0.110 C635 / 8.0.0.127 C719 kddi・オープン市場 / 8.0.0.202 C719 / 8.0.0.151 C01) + 抽出済み `kernel_stock.bin` |

研究での使いみち:
- **8.0.0.127(C719)** — カーネルシンボル配置の復元元。SELinux 迂回定数
  `avc_cache - fair_sched_class = 0x134c838` の導出に使用
- **8.0.0.110(C635)** — メジャー内ダウングレードターゲット (カーネル 4.4.23)。
  公開研究 CVE-2019-2215 が適用されるビルドで、RUNBOOK 関門 A/B の根拠
- 各パッケージ — boot image ヘッダ、recovery の検査、更新検証フローを
  分析した一次資料 (`docs/ANE_BOOT_CONTRACT.md` §1-4)

改変イメージ・unlock コード・有償ツール類は含まない。解除手法自体は
公開研究 (CVE-2019-2215, Project Zero) に依拠し、その再現手順を本
リポジトリの文書が記録している。

全取得:
```
ia download p20lite-ane-lx2j-stock-firmware
```
個別取得はアイテムページの Download Options から。
(`ia` CLI は `pip install internetarchive` または `uv tool install internetarchive`)

## HiSuite (ダウングレード検証に使用した公式インストーラ)

RUNBOOK 関門 A のダウングレードは、ベンダー自身の PC ツール HiSuite の
バージョン切り替え機能によってのみ成立する (dload/SD ではメジャー境界を
越えられないことを 7 種のパッケージ構築で検証済み — 実測記録は
`docs/ANE_BOOT_CONTRACT.md`)。検証に使用した公式ビルドを Internet Archive に
保存してある (ベンダーのダウンロード URL は永続が保証されないため):

| アイテム | 内容 |
|---|---|
| [p20lite-ane-lx2j-hisuite-tools](https://archive.org/details/p20lite-ane-lx2j-hisuite-tools) | 検証に使用した HiSuite 公式インストーラ (現行版 W00018218 / 10.0.0.510 W00003542) + HiSuite Proxy V3.3.0 (サードパーティのオープンソースヘルパー、フォールバック評価用) |

## Safety

- flash 対象は `kernel` パーティションに限る。ストックカーネルは常に
  `firmware/kernel_stock.bin` にあり、復帰できる。
- ツールは recovery パーティション・configfs・ユーザーデータに触れない。
- BLU の nvme 操作はスクリプトが書き込み前に必ずバックアップを取る。
  バックアップは「元に戻す」唯一の手段であり、削除しないこと。

## Verification expectations

新しいものを焼く前にホスト側チェックを実行する:

```
python3 tools/verify/verify_ane_early_vectors.py     # 早期パークベクタ
python3 tools/verify/verify_base_loads.py            # ベースロード監査
bash    tools/flows/ane_logloop.sh --help 2>/dev/null || true
```

プローブアセンブラの QEMU 証明はその横にある
(`tools/probes/ane_log_probe.sh` は QEMU 描画チェックが通らないと
イメージをパッケージしない)。
