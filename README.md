# video-distill

[**简体中文**](README.md) | [English](README_EN.md)

<p align="center"><img src="docs/pipeline.svg" alt="video-distill pipeline" width="880"></p>

> 把任意视频变成**可信、可引用**的知识——每一处文字修正都有具体帧作证，每一次"完成"都要过可执行自检。

一个面向 AI 编程智能体（Claude Code / ZCode 等一切读取 `SKILL.md` 的 agent）的[技能](https://github.com/anthropics/skills)：双路抽帧 → 转录 → **帧证据纠错** → 蒸馏 → 可执行收尾自检。

核心理念：**转录必有错，无证据不改字。** 语音转文字的同音字误写、专有名词错拼，靠重听永远验不出来——视频画面里的板书、字幕、术语写法才是唯一的物证。

---

## 为什么需要它

常见的"视频转文字"管线产出的文本，错误是静默的——更糟的是，agent 基于"自我汇报"就宣称完成，没人检查磁盘上的真产物。video-distill 用两层纪律对治：

1. **帧证据纠错** —— 每处文字改动必须引用具体帧（`原文 → 改后 | 证据=scene113.jpg`）；无证据的疑似错误标 `[UNVERIFIED]` 保留，绝不"顺手改对"。
2. **可执行自检（prove-it-works）** —— `verify-output.sh` 对着磁盘真产物跑 12 项硬检查，exit 0 才算完成。这条纪律源自真实事故：批量任务自报成功，产物根本没落盘。

## 适用场景

凡是"视频里的内容，之后要被**引用、汇总、拿来做决定**"的场景——都适用。

| 场景 | 为什么需要帧证据 |
|---|---|
| **讲座 / 播客 → 笔记** | 口播术语被转错，帧里 slide 的写法才是标准写法 |
| **教程视频 → 操作手册** | 命令行参数、文件名（`SOUL.md` vs `sore.md`）只有画面能锁定，听永远分不清 |
| **会议录像 → 决议纪要** | "预算 300 万"错成 30 万是要出事的——板书 / PPT 是物证 |
| **批量视频处理** | 逐条人工校对不现实；可审计的自动化 = 每处改动有帧作证，抽查即可放行 |
| **采访 / 对谈 → 引文引用** | 引文可信度靠 changes.log 背书，敢直接引用 |
| **多语言视频（繁转简）** | Whisper 中文输出常带繁体 + 同音字，逐句转换最容易顺手改错 |

**不适用**：纯音乐 MV、画面无文字且术语密度低的闲聊视频（帧证据没东西可锚）、实时直播。

## 依赖工具

| 工具 | 用在哪 | 必需？ | 获取 |
|---|---|---|---|
| **ffmpeg** | 双路抽帧（固定间隔 + 场景切换）、音频提取 | ✅ 必需 | `brew install ffmpeg` / [ffmpeg.org](https://ffmpeg.org) |
| **yt-dlp** | ⓪ 下载（YouTube / B站 / 抖音等）、探测字幕轨 | ✅ 必需 | `brew install yt-dlp` / [yt-dlp.org](https://github.com/yt-dlp/yt-dlp) |
| **whisper.cpp** 的 `whisper` CLI | ② 转录（或任何兼容 `--model/--output_format` 的实现） | 转录必需（字幕预放路线可跳过） | [ggml-whisper/whisper.cpp](https://github.com/ggml-whisper/whisper.cpp) |
| **Python 3** | extract.sh 内部（帧时间戳对齐） | ✅ 必需 | 系统自带或 [python.org](https://www.python.org) |
| **多模态图像理解** | ③ 读帧证据（Claude / GPT-4V / Gemini 视觉，或本地 VLM） | 纠错必需（无则人工看帧） | 随你的 agent |

> **16GB 内存机器**：whisper 用默认 `small` 模型即可，务必串行跑、`nice -n 15` 降权（详见 SKILL.md 本机负载纪律）。

## 目录结构

```
video-distill/
├── SKILL.md                      # 入口：路由 + 管线规则（先读这个）
├── scripts/
│   ├── extract.sh                # ①② ffmpeg 双路抽帧 + Whisper 转录
│   └── verify-output.sh          # ⑤ 可执行收尾自检（12 项检查，exit 0 = 完成）
└── references/
    ├── verify-protocol.md        # ③ 帧证据纠错协议 + subagent 派发模板
    ├── distill.md                # ④ 蒸馏规则（输入必须是 verified.txt）
    └── download.md               # ⓪ 下载策略 + 版权边界
```

## 管线

```
⓪ 下载          yt-dlp（YouTube/B站/抖音…）——优先拿官方字幕轨当地面真值
①② 提取         extract.sh → frames/tick*.jpg + frames/scene*.jpg + transcript/raw.{txt,srt}
③ 纠错          读帧作证据 → verified.txt + changes.log（每处改动引用一帧）
④ 蒸馏          只吃 verified.txt（绝不吃 raw.txt）→ DIGEST.md
⑤ 自检          verify-output.sh → exit 0，否则不算完成
```

**为什么双路抽帧**：口播类视频极少触发场景切换（实测 4 分钟仅 2 次），单靠场景检测证据不够；固定间隔保证覆盖，场景帧补密度。文件名内嵌秒数，可直接对齐 SRT 时间轴。

## 安装

```bash
git clone https://github.com/mayuegood/video-distill ~/.agents/skills/video-distill
```

完成——agent 通过 `SKILL.md` 自动发现该技能。验证一次已有产物：

```bash
bash ~/.agents/skills/video-distill/scripts/verify-output.sh <输出目录>
```

## 自检层（prove-it-works）

`verify-output.sh` 跨三层跑 12 项硬检查，且已焊进管线自身——提取层自动触发（stage 模式），纠错协议要求主 agent 亲自重跑完整模式（subagent 的自我汇报不算数），蒸馏收尾全量再跑一次作为最后一道闸。

| 层 | 检查 | 抓什么坑 |
|---|---|---|
| 提取 | frames 存在 / raw.txt+srt 非空 / 可读 / 体量随时长自适应 | "extract 说跑完了"但产物没落盘 |
| 纠错 | verified.txt+changes.log 存在 / 每处改动带证据标注 / 统计块 / 体量比（按路线自适应） | 缺证据、静默大段删改 |
| 蒸馏 | DIGEST 非空 + 来源标注 | 空壳交付物 |

已知边界：体量比检查只报警不定罪——字幕路线的转录会按意段重组（实测 38% 属正常），FAIL 意味着"跑关键词抽查"，不是"内容丢了"。

## 使用方式

对 agent 说：**"处理这个视频 https://… "**——SKILL.md 的路由表自动选入口（本地文件 / 视频号链接 / 普通链接 / 已有转录 / 已有 verified.txt）。也可手动分层运行——每个脚本都可独立执行。

## 设计决策

- **校对不是改写**：纠错层绝不改语序、不删句、不润色。
- **阈值按路线自适应**：字幕路线的 raw 是逐行堆叠（冗余大），whisper 路线是密文本——体量检查相应区分。
- **保留未修正的可见性**：无法验证的存疑词标 `[UNVERIFIED: 疑似应为XX]` 留在原文里，而不是"好心"改掉。

## 致谢与先例

- **[pstack](https://github.com/cursor/plugins/tree/main/pstack)**（Lauren Tan, Cursor）—— `principle-prove-it-works` 原则直接启发了本管线的可执行自检层（"对着真产物验证，而不是代理物、自我汇报或'能编译'"），其 playbook/路由模式也影响了 SKILL.md 的分层设计。
- **[cangjie-skill](https://github.com/kangarooking/cangjie-skill)**（仓颉）—— 可选的重蒸馏路径（七阶段）；本仓库内置的 RIA-lite 是 fallback。
- **[whisper.cpp](https://github.com/ggml-whisper/whisper.cpp)** —— 转录后端。
- **[yt-dlp](https://github.com/yt-dlp/yt-dlp)** / **[ffmpeg](https://ffmpeg.org)** —— 下载与双路抽帧。
- 帧证据纠错方法论（每处改动引用具体帧）源自一次真实的批量转录事故：静默同音字错误渗进了发布版摘要；协议文档见 `references/verify-protocol.md`。

如果这个仓库对你有帮助，欢迎点个 star —— 也欢迎 PR，尤其是各平台专属的下载配方。

## License

MIT
