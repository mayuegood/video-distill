#!/usr/bin/env bash
# video-distill ①② 提取层：双路抽帧 + Whisper 转录(txt+srt) + 纠错任务包 + 提取层自检
# 用法: bash extract.sh <video> <out_dir>
# 可调: WHISPER_MODEL(默认small) TICK_SEC(默认12) SCENE_THR(默认0.3)
# 依赖: ffmpeg + whisper CLI(whisper.cpp 或兼容 --model/--output_format 的实现)
# 设计依据: 口播/渐变类视频场景切换极少(实测4分钟仅2次)，单靠scene检测证据不足；
#           固定间隔保覆盖 + scene帧补密度，文件名带秒数可与srt时间轴对齐。
set -eu
VIDEO="${1:?用法: bash extract.sh <video.mp4> <out_dir>}"
OUT="${2:?缺输出目录}"
WHISPER_MODEL="${WHISPER_MODEL:-small}"
TICK_SEC="${TICK_SEC:-12}"
SCENE_THR="${SCENE_THR:-0.3}"

mkdir -p "$OUT/frames" "$OUT/transcript"

echo "═══ ① 双路抽帧（tick 每 ${TICK_SEC}s + scene 检测）═══"
# 固定间隔: 全程覆盖兜底
ffmpeg -hide_banner -loglevel error -i "$VIDEO" -vf "fps=1/${TICK_SEC}" -q:v 3 "$OUT/frames/tick%04d.jpg"
# 场景切换: 信息密度高(板书翻页/镜头切换), 阈值越低越敏感
ffmpeg -hide_banner -loglevel error -i "$VIDEO" -vf "select='gt(scene,${SCENE_THR})',showinfo" -vsync vfr -q:v 3 "$OUT/frames/scene%04d.jpg" 2>/tmp/sd.log || true
# showinfo 里带 pts_time, 提出来重命名为 scene<秒>.jpg 方便与 srt 对齐
python3 - <<PYEOF
import re, os, glob
log = open("/tmp/sd.log", errors="ignore").read()
times = re.findall(r"pts_time:([\d.]+)", log)
scenes = sorted(glob.glob("$OUT/frames/scene*.jpg"))
for f, t in zip(scenes, times):
    os.rename(f, "$OUT/frames/scene%d.jpg" % int(float(t)))
print(f"  scene 帧对齐: {len(times)} 个切换点")
PYEOF
TICKS=$(ls "$OUT"/frames/tick*.jpg 2>/dev/null | wc -l | tr -d ' ')
SCENES=$(ls "$OUT"/frames/scene*.jpg 2>/dev/null | wc -l | tr -d ' ')
echo "  抽帧完成: tick ${TICKS} 张 + scene ${SCENES} 张"

echo "═══ ② 转录层（Whisper：${WHISPER_MODEL} 模型，txt + srt）═══"
if [ ! -f "$OUT/transcript/raw.txt" ] || [ ! -f "$OUT/transcript/raw.srt" ]; then
  # 若调用方已预放字幕(官方字幕轨路线), 自动跳过 whisper
  # 注意: whisper.cpp 的 --output_format 是单值参数(重复传只保留最后一个),
  #       所以跑两次(--output_format txt 一次, srt 一次)或用 all 一次拿全
  ffmpeg -hide_banner -loglevel error -i "$VIDEO" -vn -ac 1 -ar 16000 "$OUT/audio.mp3"
  WHISPER_LANG="${WHISPER_LANG:-auto}"
  LANG_FLAG=""
  [ -n "${WHISPER_LANG}" ] && [ "${WHISPER_LANG}" != "auto" ] && LANG_FLAG="--language ${WHISPER_LANG}"
  whisper "$OUT/audio.mp3" --model "$WHISPER_MODEL" \
      --output_format all --output_dir "$OUT/transcript" 2>/dev/null \
    || whisper "$OUT/audio.mp3" --model "$WHISPER_MODEL" $LANG_FLAG \
      --output_format all --output_dir "$OUT/transcript" 2>/dev/null
  mv -f "$OUT/transcript/audio.txt" "$OUT/transcript/raw.txt"
  mv -f "$OUT/transcript/audio.srt" "$OUT/transcript/raw.srt"
  rm -f "$OUT"/transcript/audio.vtt "$OUT/transcript/audio.tsv" "$OUT/transcript/audio.json" "$OUT/audio.mp3"
  # 把 whisper 检测到的语言写进文件头，供下游校验参考
  DETECTED=$(grep -oP 'Detected language: \K\S+' "$OUT/transcript/raw.srt" 2>/dev/null | head -1)
  [ -n "$DETECTED" ] && echo "  检测语言: $DETECTED"
fi
CHARS=$(wc -m < "$OUT/transcript/raw.txt" | tr -d ' ')
echo "  转录初稿 OK · ${CHARS} 字符（保留原始误写，可审计）"

echo "═══ ③ 纠错任务包生成 ═══"
FRAMES=$((TICKS + SCENES))
cat > "$OUT/transcript/verify-task.md" <<EOF
# 纠错任务
对照关键帧画面（板书/字幕/图表中的文字）校对转录文本的误写。

## 待校对材料
- raw.txt —— 转录初稿（保留原始误写，可审计）
- raw.srt —— 带时间轴的转录（定位某句话出现在视频第几秒）

## 视觉证据（关键帧）
$OUT/frames/ 目录，共 ${FRAMES} 张，文件名带时间戳：
- tickNNNN.jpg —— 固定间隔帧（全程覆盖兜底）
- sceneNNN.jpg —— 场景切换帧（板书翻页/镜头切换，信息密度高）

## 做法
1. 先扫一遍帧，记下每张帧里出现的板书/字幕文字（专有名词优先）
2. 用 raw.srt 把帧时间戳对到对应句子
3. 只改有帧证据支撑的错误（帧里有"岷江"两个字才改"明江→岷江"）

## 要求（详见 skill 的 references/verify-protocol.md）
1. 每处改动记录：原文 → 改后 → 证据帧文件名（写入 changes.log）
2. 无证据的疑似错误保留并标注 [UNVERIFIED]
3. 繁体→简体转换需逐句进行，不改动词序
4. 产出 verified.txt（纯净文本）+ changes.log（可审计）
EOF
echo "  verify-task.md 就绪"

echo ""
echo "═══ 提取层产物 ═══"
find "$OUT" -type f | sort

# 验证 raw.txt 真的产生了内容（whisper 失败或 0 字节不应算 extract 完成）
if [ ! -s "$OUT/transcript/raw.txt" ]; then
  echo "  ⚠ raw.txt 为空，whisper 转录可能失败"
  exit 1
fi

echo ""
echo "═══ 自动清理过程垃圾 ═══"
if [ -f "$OUT/audio.mp3" ]; then rm -f "$OUT/audio.mp3"; echo "  ✓ audio.mp3（whisper 用完，原始视频里有音轨可重提取）"; fi
for f in "$OUT"/*.log; do [ -e "$f" ] && rm -f "$f"; done
rm -f /tmp/sd.log
echo "  保留: transcript/（含 raw.txt / raw.srt / verify-task.md）+ frames/（视觉证据）"

echo ""
echo "═══ ⑤ 收尾自检（提取层范围，prove-it-works）═══"
# 只验 ①② 层(纠错/蒸馏还没发生); verify-output.sh 对缺失的 verified 会报 FAIL 属预期,
# 因此用 stage=extract 模式: 只跑提取层检查, 结果计入退出码
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
if bash "$SELF_DIR/verify-output.sh" "$OUT" --stage extract; then
  echo "  提取层自检 PASS — 可以进入 ③ 纠错（读 references/verify-protocol.md）"
else
  echo "  ⚠ 提取层自检 FAIL — 先修复上面的 FAIL 项, 不要带病进 ③"
  exit 1
fi
