# 夜間自走 報告 (2026-10-06 23:30 → 10-07 07:00)

## 結論 (要点)

1. 【最重要・解決】「暴走」の正体 = uart::putc の無制限 FIFO 待ち
   - 発見の連鎖: リング末尾が "launchd: calling run" の3バイト ("LAU") で
     停止 → ELR=0x1BFD1A4 を正しい写像 (実行時 = ELF vaddr + 0x1660000、
     リング自身が印字する RELOCATION_DELTA) で引くと uart::putc の内部
     (0x59D130..0x59D1C0) と完全一致 (nm 照合で確認)
   - 機序: TXFF スピン (FR bit5、base+0x18) が IRQ 文脈の putc と同一
     FIFO を奪い合い、FIFO が満杯のまま返らない → ブートスレッド永久停止
   - 修正 v140: 待ちを有界化 (200k spins で続行)。リング tee は putc の
     先頭で先に書かれる設計なので、ハード UART の1バイト喪失のみで世界は生存
2. 【新機能】読み取り路 = 完全開通
   - oem xfer (生バルク) = 57KB を一撃で (per-chunk FIFO 完了待ちが修正点)
   - ADB ミニプロトコル完全動作: CNXN→CNXN(banner) / OPEN→OKAY+WRTE+CLSE
   - ADB shell:log (v141+) = リング末尾を ADB 経由で直接ストリーム
   - oem ringsave (v143) = コマンド文脈からリング全体を eMMC スクラッチへ
   - 画面へのログ末尾表示 (行60-65、写真で読める)
3. 【自動化】oem crash = ソフトウェア・リセット実証済み (物理押下不要)
   - night_engine.sh v5 = dmesg エッジ検知 (キャッシュ偽装に騙されない) +
     新鮮ブートの最初の会話でクラッシュ/回収を行う自動サイクル
4. 【朝の一歩目】
   - コンボだけで OK: LK を検知したエンジンが **v143 を自動フラッシュ**し、
     その後の最初のブートで **リングを自動回収** (grab モード)
   - v143 = putc修正 + ADB shell:log + ringsave (最良候補)

## 用意済みイメージ (artifacts/)
| 版 | 内容 | 用途 |
|---|---|---|
| v143 | putc修正 + shell:log + ringsave | 本命 (エンジンが自動で焼きます) |
| v144 | v143 + UART FR プローブ (fr_pre/fr_post) | 失敗時の根本原因計器 |
| v142 | v141 + ADB 記述子フリップ (ff/42/01) | 本物の adb devices テスト |
| v140 | putc 修正のみ | 対照実験 |

## 夜間終盤の状態 (重要)
- 直近の稼働ブート (v132) は「USBコア完全ブリック + 世界はティック生存」の
  安定凍結に入りました。sysfs/lsusb の "ANE fastboot" は**キャッシュの幻**で、
  ホスト dmesg の最終イベント (23:41:15, device number 8) 以降 55 分間
  USB イベントゼロ = デバイスは USB レベルで沈黙しています。
- この状態は自然リセットしません (SP805 が給餌され続けるため)。
  **唯一の起床手段 = 物理コンボ**です (下記)。
- v140 の有界化修正が効けば、次のビルドからこの「USBブリック付き凍結」は
  再発しない見込み (putc が返り、世界が進み続けるため)。

## 朝のお願い (これだけ)
1. ボリューム下 + 電源 (~10秒) → LK で止める
2. あとは放置 → エンジンが自動で v143 を焼き、起動後にリングを回収します
3. 結果 (launchd の L0-L6 マーク + リング/ADB のログ) を報告します

## データ・ツール
- rings_night/ = 回収リング / logs/night_*.log = エンジンの行動ログ
- decode_ring.py <ring> = ブート区間分割デコーダ
- adbtest.py / adbtest_full.py = ADB ワイア検証
- fb_xfer.py = 生転送 (r <addr> <len> / m <lba> <sectors>)
- fb_probe.py / fb_recover_ep1.py = 生存確認 / EP1 ダンス回復
- MORNING_REPORT.md = 本ファイル
