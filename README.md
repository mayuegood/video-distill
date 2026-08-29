# video-distill

**Turn any video into trustworthy, citable knowledge — with frame-level evidence for every correction.**

A [skill](https://github.com/anthropics/skills) for AI coding agents (Claude Code, ZCode, and anything that reads `SKILL.md`): dual-track frame extraction → transcription → **frame-evidence correction** → distillation. Every text change is traceable to a specific video frame; every deliverable passes an executable self-check before it can be called "done".

> 核心理念：**转录必有错，无证据不改字。** Speech-to-text errors (homophones, mangled proper nouns) can never be verified by re-listening — the video's own frames (slides, subtitles, on-screen text) are the only physical evidence. This pipeline makes every correction auditable and every completion claim verifiable.

English docs · 中文说明见下方

---

## Why this exists

Typical "video → notes" pipelines produce plausible text with silent errors baked in. Worse, the agent *claims* completion based on its own self-report — and nobody checks the artifacts on disk.

video-distill enforces two discipline layers:

1. **Evidence-based correction** — a transcription change is only allowed with a frame reference (`原文 → 改后 | 证据=scene113.jpg`). Unverifiable guesses stay in the text tagged `[UNVERIFIED]`.
2. **Executable self-check** — `verify-output.sh` verifies real artifacts on disk (not "the agent said it finished"). Exit 0 or it's not done. This was born from a real incident: a batch job reported success, but the output was never written to disk.

---

## What's inside

```
video-distill/
├── SKILL.md                      # Entry point: routing + pipeline rules (read this first)
├── scripts/
│   ├── extract.sh                # ①② ffmpeg dual-track frames + Whisper transcription
│   └── verify-output.sh          # ⑤ Executable self-check (12 checks, exit 0 = done)
└── references/
    ├── verify-protocol.md        # ③ Frame-evidence correction protocol + subagent template
    ├── distill.md                # ④ Distillation rules (input MUST be verified.txt)
    └── download.md               # ⓪ Download strategies + copyright boundary
```

## Pipeline

```
⓪ Download          yt-dlp (YouTube/Bilibili/…) — prefer official subtitle tracks as ground truth
①② Extract          extract.sh → frames/tick*.jpg + frames/scene*.jpg + transcript/raw.{txt,srt}
③ Correct           read frames as evidence → verified.txt + changes.log (every change cites a frame)
④ Distill           verified.txt (NEVER raw.txt) → DIGEST.md
⑤ Self-check        verify-output.sh → exit 0, or it's not done
```

**Why dual-track frame extraction:** speech-heavy videos rarely trigger scene changes (observed: 2 scene cuts in a 4-min talk), so scene detection alone gives too little evidence. Fixed-interval ticks guarantee coverage; scene frames add density where it matters. Filenames embed the second offset, aligning directly with the SRT timeline.

## Install

**Requirements:** `ffmpeg`, `yt-dlp`, Python 3, and [whisper.cpp](https://github.com/ggml-whisper/whisper.cpp)'s `whisper` CLI (or any compatible CLI with `--model/--output_format` flags). macOS/Linux. 16GB RAM machines: use the default `small` model and keep transcriptions serial.

```bash
git clone https://github.com/<you>/video-distill ~/.agents/skills/video-distill
```

That's it — agents discover the skill via `SKILL.md`. To verify an existing run:

```bash
bash ~/.agents/skills/video-distill/scripts/verify-output.sh <output_dir>
```

## The self-check (prove-it-works)

`verify-output.sh` runs 12 hard checks across three layers and is wired into the pipeline itself — extraction auto-runs it (stage mode), the correction protocol requires the parent agent to re-run it in full mode (a subagent's self-report doesn't count), and distillation ends with a full re-run as the final gate.

| Layer | Checks | Catches |
|---|---|---|
| Extract | frames exist / raw.txt+srt non-empty / readable / size scales with video length | "extract said it finished" but nothing landed on disk |
| Correct | verified.txt+changes.log exist / every change cites evidence / stats block / size ratio (route-aware) | missing evidence, silent mass deletion |
| Distill | DIGEST non-empty + source attribution | hollow deliverables |

Known boundary: the size-ratio check flags, it doesn't convict — subtitle-route transcripts get restructured (observed 38% is normal), so a FAIL there means "run the keyword spot-check", not "content is lost".

## Usage sketch

Tell your agent: *"处理这个视频 https://… / distill this video"* — the SKILL.md routing table picks the entry point (local file / WeChat-Channel link / normal URL / existing transcript / existing verified.txt). Or run layers manually — every script is standalone.

## Design notes

- **Correct, not rewrite**: the correction layer never touches word order, deletes sentences, or "improves" phrasing. 校对不是改写。
- **Route-aware thresholds**: subtitle-route raw transcripts are line-stacked (redundant) while Whisper-route ones are dense — size checks adapt accordingly.
- **Keep the unfixed visible**: uncorrectable suspicious words stay tagged `[UNVERIFIED: 疑似应为XX]` rather than being "helpfully" fixed.

## License

MIT

---

## 中文速览

把任意视频（本地文件 / 视频号 / YouTube / B站）加工成**可信、可审计**的知识：

1. **双路抽帧** — 固定间隔帧保证覆盖 + 场景切换帧补密度，文件名内嵌秒数对齐字幕时间轴
2. **转录** — Whisper（默认 small，16GB 机器稳）；有官方字幕轨时优先拿字幕当地面真值
3. **帧证据纠错** — 每处改动必须引用具体帧（`原文 → 改后 | 证据=帧文件名`）；无证据的疑似错误标 `[UNVERIFIED]` 保留，不许"顺手改对"；产出 `verified.txt + changes.log`
4. **蒸馏** — 只吃 verified.txt（raw.txt 的错字会渗进引文——实测发生过）
5. **可执行收尾自检** — `verify-output.sh` 对着磁盘真产物验证 12 项，exit 0 才算完成；源自真实事故（任务自报成功但产物根本没落盘）

安装：`git clone` 到 `~/.agents/skills/video-distill`（或你的 agent 对应的 skills 目录）即可被自动发现。
