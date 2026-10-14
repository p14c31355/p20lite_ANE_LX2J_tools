# 夜間自走 v331 (2026-10-13 22:56 開始)

## 投入版
- v331 = v329b (会話カウント式静穏待ち) + v330 (モバイルホーム) + ブートスレッド心拍 &
  pump 側凍結検知 (boot_recovery_check, 7200 beats ≈ 10分で loader reset)
- commit: 3f8e1f2f (recovery), 775efc9b (convwait), abbec92c (mobile home)

## 復帰機構 (ユーザー要求の「安全な復帰機構」)
1. 待機ループが毎パス BOOT_HEARTBEAT を加算
2. タイマ pump が boot_recovery_check(beats) を毎ビート実行
3. 心拍停止を検知 → WD: BOOT FROZEN → 7200 beats 後 schedule_reset_at
   = v63 チェーンで loader 再起動 → エンジンが v331 を再 flash
   = 物理操作不要の自動復帰レーン

## 自走ループ (night_engine_v24.sh, 800 cycles)
LK 検知 → v331 flash → reboot → リング収集 → ANE fastboot 検知 →
reboot-bootloader (no combo) → LK ... 各サイクル約3-4分

## 朝の確認項目
1. logs/night_*.log のサイクル数とエラー
2. rings_night/v331* の STG HOME-OK 有無 (モバイルホーム描画の成否)
3. WD: BOOT FROZEN RESET の発火回数 (復帰機構の動作証拠)
4. RENUM-OK / REENUM SKIP の出現 (静穏待ち完了の証拠)
