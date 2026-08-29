#!/usr/bin/env bash
# video-distill ①② 提取层：双路抽帧 + Whisper 转录(txt+srt) + 纠错任务包
# 用法: bash extract.sh <video> <out_dir>
# 可调: WHISPER_MODEL(默认small) TICK_SEC(默认12) SCENE_THR(默认0.3)
# 设计依据: 口播/渐变类视频场景切换极少(实测4分钟仅2次)，单靠scene检测证据不足；
#           固定间隔保覆盖 + scene帧补密度，文件名带秒数可与srt时间轴对齐。
set -eu
VIDEO="${1:?用法: bash extract.sh <video.mp4> <out_dir>}"
OUT="${2:?缺输出目录}"
WHISPER_MODEL="${WHISPER_MODEL:-small}"
TICK_SEC="${TICK_SEC:-12}"
SCENE_THR="${SCENE_THR:-0.3}"
mkdir -p "$OUT"/{frames,audio,transcript}

echo "═══ ① 提取层（ffmpeg：音轨 + 双路关键帧）═══"
# 音轨防御：X/GIF 场景常见无音轨视频（无声 loop 动图），ffmpeg 提音轨会失败
HAS_AUDIO=$(ffprobe -v error -select_streams a -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$VIDEO" 2>/dev/null | head -1)
if [ -z "$HAS_AUDIO" ]; then
  echo "  ⚠ 视频无音轨（无声动图/纯画面），跳过转录，只抽帧"
  NO_AUDIO=1
  rm -rf "$OUT/audio"
else
  NO_AUDIO=0
  ffmpeg -y -i "$VIDEO" -vn -acodec libmp3lame -q:a 4 "$OUT/audio/audio.mp3" 2>/dev/null
fi
rm -f "$OUT"/frames/*.jpg "$OUT"/frames/*-times.txt
# A 路 tick：固定间隔，全程覆盖兜底
ffmpeg -y -i "$VIDEO" -vf "fps=1/${TICK_SEC},showinfo" -vsync vfr \
  "$OUT/frames/_tick-%03d.jpg" 2>&1 | grep -o "pts_time:[0-9.]*" | cut -d: -f2 > "$OUT/frames/tick-times.txt" || true
# B 路 scene：场景切换帧（板书翻页/镜头切换，信息密度高）
ffmpeg -y -i "$VIDEO" -vf "select='gt(scene,${SCENE_THR})',showinfo" -vsync vfr \
  "$OUT/frames/_scene-%03d.jpg" 2>&1 | grep -o "pts_time:[0-9.]*" | cut -d: -f2 > "$OUT/frames/scene-times.txt" || true
i=0
while read -r t; do
  i=$((i+1)); mv "$OUT/frames/_tick-$(printf '%03d' "$i").jpg" "$OUT/frames/tick$(printf '%03d' "${t%.*}").jpg"
done < "$OUT/frames/tick-times.txt"
i=0; kept=0
while read -r t; do
  i=$((i+1))
  # 距最近 tick <1.5s 的 scene 帧是重复证据，跳过
  near=$(awk -v t="$t" -v s="$TICK_SEC" 'BEGIN{m=t-int(t/s)*s; print (m<1.5||m>s-1.5)?1:0}')
  [ "$near" = "1" ] && continue
  mv "$OUT/frames/_scene-$(printf '%03d' "$i").jpg" "$OUT/frames/scene$(printf '%03d' "${t%.*}").jpg"
  kept=$((kept+1))
done < "$OUT/frames/scene-times.txt"
rm -f "$OUT"/frames/_*.jpg
FRAMES=$(ls "$OUT"/frames/*.jpg 2>/dev/null | wc -l | tr -d ' ')
echo "  音轨 OK · 关键帧 ${FRAMES} 张（tick $(wc -l < "$OUT/frames/tick-times.txt" | tr -d ' ') + scene 增量 ${kept}，文件名=秒数）"

echo "═══ ② 转录层（Whisper：${WHISPER_MODEL} 模型，txt + srt）═══"
if [ "$NO_AUDIO" = "1" ]; then
  printf "" > "$OUT/transcript/raw.txt"
  printf "" > "$OUT/transcript/raw.srt"
  echo "  跳过（无音轨）· 画面内容见 frames/，信息在帧不在语音"
elif [ ! -f "$OUT/transcript/raw.txt" ] || [ ! -f "$OUT/transcript/raw.srt" ]; then
  # 注意: whisper 的 --output_format 是单值参数(重复传只保留最后一个)，
  # 所以用 all 全量输出 + 显式路径重命名，不用通配符（空目录下 mv *.txt 会炸）
  rm -f "$OUT"/transcript/audio.*
  # 语言自动检测：环境变量 WHISPER_LANG 优先（zh/en/auto），否则 auto
  # 英文视频被强制 zh 会产生"繁體中文幻觉"，必须 auto
  LANG_FLAG="auto"
  [ -n "${WHISPER_LANG:-}" ] && [ "${WHISPER_LANG}" != "auto" ] && LANG_FLAG="${WHISPER_LANG}"
  if [ "$LANG_FLAG" = "auto" ]; then
    whisper "$OUT/audio/audio.mp3" --model "$WHISPER_MODEL" \
      --output_format all --output_dir "$OUT/transcript" 2>/dev/null
  else
    whisper "$OUT/audio/audio.mp3" --model "$WHISPER_MODEL" --language "$LANG_FLAG" \
      --output_format all --output_dir "$OUT/transcript" 2>/dev/null
  fi
  mv -f "$OUT/transcript/audio.txt" "$OUT/transcript/raw.txt"
  mv -f "$OUT/transcript/audio.srt" "$OUT/transcript/raw.srt"
  rm -f "$OUT"/transcript/audio.vtt "$OUT"/transcript/audio.tsv "$OUT"/transcript/audio.json
  # 把 whisper 检测到的语言写进文件头，供下游校验参考
  DETECTED=$(grep -oP 'Detected language: \K\S+' "$OUT/transcript/raw.srt" 2>/dev/null | head -1)
  [ -n "$DETECTED" ] && echo "  检测语言: $DETECTED"
fi
CHARS=$(wc -m < "$OUT/transcript/raw.txt" | tr -d ' ')
if [ "$NO_AUDIO" = "1" ]; then
  echo "  无音轨 · 0 字符（正常，画面类内容）"
else
  echo "  转录初稿 OK · ${CHARS} 字符（保留原始误写，可审计）"
fi

echo "═══ ③ 纠错任务包生成 ═══"
cat > "$OUT/transcript/verify-task.md" <<EOF
# 纠错任务
对照关键帧画面（板书/字幕/图表中的文字）校对转录文本的同音误写。

## 待校对材料
- raw.txt —— 转录初稿（保留原始误写，含已知错误模式：繁体输出、人名地名术语误写）
- raw.srt —— 带时间轴的转录（定位某句话出现在视频第几秒）

## 视觉证据（关键帧）
$OUT/frames/ 目录，共 ${FRAMES} 张，文件名带时间戳：
- tickNNN.jpg —— 第 NNN 秒的固定间隔帧（全程覆盖兜底）
- sceneNNN.jpg —— 第 NNN 秒的场景切换帧（板书翻页/镜头切换，信息密度高）

## 做法
1. 先扫一遍帧，记下每张帧里出现的板书/字幕文字（专有名词优先）
2. 用 raw.srt 把帧时间戳对到对应句子
3. 只改有帧证据支撑的错误（帧里有"岷江"两个字才改"明江→岷江"）

## 要求（详见 skill 的 references/verify-protocol.md）
1. 每处改动记录：原文 → 改后 → 证据帧文件名（写入 changes.log）
2. 无证据的疑似错误保留并标注 [UNVERIFIED]
3. 繁体→简体转换需逐句进行，不改动词序
4. 产出 verified.txt（纯净简体）+ changes.log（可审计）到本目录
EOF
echo "  任务包 OK → $OUT/transcript/verify-task.md"

echo ""
echo "═══ 完成 · 下一步 ═══"
echo "  ③ 按 verify-protocol.md 读帧纠错 → verified.txt + changes.log"
echo "  ④ 用 verified.txt（不是 raw.txt）蒸馏"
find "$OUT" -type f | sort

# 验证 raw.txt 真的产生了内容（whisper 失败或 0 字节不应算 extract 完成）
# 例外：无音轨视频 raw.txt 为空是正常结果
if [ "$NO_AUDIO" != "1" ] && [ ! -s "$OUT/transcript/raw.txt" ]; then
  echo "  ⚠ raw.txt 为空，whisper 转录可能失败"
  exit 1
fi
echo ""
echo "═══ 自动清理过程垃圾 ═══"
AUDIO_BYTES=0
LOGS_BYTES=0

if [ -d "$OUT/audio" ]; then
  AUDIO_BYTES=$(du -sk "$OUT/audio" | awk '{print $1}')
  rm -rf "$OUT/audio"
  echo "  ✓ audio/（whisper 用完，原始视频里有音轨可重提取）"
fi

# 留 raw.txt + raw.srt + frames + transcript（这是核心交付物）
# 其他过程文件一律删
for f in "$OUT"/*.log; do [ -e "$f" ] && rm -f "$f"; done

echo "  保留: transcript/（含 verified.txt / changes-*.log / raw.txt / raw.srt）+ frames/（视觉证据）"

echo ""
echo "═══ ⑤ 收尾自检（提取层范围，prove-it-works）═══"
# 只验 ①② 层(纠错/蒸馏还没发生); verify-output.sh 对缺失的 verified 会报 FAIL 属预期,
# 因此这里用 stage=extract 模式: 只跑提取层检查, 结果计入退出码
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
if bash "$SELF_DIR/verify-output.sh" "$OUT" --stage extract; then
  echo "  提取层自检 PASS — 可以进入 ③ 纠错"
else
  echo "  ⚠ 提取层自检 FAIL — 先修复上面的 FAIL 项, 不要带病进 ③"
  exit 1
fi
