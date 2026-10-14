# stepmarks13/14/15 の記録読み表

実行順 (stepmarks15): 1 9 b c q r t s e a h f k l m n (16 枠ちょうど)

| count | マーク列末尾 | 死点 |
|---|---|---|
| 02 | 9 | 9 の直後 |
| 03 | b | b→c 間 = post-9 コンソール書込 |
| 04 | c | c→q 間 = テーブル/ルート構築中 |
| 05 | q | q→r 間 = TTBR/MAIR/TCR + TLB 中 |
| 06 | r | r→t 間 = **無効化シーケンス中** (stepmarks13 は 06 でここまで来ず) |
| 07 | t | t→s 間 = **SCTLR 書き換え (MMU有効化) 中** ← stepmarks13 の死点 (06 止まり) |
| 08 | s | s→e 間 = init 戻り + post-MMU プリント |
| 09 | e | e→a 間 (瞬間) |
| 0A | a | a→h 間 = from_boot_info 呼び出し |
| 0B | h | h→f 間 = report 内 ← **stepmarks14 の死点 (USB 読み)** |
| 0C | f | f→k 間 = allocator 構築部 |
| 0D | k | k→l 間 = fdt reserved walk 突入 ← stepmarks11 の死点 |
| 0E | l | l→m 間 = ノードスクラッチ構築 |
| 0F | m | m→n 間 = walk_structure 本体 |
| 10 | n | 記録満杯 = walk 復帰以降 (以降の死はログで読む) |

## 実測の推移

| ビルド | 内容 | count | 死点 |
|---|---|---|---|
| stepmarks12 | (旧) | 02 | 9 直後 (フレーキー) |
| stepmarks13 | mmu 内部分割 + report(USB 読み入り) | 06 | r→t (SCTLR 直前) |
| stepmarks14 | +ic iallu 前倒し +C=0 (D キャッシュ OFF) +t | 0B | **r→s 突破!!** → h→f (report の USB 読み = バスストール疑い) |
| stepmarks15 | +report から USB 読み除去 +FTLX 自前ログ +probe v5 | 予測 0C 以降 | f→k / k→l (fdt walk) が次の壁 |

## 計器の規約 (stepmarks15 時点)

- ログの読み先 = **FTLX ブロック (0x348D0000)**: [magic "FTLX"][size][cap] + 本文。
  毎ブート ane_step_begin がリセット、uart tee が 1 バイトずつ追記、tee_flush が
  書いた範囲を cache clean。pmsg ゾーンは Huawei 側ブートがヘッダを 0 にするため
  プローブは FTLX 優先 (magic 不一致時のみ pmsg 先頭窓へフォールバック)。
- ZH 行 = [FTLX magic][FTLX size][PMSG size] — 2 チャネルの生死が 1 枚で分かる。
- 早期ブートで **バス読み (USB レジスタ等) を絶対に行わない**: LK がクロックゲート
  したまま残す窓を読むとバスがストールして CPU ごと死ぬ (stepmarks14 で実測)。
