# ANE-LX2J ブートローダー解除 実行ハンドブック (RUNBOOK)

**対象**: Huawei P20 Lite **ANE-LX2J** (Kirin 659 / hi6250, Japan cust C635) を
**ソフトウェアのみ**でブートローダー解除する手順。分解・テストポイント・有償ツールなし。

この手順は 2026-10-02 に実機で完遂済み (記録:
[`ANE_LX2J_BOOTLOADER_UNLOCK_20261002.ja.md`](ANE_LX2J_BOOTLOADER_UNLOCK_20261002.ja.md)、
詳細台帳 [`journal/ANE_UNLOCK_NOTES.md`](journal/ANE_UNLOCK_NOTES.md))。
本書は同じことを**再実行する人/エージェント**のために、必要なファイル・順序・
検証点・失敗時の対処を 1 冊にまとめたものである。

---

## 0. 全体像 — 5 つの関門

```
[関門 A] EMUI 9.1 → 8.0 へのダウングレード     (Windows + HiSuite, 無料)
[関門 B] root 取得                             (CVE-2019-2215, 定数差分 0x134c838)
[関門 C] FBLOCK クリア                         (root + hisi-nve)
[関門 D] OEM ロック解除トグル                  (Android UI, Wi-Fi 待ち)
[関門 E] USRKEY へのコード書き込み             (root + nvme イメージ直接編集)
[最終]   fastboot oem unlock <16桁コード>
```

順序が重要: C (FBLOCK) を先にやらないと `check password failed` が先に出て
失敗原因が読めなくなる。D (トグル) は B〜C と並行して進めてよい。

**費用**: ファームウェア 4 本の取得に約 240 円 (マーケットプレイスのクレジット)。
解除自体は無料。

---

## 1. 事前準備

### 1.1 端末の固定 (最初にやる)

| 項目 | 確認コマンド | 期待値 |
|---|---|---|
| 機種 | `adb shell getprop ro.product.model` | `ANE-LX2J` |
| cust | `*#*#2846579#*#*` → Version Information | `CUST = C635` |
| ビルド | `adb shell getprop ro.build.display.id` | `9.1.0.132(C635)` (解除時実績) |
| カーネル | `adb shell cat /proc/version` | ダウングレード前 `4.9.148` / 後 `4.4.23` |

「P20 Lite」には LX1/LX2/LX2J/LX3 等の亜種があり、ファームが異なる。
**モデルと cust が一致しないパッケージは updater が必ず拒否する**。

### 1.2 このリポジトリ内で使うもの

| 用途 | パス |
|---|---|
| CVE-2019-2215 エクスプロイト (実績ビルド, aarch64) | `unlock/backup/cve-2019-2215_working_0x134c838` |
| 同ソース (定数 0x134c838 済み) | `unlock/cve-source/` |
| NV 読み書きツール hisi-nve (aarch64 / armv7) | `unlock/tools/hisi-nve` / `hisi-nve.armv7` |
| 実績 nvme イメージ (before/unlocked 記録) | `unlock/backup/nvme_*.bin` |
| ダウングレード用 8.0.0.110(C635) パッケージ | `firmware/azrom/` (13 GB)。**[Internet Archive ミラー](https://archive.org/details/p20lite-ane-lx2j-stock-firmware)から取得可** |
| HiSuite インストーラ (Windows 側) | [Internet Archive ミラー](https://archive.org/details/p20lite-ane-lx2j-hisuite-tools) (公式配布 URL が消えたときのバックアップ) |
| HiSuite 手順書 (Windows 側) | `docs/WINDOWS_CHECKLIST.txt` |
| ファームウェアパッケージ解析ツール | `tools/analyze/`, `tools/unlock/build_*.py` |

hisi-nve を失った場合は upstream から再ビルド可能:
`git clone https://github.com/R0rt1z2/hisi-nve && cd hisi-nve && sed -i 's|#include <memory.h>|#include <string.h>|' src/crypto/sha256.c && PATH=<NDK>: $PATH ndk-build NDK_PROJECT_PATH=. NDK_APPLICATION_MK=./Application.mk` → `libs/arm64-v8a/hisi-nve`

### 1.3 ホスト要件

- Linux + `adb` + `fastboot` (platform-tools)
- Windows (実機または USB パススルー VM)。**Wine では不可** (WineHQ bug #51666、実測)
- NDK 28 系 (バイナリを再ビルドする場合のみ)

---

## 2. 関門 A — EMUI 9.1 → 8.0 ダウングレード (HiSuite)

詳細手順: [`WINDOWS_CHECKLIST.txt`](WINDOWS_CHECKLIST.txt)。要点のみ。

1. Windows に HiSuite をインストール。
   端末の HiSuite インストーラ (CD ドライブとして見える) も退避手段になる。
2. 端末: `*#*#2846579#*#*` → Background Settings → USB Port Settings → **HiSuite Mode**。
   HDB を許可。
3. HiSuite → Update → **「switch to an older version」** が出るか確認。
   - 出たらそのまま実行 → EMUI 8 にロールバック (データ消える)。
   - 出ない場合は HiSuite Proxy (V3.3.0) でロールバック ROM を適用。
4. Linux 側で検証:

```bash
adb shell cat /proc/version            # 4.4.23 が見えたら成功
adb shell getprop ro.build.display.id  # 8.0.0.x(C635)
```

**dload (SD カード) では 9→8 を越えられない**。7 通りのパッケージ改造
(EOCD/frankenZIP 含む) で全て 5% で停止することを実測済み。時間を捨てないこと。
同一メジャー内 (8.0.0.151 → 8.0.0.110) なら dload で移動できる。

---

## 3. 関門 B — root 取得 (CVE-2019-2215)

### 3.1 エクスプロイトの配備

```bash
# 事実上の配置 (実行はしない。ダウングレード後に 4.4.23 で実行する)
adb push unlock/backup/cve-2019-2215_working_0x134c838 /data/local/tmp/cve-2019-2215
adb push unlock/tools/hisi-nve /data/local/tmp/hisi-nve
adb shell chmod 755 /data/local/tmp/cve-2019-2215 /data/local/tmp/hisi-nve
adb shell md5sum /data/local/tmp/cve-2019-2215   # ホスト側 md5sum と照合
```

### 3.2 実行と勝ち判定

```bash
printf 'id\ncat /proc/self/attr/current\ngetenforce\ndd if=/dev/block/bootdevice/by-name/nvme of=/dev/null bs=512 count=1 2>&1\nexit\n' \
  | timeout 240 adb shell /data/local/tmp/cve-2019-2215
```

**勝ち** = `uid=0(root)` が出て、SELinux ドメインが root に、`Could not load policy`
が**ちょうど 1 回**出て、nvme の `dd` が通る。
**負け** = `u:r:shell:s0` のまま `Permission denied`。負けは目で見て勝ちと区別が
つかないので、**root プロンプトが条件**。`grep -c 'uid=0(root)'` で判定する。

### 3.3 勝率を上げる規則 (実測)

- **1 回の起動につき 1 実験**。失敗ブートは LK の連続失敗カウンタを進め、
  2 連続で fastboot 窓なしで eRecovery 直行になる。
- リブート直後より**起動から 5-10 分経過してから**の方が勝つ (ヒープ状態)。
  `/proc/loadavg` が落ち着いていること。
- 再試行の前に `adb shell 'ps -A | grep cve'` でゾンビ (`Z`) を確認。あったらリブート。
- 競合 (race) は 25 分で見極める。勝ち出力は ~16 分以内に来る実績。30 分以上の
  ポーリングは値がない。負けていたらリブートして再試行 (勝率は試行回数が杠杆)。
- **ビルド規則**: 定数の即値変更のみ勝率を保つ。コード構造変更 (argv 解析追加等) は
  実測で全敗。再ビルドする場合は `unlock/cve-source/` を使い、最小差分を守ること。

### 3.4 SELinux 迂回の仕組み (定数差分)

エクスプロイトは 2 定数の**差だけ**を使う:

```
kaslr_offset   = read(task_struct + SCHED_CLASS_OFF) - FAIR_SCHED_CLASS
avc_cache_addr = kaslr_offset + AVC_CACHE
```

| カーネルビルド日 | ビルド | `avc_cache - fair_sched_class` |
|---|---|---|
| 2018-04-18 | 8.0.0.110(C635) | 0x132e838 |
| 2018-05-16 | L22J 8.0.0.202(C719) | 0x134a838 |
| 2018-06-11 | TL00 8.0.0.151(C01) | 0x134a838 |
| 2019-04-25 | LX2J 8.0.0.127(C719) | **0x134c838** ← 実機のカーネル (2019-03-01) と一致 |
| - | エクスプロイト同梱値 | 0x135c838 (間違い。shell ドメインから出られない) |

本リポジトリの実績ビルドとソースは **0x134c838 に固定済み**。他の亜種端末では
`tools/verify/audit_movz_movk.sh` 系の方法で候補差分をスイープする
(スキル `huawei-kirin-device-unlock` の references 参照)。

---

## 4. 関門 C — FBLOCK クリア

`tools/unlock/unlock_now.sh` が全体を自動実行する (バックアップ → 書き込み → 検証)。
手動でやる場合は root シェル内で:

```
/data/local/tmp/hisi-nve r FBLOCK     # 書く前に読む (7 コピーすべて 1 = locked)
/data/local/tmp/hisi-nve w FBLOCK 0
/data/local/tmp/hisi-nve r FBLOCK     # 7 コピーすべて 0 になったことを確認
sync
```

**書き込み前の nvme バックアップを必ず取る** (`dd if=/dev/block/bootdevice/by-name/nvme of=/sdcard/nvme_backup_<時刻>.bin`)。
このバックアップが「元に戻す」唯一の手段である。

`hisi-nve` は「成功」と報告しても**書けていないことがある** (次節)。書いた後は
必ず `r` で読み戻し、さらに `tools/unlock/diff_nvme.sh` でダンプ diff を取る。
**ツールの成功報告は証拠にならない。パーティションのバイト比較が証拠**。

FBLOCK=0 だけではブートローダーの状態は変わらない (必要条件、十分条件ではない)。
次の 2 関門が残る。

---

## 5. 関門 D — OEM ロック解除トグル (Android UI)

- 設定 → 開発者向けオプション → **OEM ロック解除** を ON。
- **Wi-Fi に接続してしばらく待たないとトグルがグレーアウトしている。**
  `sys.oem_unlock_allowed` の書き換えや oemlock HAL では開かない (実測で全部失敗)。
- この ROM には `persistent_data_block` サービスも oemlock HAL も無く、
  FRP 状態を書けるのはこのトグルだけ。

---

## 6. 関門 E — USRKEY へのコード書き込み (最重要の落とし穴)

**`hisi-nve w USRKEY <code>` はこの端末では無効** — `Hashing USRKEY...` と表示して
パーティションは工場出荷値のまま (実測)。有効な手順は nvme イメージを直接編集して
`dd` で書き戻すこと。`tools/unlock/write_usrkey_direct.sh` が全体を自動実行する。

```
エントリ配置 : 名前 (8 バイト) + 12 → 値 (104 バイト)
USRKEY コピー: 7 個
```

スクリプトの流れ:
1. root シェルで `nvme` をダンプ (`nvme_now.bin`)。
2. 全 USRKEY 値フィールドへ `SHA256(<16 桁コード>)` を書き込む。
   (コード例: `0123456789ABCDEF` — **自身で選んだ 16 桁**。このコードは
   eRecovery と再ロックで再度要求されるので控える)
3. 書き戻し (`dd if=... of=/dev/block/bootdevice/by-name/nvme bs=4096`) + `sync`。
4. 再ダンプして **7 コピーすべて**が `SHA256(コード)` 一致を確認 (スクリプト末尾で自動検証)。

検証は `tools/unlock/read_usrkey_hex.sh` / `tools/unlock/diag_usrkey.sh` も使える。

---

## 7. 最終 — `fastboot oem unlock`

```bash
adb reboot bootloader
fastboot oem lock-state info    # 現状確認
fastboot oem unlock 0123456789ABCDEF
```

応答の読み方 (上から順に評価される):

| 応答 | 意味 | 対処 |
|---|---|---|
| `(bootloader) check password failed!` | USRKEY がまだ正しくない | 関門 E に戻る。FBLOCK が 0 かも再確認 |
| `(bootloader) Necessary to unlock FRP! ...` | コード照合は通過。トグルが未完了 | 関門 D に戻る |
| `(bootloader) The device will reboot and do factory reset... OKAY` | **解除成功** | 初回起動は初期化される |

### 解除の検証 (fastboot に再入せずに済む方法)

解除直後の再起動後、通常 adb で:

```bash
adb shell getprop ro.boot.flash.locked        # 1 → 0
adb shell getprop ro.boot.verifiedbootstate   # GREEN → ORANGE
```

### 解除後すぐやること

1. **post-unlock nvme ダンプ**を保存する (`tools/unlock/backup_after_unlock.sh`)。
   今後の「元の状態」はここが基準 (工場出荷状態ではない)。
2. **16 桁コードを 2 箇所以上に控える**。NV パーティションとバックアップ以外に
   このコードを再発行する手段はない。
3. `fastboot oem lock-state info` が `FB LockState: LOCKED / USER LockState: UNLOCKED`
   を返すことを確認 (FB 側はこのまま。USER 側がフラッシュ可否を司る)。

---

## 8. 失敗時の対処 (実測に基づく)

| 症状 | 原因 | 対処 |
|---|---|---|
| HiSuite に繋がらない | Wine / HDB 未許可 / USB モード | Windows 実機、HiSuite Mode 再設定、ケーブル/ポート変更 |
| SD アップデートが 5% で止まる | メジャー境界 (9→8) は dload 不可 | HiSuite でロールバック (関門 A) |
| `Software install failed / Incompatibility` | パッケージと model/cust 不一致 | 同一 model+cust のパッケージを入手 |
| exploit が root にならない | 定数差分が違う / ヒープ汚染 | §3.3 の規則。`0x134c838` は本機のみ有効 |
| exploit 実行後に起動が固まる | 失敗ランの後遺症 (2 インターフェースの 12d1:107e) | 電源長押し ~10 秒 → 完全電源 OFF → 電源+Vol下で fastboot |
| eRecovery に入ったまま出ない | eRecovery は自己脱出しない | **完全電源 OFF** → 電源+Vol下 |
| `check password failed!` が消えない | USRKEY 書き込みが無効だった | 関門 E の dd 方式。7 コピー一致を確認 |
| OEM unlock トグルがグレーアウト | インターネット接続履歴がない | Wi-Fi 接続して待つ。他の道はない |

USB の状態指紋 (詰んだ場所の判定に使う):

| 状態 | lsusb | 判別 |
|---|---|---|
| Android 正常 | `12d1:107e` 6 interfaces + adb 応答 | 健康 |
| fastboot | `fastboot devices` が応答 (product 文字列は "Bluetooth Radio" という Huawei 特有のquirk) | 窓が開いている |
| 起動途中でハング | `12d1:107e` 2 interfaces、adb も fastboot も不応答 | 電源長押し 10 秒で回収 |

---

## 9. 実行順のチェックリスト (エージェント向け)

- [ ] 0. `adb shell getprop ro.product.model` が `ANE-LX2J` である
- [ ] 1. `ro.build.display.id` を記録 (ダウングレード前の状態)
- [ ] 2. Windows セッションで EMUI 8 へロールバック → `/proc/version` = 4.4.23 を確認
- [ ] 3. exploit + hisi-nve を push、md5 照合
- [ ] 4. exploit 実行 → `uid=0(root)` + nvme dd 成功
- [ ] 5. **nvme バックアップ** (書き込み前の最初の dd)
- [ ] 6. `hisi-nve w FBLOCK 0` → 読み戻し 7 コピー確認
- [ ] 7. OEM unlock トグル ON (Wi-Fi 待ち含む)
- [ ] 8. nvme ダンプ → USRKEY 7 箇所へ SHA256(コード) → 書き戻し → 再ダンプ照合
- [ ] 9. `fastboot oem unlock <コード>` → `OKAY`
- [ ] 10. `ro.boot.flash.locked=0` / `verifiedbootstate=ORANGE` を確認
- [ ] 11. post-unlock nvme ダンプ保存 + コードの控え

各ステップの詳細スクリプトは `tools/unlock/` にある (§4, §6 参照)。
**p20-root 作業ツリー前提のスクリプトがある** (`cd /home/placeless/dev/p20-root` するもの)。
その場合は p20-root に cd してから実行するか、パスを読み替える。
