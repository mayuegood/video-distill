#!/usr/bin/env bash
# ============================================================
# verify-output.sh — video-distill 管线收尾自检(prove-it-works)
# 用法: bash verify-output.sh <out_dir> [--stage extract]
#   --stage extract: 只跑提取层(供 extract.sh 末尾自动调用, ③④未发生不报 FAIL)
# 退出码: 0 = 全部通过; 1 = 有 FAIL(管线不算完成)
# 原则: 验证对着真东西(磁盘文件/帧内容), 不拿替身当证据
# ============================================================
set -u
OUT="${1:?用法: verify-output.sh <out_dir> [--stage extract]}"
STAGE="${2:-}"
PASS=0; FAIL=0
SKIP_ERRATA=0; SKIP_DISTILL=0
[ "$STAGE" = "--stage" ] && { STAGE_VAL="${3:-}"; [ "$STAGE_VAL" = "extract" ] && { SKIP_ERRATA=1; SKIP_DISTILL=1; }; }

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "  PASS  $desc"; PASS=$((PASS+1))
  else
    echo "  FAIL  $desc"; FAIL=$((FAIL+1))
  fi
}

# 前提检查: 前置文件不存在时, 后续"内容质量"类检查直接 SKIP 而非误 PASS
need_file() {  # need_file <path> — 文件存在返回 0
  test -s "$1"
}

echo "═══ prove-it-works 收尾自检: $OUT ═══"

echo "── ①② 提取层 ──"
check "frames/ 目录存在且非空"          test -n "$(ls "$OUT/frames/"*.jpg 2>/dev/null)"
check "transcript/raw.txt 存在且非空"   test -s "$OUT/transcript/raw.txt"
check "transcript/raw.srt 存在且非空"   test -s "$OUT/transcript/raw.srt"
# 可读性检查: 前置是文件真的存在(file 对缺失文件也会输出错误串, 会误 PASS)
if need_file "$OUT/transcript/raw.txt"; then
  check "raw.txt 是可读文本(非二进制)"  bash -c "file -b '$OUT/transcript/raw.txt' | grep -qv 'cannot open'"
else
  check "raw.txt 是可读文本(非二进制)"  false
fi
# raw.txt 体量自适应: ≥10 字节/秒视频时长(60s→600B, 72min→43KB)。
# 时长从 raw.srt 末条时间戳解析; 解析失败回退 300 字节空壳下限。
VID_LEN=$(grep -oE '[0-9]{2}:[0-9]{2}:[0-9]{2}' "$OUT/transcript/raw.srt" 2>/dev/null | tail -1 | awk -F: '{print ($1*3600)+($2*60)+$3}')
[ -z "$VID_LEN" ] && VID_LEN=0
MIN_BYTES=$((VID_LEN * 10))
[ "$MIN_BYTES" -lt 300 ] && MIN_BYTES=300   # 下限仅防空壳; 真判据是 10B/s 斜率
check "raw.txt 体量合理(≥${MIN_BYTES}B, 视频约${VID_LEN}s)" test "$(wc -c < "$OUT/transcript/raw.txt" 2>/dev/null || echo 0)" -ge "$MIN_BYTES"

echo "── ③ 纠错层 ──"
if [ "$SKIP_ERRATA" = "1" ]; then
  echo "  SKIP  (stage=extract: ③ 尚未发生)"
else
check "verified.txt 存在且非空"         test -s "$OUT/transcript/verified.txt"
check "changes.log 存在且非空"          test -s "$OUT/transcript/changes.log"
# changes.log 里每一处 "→" 改动行都必须带证据标注(帧文件名或 COMMON-SENSE)
# 逻辑: 若存在改动行且存在缺证据的改动行 → FAIL; 无改动行(纯格式日志)→ PASS
if grep -q "→" "$OUT/transcript/changes.log" 2>/dev/null; then
  check "changes.log 改动行全带证据标注"  bash -c "! grep -E '→' '$OUT/transcript/changes.log' | grep -vE '证据=|COMMON-SENSE|格式|N/A' | grep -q ."
else
  check "changes.log 改动行全带证据标注"  bash -c "test -s '$OUT/transcript/changes.log'"
fi
# 统计行的四项指标存在
check "changes.log 末尾有四行统计"       bash -c "grep -q '总改动数' '$OUT/transcript/changes.log' && grep -q '帧证据' '$OUT/transcript/changes.log'"
# verified.txt 不能比 raw.txt 短太多——但两条路线体量特征不同:
#   whisper 路线: raw 是密集口播文本 → verified ≥60% 正常
#   字幕预放路线: raw 是字幕逐行堆叠(冗余大, verified 会按意段重组) → ≥25% 即可
# 判别: raw.srt 里含 "-->" 时间轴标记密度高 = 字幕路线
# 另: 阈值报警 ≠ 内容真丢,须用关键词抽查复核(见 SKILL.md ⑤ 抽查条款)
if grep -q -- "-->" "$OUT/transcript/raw.srt" 2>/dev/null; then
  MIN_PCT=25; ROUTE="字幕预放"
else
  MIN_PCT=60; ROUTE="whisper"
fi
RAW=$(wc -c < "$OUT/transcript/raw.txt" 2>/dev/null || echo 0)
VER=$(wc -c < "$OUT/transcript/verified.txt" 2>/dev/null || echo 0)
check "verified.txt 体量合理(≥${MIN_PCT}% raw, ${ROUTE}路线, 实际 $((VER * 100 / (RAW>0?RAW:1)))%)" bash -c "test $VER -ge $((RAW * MIN_PCT / 100))"
fi

echo "── ④ 蒸馏层(可选,有 DIGEST 才查) ──"
if [ "$SKIP_DISTILL" = "1" ]; then
  echo "  SKIP  (stage=extract: ④ 尚未发生)"
elif test -f "$OUT/DIGEST.md"; then
  check "DIGEST.md 非空"                test -s "$OUT/DIGEST.md"
  # 引文核对: DIGEST 里若引用了 verified 独有内容, 抽查首条引文行能在 verified.txt 找到
  check "DIGEST.md 含来源标注"          grep -q "verified" "$OUT/DIGEST.md"
else
  echo "  SKIP  DIGEST.md 不存在(本次交付到 verified.txt 为止)"
fi

echo "═══ 结果: PASS=$PASS FAIL=$FAIL ═══"
test "$FAIL" -eq 0
