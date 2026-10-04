# ANE-LX2J v21 = eRecovery 殺し（クリーン再起動方式）— 2026-10-04 夜間

## 何が問題だったか
- 従来の自動帰還方式 = 「ラッパーが死ぬ → SP805 watchdog (1s) が咬む → 再起動」
- この死は LK に **AP_S_AWDT (0x23) = 予期しない再起動** として記録され、失敗カウントを毎回 +1
- 連続 5 回前後で LK は eRecovery へ直行（fastboot 窓すら開かない）。回復は完全電源 OFF（コンボ）のみ
- つまり「watchdog で戻る」方式は、戻るたびに eRecovery へ近づく構造的欠陥だった

## v21 の設計（ソース実装に基づく）
- 再起動理由は文字列 → `hisi_pm_system_reset` → `set_reboot_reason` → **PMU_RESET_REG**（常時給電域）に格納
  （根拠: rdr_hisi_ap_adapter.c:1803、hisi_poweroff.c:71、reboot_reason_map[] rdr_common.c:179）
- クリーン再起動の証明印 **RDR_REBOOT_DONE = 0xff1230ff** はカーネルの reboot notifier が共有 RAM へ書く
  （根拠: rdr_field_core.c:132、rdr_inner.h:41）
- v21 = ラッパーの作業完了直後に **RESTART2 クリーン再起動**を自分で発行:
  `syscall(SYS_reboot, 0xfee1dead, 672274793, 0xa1b2c3d4, "bootloader")`
  = `adb reboot bootloader` と同一経路 → LK は例外としてカウントせず、BCB の bootonce 命令に従い fastboot を開く
- 保険: RESTART2 失敗 → plain RESTART → 8 秒 petter 付き旧 watchdog 経路（デグレなし）

## 実測サイクル（自動、ユーザー操作なし）
- サイクル1: 04:06:56 flash → 捕捉 04:07:16 → 回収 04:08:05（69 秒）
- サイクル2: 04:08:51 flash → 捕捉 04:09:10 → 回収 04:09:58（67 秒）
- サイクル3: 04:10:32 flash → 捕捉 → 回収 04:11:40（68 秒）
- 全サイクルで report 末尾 = 「M-rb: clean restart2 'bootloader'」で終了（= 再起動成立の署名）
- eRecovery ゼロ・watchdog 死ゼロ。旧方式は 3〜5 連続で eRecovery に落ちていたので、サイクル4-5 の完走で「殺し」の正式な証明完了
- サイクル4: 04:12:36 flash → 04:12:56 捕捉 → 04:13:40 回収（64 秒）
- サイクル5: 04:13:55 flash → 04:14:14 捕捉 → 04:15:03 回収（68 秒）
- **5/5 完走 = eRecovery ゼロ = 「eRecovery 殺し」正式成立**（旧方式は 3〜5 連続で eRecovery に落ちていた）
- 全 5 サイクルでユーザー操作ゼロ（コンボ不要）。今後は V21_LOOP.sh N で任意回数を無人実行可能

## M1 死の決着（2026-10-04 04:3x）
- 真犯人 = SD カード。mmcqd が card_busy_detect でスピン → FIQ ウォッチドッグ 88 秒で全コア停止（pstore の死コンソールで確定）
- v25 = ホットログを /data (eMMC) へ、SD は一括コピーのみ → 25 秒窓フル生存（petter 欠落ゼロ）・init.hw 健在（kmsg_t24s）・FIQ 痕跡消滅・trace 30,429 行 T end st=0 で根治確認
- 残: v26 = トレーサのシグナル転送、/init.hw ENOENT の謎

## v22 ドラフト（次の実験、コンパイル確認済み）
- tools/ane_initwrap22.c = v21 + ptrace による syscall トレーサ（fallback 経路）
- init.hw を PTRACE_TRACEME で起動し、全 syscall を /mnts/ane/trace.txt へ 1 行ずつ fsync
- 死の直前の syscall が最後の行に残る = パニック不可視問題への最初の光
- 注意: 現状はフォールバック経路にのみ存在するため、fast パス（M-rb 成功）では到達しない。
  実行時は「trace.txt が無ければ trace モード（M-rb をスキップ）、あれば通常モード」のガードを付けるのが正しい（v23 として実装）

## eRecovery 殺し・第2弾: FullereneOS 用 早期パークベクタ (2026-10-04 05:2x)
- 問題: Fullerene 本体の死 (mark 6→7 のコンソール窓) は独自ベクタ設置前 = LK 残置ベクタ経由 → rescue 系 (eRecovery) に着地しやすい。
  ユーザー指摘「FullereneOS でいくと ERECOVERY 落ちする」
- 対策 (実装済み・entry.rs): `aarch64_bootstrap` 冒頭 (最初のデバイスアクセス前) に park-only ベクタを設置
  - 16 スロット全部がハンドラへ (`.text.ane_early_vectors`, 2KB 整列)
  - ハンドラ = DAIF マスク → マークブロックに 'F' (0x46) 追記 → wfe パーク
    (リセットしない = §12 の実測則「ハング → fastboot」に乗せる)
  - VBAR_EL1 (+ EL2 ハンドオフ時は VBAR_EL2) を register-only で設定 (リロケーション前でも安全)
- 検証: QEMU 証明 PASS = スクラッチが「123456F」(count=7) — フォルトをハンドラが捕まえたことまで機械証明
  - `ane_marks_qemu_proof.sh` 更新 (asm の movz/movk とアサートもリターゲット)
  - `tools/verify_ane_early_vectors.py` = Image バイト走査 (ELF はシンボル剥がれのため)。テーブル 0x12000 / ハンドラ 0x12800 = PASS
- 成果物: artifacts/fullerene-ane-stepmarks3-stock.img (11,620,352 B, byte-exact)
- 読み出し: artifacts/fullerene-ane-paint-probe-stock.img (新設。stock 埋め込み形 = LK 受理が確実。小型形は受理が不安定)
- 読み出し v2: artifacts/fullerene-ane-rch-probe2-stock.img = 全 10 チャネル (VG0/VG1/G0/G1/D0-D3/WCH0/WCH1) の
  DATA_ADDR0 を読んで妥当なバッファを色分け塗り。ramoops 窓保護つき。検証 = verify_base_loads 10 値 + QEMU PASS
- 実機テスト結果 (05:36-05:50): stepmarks3 = fastboot 窓 → 復元 ✓ (キル成立)。paint-probe (2 連続目の失敗) = 窓なし直接 eRecovery
- 運用則: **1 電源サイクル = 実験ブート 1 回**。失敗の次の実験はコンボ (完全電源 OFF) から

## 観測: RCH プローブ run-2 = fastboot 窓なしで直接 eRecovery (05:15:36)
- run-1 (同一 hang イメージ) は ~7.2 分で fastboot 窓 → 捕捉復元。run-2 は起動+154 秒で 12d1:107e 1iface に着地
  (窓は kern.log に出現せず、12 分以上静止)。差 = 前回の完全電源 OFF 以降の連続失敗数 (1 回目 → fastboot / 2 回目 → eRecovery)
- 行き先は「終わり方」だけでなく LK の揮発カウンタにも依存する (§12 追記済み)。コンボ (完全電源 OFF) でカウンタを冷やす

## 次の課題（朝以降）
1. stepmarks3 (kill版) 実機テスト: カウンタ冷却 → flash → 死の行き先が fastboot 窓に変わるか (eRecovery 消滅の確認)
2. paint-probe-stock でマーク読出: 「白 + 7 帯 (123456F)」なら早期ベクタ動作の実機確定
3. Fullerene の死点特定 (paint の色帯) → コンソール・クロック仮説の最終判定
4. 既存の保留: Bramble (a)耐久ログ化設計 / (b)記録数監査、Teclast T5 (.pac 抽出)

## ファイル
- ラッパー: tools/ane_initwrap21.c（151行+、M-rb ブロック追加）
- パッケージ: /tmp/rd_patch/testV21.img（id=c1c3726957945dab）
- 守衛: ane_awake.sh（シリアル grep 修正済み）、回収: sd_auto/cycle_v17_1004_040749/ ほか
- 核となるマーカー: report.txt の `M-rb: clean restart2 'bootloader'` の後に何も続かなければ再起動成立

## 04日 朝: 読み出し系の完成とブート現在地 (08:30)
- スキャン元 = 0x31000000 に確定: テキストプローブの fallback(0x31000000) 描画が画面に出た (ユーザー写真で完全読取)。
  fallback は最初期プローブから「kernel reserved graphic region」として固定されていた正解ターゲットだった
- テキストコンソール完成: 8x8 フォント (hex + V/R/C + 空白) を 4x スケールで 12 行 x 33 字のビットマップに描画し
  全候補 + 0x31000000 に blit。QEMU 証明済み (文字列一致・グリフ画素・blit 着弾)
  artifacts/fullerene-ane-text-fix-stock.img = 読み出し用 (byte-exact)
- レジスタベースの誤りを発見: 06:13-08:19 の各プローブは DSS ベースを誤値 (0xE8643000 系) で読んでいた。
  正 = rch_probe2 の vendor tree 由来値: VG0=0xE8620000 VG1=0xE8628000 G0=0xE8638000 G1=0xE8640000
  D0..D3=0xE8650000/0xE8651000/0xE8652000/0xE8653000 WCH0=0xE865A000 WCH1=0xE865C000 (+0x60 = DATA_ADDR0)
  この間の消去法の結論は全て無効。以後のプローブは必ずこの値で
- 実機記録の読取 (ユーザー写真): count=9, マーク "123456789" (+9 バイト目に前回残骸)。
  = ブートはステップ 9 まで到達 (1-5 ブートストラップ / 6-7 コンソール+クロックゲート+ベクタ / 8 UFS 契約 / 9 同戻り)
- 死点 = main.rs:843-857 間 = mmu::init() の中でハング。'F' (フォルトマーク) なし = フォルトでなく黙って停止
  (早期ベクタのパークハンドラは未発火。パーク経路は eRecovery 殺し用として別に機能)
- eRecovery 殺し実績: 今夜 fastboot 窓 / eRecovery 着地を 10 回以上観測、自動捕獲でストック復元は毎回成功
- カメラ: eMeet C960 は MJPEG 1920x1080 対応 (今夜までは 640x480 YUYV)。以後は高解像度で読取
- 次: mmu::init() (identity map + caches) のハング究明 (マップ範囲・属性・DSB/ISB 待ちを一次ソースで確認)

## 04日 08:40: mmu::init 死の真因と修正 (実機検証待ち)
- 真因 = `mmu::is_mmio()` のレンジ表が Bramble(Qualcomm) のまま。ANE では
  ① 本物の MMIO (UART 0xfdf02000 / DSS 0xE86xxxxx / CRG 0xfff35000) が Normal(キャッシュ可)扱い
  ② RAM の一部 (0x00800000-0x009FFFFF 等) が Device 扱い、の二重誤り
- 死の構図: MMU 有効化 → main.rs:855 の最初の UART puts がキャッシュ経由 → 停止 (マーク 9→a 間と一致)
- 修正 = per-platform `MMIO_RANGES`: ANE = [(0xE0000000, 0xFFFFFFFF)] (根拠 = 端末 DT: RAM 0x400000-0xE0000000、
  周辺は全部 0xE0000000 以上。0xE0000000 未満のノードは reserved-memory と dsp@49000000 のみ)。
  Bramble/QEMU = 従来リスト維持 (挙動不変)。mmu.rs は cfg で選択
- 検証: host テスト `tests/ane_mmio_ranges.rs` 2件 PASS (既存 29+7 維持)。ANE/Bramble 両 aarch64 ビルド成功
- 成果物: artifacts/fullerene-ane-mmu-fix-stock.img (byte-exact)
- 次: 実機 = [コンボ]→[mmu-fix 焼き]→[死後に reader(text-fix) 自動差替]→[1080p 撮影]→[ストック復帰]
  (ane_mmufix_test.sh = この連鎖。読み出しは record の count/marks が真実)

## 04日 09:20: a→d 区間の特定と stepmarks5
- 09:14 写真読取: stepmarks4 も count=10 "123456789a" 止まり = d/e/f/g 未書込
  ⇒ 真の壁 = a と d の間 = **アロケータ節 (main.rs:859-888)**。タイマー説は外れ
- 容疑: ①PhysicalFrameAllocator ≈25KB をスタック構築 (ブートスタック = 64KB のみ!!)
  ②fdt の reserved-memory 探索 / ③memory_map 読み
- stepmarks5 の対策: ブートスタック 64→256KB + from_boot_info 内に h/i/j 細分マーク
  (h=入口, i=reserved探索後, j=構築完了)。マーク容量 16 の都合で b/c を一時退避
- 記録の読み方: 9a→9aH→9aHi→9aHij の伸びで死亡点を 1 マーク単位で確定
- 成果物: artifacts/fullerene-ane-stepmarks5-stock.img (11,583,488 B, byte-exact)

## 04日 09:30: stepmarks5 の結果 (09:14 写真) と stepmarks6
- 5 の記録 = count 0B, "123456789a h(0x68)" = from_boot_info 入口まで書けた。i は無し
- 逆アセンブル証拠: main() のフレーム = 32KB+ (sp+0x7AA8 参照)、~27KB のアロケータ構造体は
  実際にスタック上 (NRVO スロット)。64KB(stepmarks4: a→d 死) → 256KB(5: h→i 死) で死亡点が
  深化 = スタック制約と整合
- ホスト実証: 実 ANE ツリーでの find_reserved_memory_regions は 0.04s で完走 (tests/ane_fdt_walk.rs、
  メモリマップ 3 領域一致も確認) = DT 探索そのものは白
- stepmarks6: ブートスタック 1MB + 内部細分マーク h,q,r,s,t,i (16 バイト容量ちょうど)
  d/e/f/g/j/b/c は一時退避。1MB 化で adr が ±1MB 超過 → entry.rs の 2 箇所を adrp+:lo12: 化
- 成果物: artifacts/fullerene-ane-stepmarks6-stock.img (11,438,080 B, byte-exact)

## 04日 09:50: ログダンプ自律ループ (ユーザー指示)
- 方針: 写真フレームでなく **ログの自律回収** + **eRecovery を挟まない**
- 実装 1: uart tee — `uart::putc` → `blackbox::text_byte` (小文字は大文字化して)
  → ramoops pmsg ゾーン (0x348E0000、12B ヘッダ + 本文) に全量ミラー。既存 append は
  容量・prz ヘッダ・キャッシュ清浄の管理済み (byte 毎に header line + 1B のみ clean)
- 実装 2: `ane_log_probe.S/.sh` — ログ末尾 330 字 (10 行 x 33) + マーク記録 2 行を描画。
  QEMU 全 PASS (文字列一致 + グリフ + blit + pmsg シード)。artifacts/fullerene-ane-log-probe-stock.img
- 実装 3: `ane_logloop.sh` — 実験焼→窓→(ストックでストリーク・リセット)→adb で再入→
  ログプローブ焼→1080p バースト→窓→ストック→SD プル。コンボ・eRecovery なしで周回
- tee 入りカーネル: artifacts/fullerene-ane-stepmarks7-stock.img (byte-exact)
- 未確定: pstore sysfs 可視性 (旧測定=空。tee で有効な prz を書くので再測定価値あり。wrapper の
  sysfs ダンプ経路は次段)。webcam の文字可読性 (ログプローブ描画で再評価)

## 04日 10:05-10:15: ログ表示の完成と回帰の特定
- reader v3 (ane_log_probe.S): ログ末尾 540 字 + マーク記録 90 字を 14 行 x 45 字に描画。
- フォント: font8x8 (public domain, Marcel Sondaar/IBM) 64 グリフ (0x20-0x5F) を埋込、ビット反転で正立化。
- 実機 10:12 写真で全行読取成功。ミラーはフォントのビット順 (LSB左 vs 私の MSB左走査) が真因。
- 判明: stepmarks7 は count=09 = また 9->a (mmu::init 直後の初 UART 書込) で死亡。
  ログは uart init 以降すべて出ており、tee (pstore 直書き) が 9->a の回帰原因と特定。
  (stepmarks6 = count 0B a,h で mmu は通過しており、差分は tee のみ)
- 対策 = stepmarks8: uart tee を RAM バッファ (TEE_RAM 4KB, 平 store のみ) へ。
  mmu 通過後 (allocator::from_boot_info の h 直後) に tee_flush() で PMSG へ一括転送。
- blit 有効長 ~500px (0x210000/0x10E0) = 12.5 行が実画面の限界。14 行 x 45 (3x scale) が安全域。
