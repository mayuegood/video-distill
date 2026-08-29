---
name: video-distill
description: 把任意视频（本地文件/视频号 sph 链接/普通视频链接）加工成可信知识：ffmpeg 双路抽帧 → Whisper 转录 → 帧证据纠错 → 蒸馏。用户说"处理这个视频""转录视频""蒸馏视频""提取视频内容""视频号视频拿内容""严谨转录"，或给出 .mp4 文件 / weixin.qq.com/sph/ 链接要求提取内容时使用。纯下载不提内容、纯剪辑转格式的请求不用此 skill。
---

# video-distill — 严谨视频内容提取管线

核心原则：**转录必有错，无证据不改字**。Whisper 对中文口播的同音字误写（民江→岷江、禮兵→李冰）靠音频永远验不出来，视频里的板书/字幕才是物证。本管线的每一处改动都必须能追溯到一张具体的帧。

> `$SKILL_DIR` = 本 skill 的安装目录（下文所有脚本路径相对它）。
> 典型位置：`~/.agents/skills/video-distill/`（Claude Code / ZCode 等 agent 自动发现）。

## 路由：先判断从哪一步进

| 用户手里有什么 | 从哪开始 |
|---|---|
| 本地视频文件 (.mp4/.mov/.webm) | 直接 ①② 提取层 |
| 视频号链接 (weixin.qq.com/sph/) | ⓪ 先读 `references/download.md` 下载 → ①② |
| YouTube/B站/抖音等普通链接 | 先 `yt-dlp --dump-json` 探**手动字幕轨**：有则 `yt-dlp --write-sub --sub-lang zh --convert-subs srt` 拿字幕当地面真值（转成 raw.srt + raw.txt 预放 transcript/，extract.sh 会自动跳过 whisper，只补抽帧）；无字幕才 `yt-dlp` 下视频走完整管线 |
| 已有转录文本（含错字） | 直接 ③ 纠错（可跳过抽帧，无帧则只做规则修复） |
| 已有 verified.txt | 直接 ④ 蒸馏 |

## ①② 提取层：跑脚本，不要手写 ffmpeg

```bash
bash "$SKILL_DIR/scripts/extract.sh" <video> <out_dir>
# 可调参数（环境变量，都有默认值）:
#   WHISPER_MODEL=medium   转录模型（默认 small，16GB 内存机器 small 稳）
#   TICK_SEC=8             固定抽帧间隔秒数（默认 12）
#   SCENE_THR=0.3          场景切换阈值（默认 0.3）
```

产物树（`<out_dir>/` 下）：

- `frames/tickNNN.jpg` — 每 TICK_SEC 秒一帧（NNN=秒数，全程覆盖兜底）
- `frames/sceneNNN.jpg` — 场景切换帧（板书翻页/镜头切换，信息密度高）
- `transcript/raw.txt` + `raw.srt` — 转录初稿（**保留原始误写**，可审计）+ 时间轴
- `transcript/verify-task.md` — ③ 的任务包

为什么是双路抽帧：口播/画面渐变类视频场景切换极少（实测 4 分钟只触发 2 次），单靠 scene 检测证据不够；固定间隔保证覆盖，scene 帧补密度。文件名内嵌秒数，可直接与 srt 时间轴对齐。

## ③ 帧证据纠错：本管线的灵魂

**先完整读 `references/verify-protocol.md`**（证据规则 + 读帧方法 + dispatch 模板都在里面），然后二选一执行：

- 视频短（<10 分钟、帧 <30 张）→ 主 agent 自己读帧纠错
- 更长或需要并行 → 派 general-purpose subagent，协议文件里有现成 dispatch prompt 模板

产出硬标准：`verified.txt` + `changes.log`（每处改动一行：`原文 → 改后 | 证据=帧文件名`）。**没有 changes.log 的 verified.txt 不算完成**——不可审计的纠错等于没纠。

## ④ 蒸馏

**输入必须是 verified.txt，绝不吃 raw.txt**——错字会原样渗进引文（实测发生过：都江宴/禮賓/明江 渗进了发布版 DIGEST）。具体走法读 `references/distill.md`：有 cangjie-skill 交给它跑七阶段，没有就用内置 RIA-lite 结构。

## ⑤ 收尾自检（prove-it-works）——宣告完成前必须逐条过，任何一条不过 = 没完成

> **执行方式**：跑 `bash "$SKILL_DIR/scripts/verify-output.sh" <out_dir>`（一条命令跑完所有硬检查，exit 0 = 通过）。
> 脚本覆盖下述全部检查项；脚本报 FAIL 时逐项修复后重跑，**不许带着 FAIL 宣告完成**。
> 手动核对项（脚本无法自动化的两条）也必须做：
> 1. **抽查 1 处纠错**：Read changes.log 里某条改动对应的那帧 jpg → 图里真有改后的字？（防"agent 幻觉看过帧"）
> 2. **引文核对**：DIGEST.md 里的引文逐条 grep verified.txt（防 raw.txt 错字渗进引文——实测发生过：都江宴/禮賓/明江）

原则：**验证对着真东西（磁盘上的文件、能 Read 出字的帧），不许拿替身（self-report、exit code、"应该已生成"）当证据。**

> 灵感来源：pstack `principle-prove-it-works` —— "Verify against the real artifact, not a proxy, self-report, or 'it compiles'."
> 本管线的本土化案例：一次批量处理中，任务 exit 0 + 自报完成，但推理根本没落盘（bridge 超时杀进程）。
> 教训：**磁盘是真值，其余都是传闻。**

### 脚本覆盖的检查项(verify-output.sh 自动跑)

| 层 | 检查 | 抓什么坑 |
|---|---|---|
| ①② 提取 | frames 非空 / raw.txt+raw.srt 存在非空 / 可读 / 体量随时长自适应 | "extract.sh 说跑完了"但产物没落盘 |
| ③ 纠错 | verified.txt+changes.log 存在 / 改动行全带证据标注 / 四行统计齐全 / **体量合理(whisper 路线≥60%,字幕路线≥25%)** | verified 缺失、changes.log 缺证据、纠错时误删大段内容 |
| ④ 蒸馏 | DIGEST 非空 + 含来源标注(有才查) | 蒸馏产物空壳 |

**已知边界**：体量阈值报警 ≠ 内容真丢——字幕路线的 verified 会按意段重组(实测 38% 正常)。脚本报 FAIL 时先做关键词抽查(抽 raw 里 10 个关键术语 grep verified),全覆盖则是阈值误判,缺了才是真丢。

### 触发链（自检已焊进管线，不靠自觉）

- `extract.sh` 末尾自动跑 `verify-output.sh --stage extract`（只查提取层），FAIL 则 exit 1 不放行进 ③
- 纠错层（含 subagent 路线）：subagent 收尾自跑自检；**主 agent 必须亲自重跑完整模式**——subagent 自报"通过"不算（self-report 不是证据）
- 蒸馏收尾全量再跑一次，作为最后一道闸

## 质量红线

- 拒绝"文案级元数据"（标题+简介+话题标签那种）——最低交付物 = verified.txt，不是视频描述
- 疑似错误无帧证据 → 保留原文 + 标 `[UNVERIFIED: 疑似应为XX]`，不许"顺手改对"
- 蒸馏中的引文一律取自 verified.txt
- 处理需要登录态/浏览器的下载时，用完必须关闭 tab 连接（平台风控，见 download.md）

## 本机负载纪律（低内存机器适用）

- whisper 一律**串行**跑，绝不并行；整链 `nice -n 15` 降权，别抢 UI 的 CPU
- 与浏览器自动化**错峰**：等浏览器任务完全收尾、tab 连接关闭后再启动 whisper
- 批量处理每条之间歇 15s；每条启动前查内存水线，可用内存 < 2.5G 就先等
- LLM 调用走远程 API，本地几乎零负载，可放心用它们分担本地压力

## 依赖

- `ffmpeg`（抽帧）、`yt-dlp`（下载）、Python 3
- [whisper.cpp](https://github.com/ggml-whisper/whisper.cpp) 的 `whisper` CLI（或任何 `--model/--output_format` 兼容的 CLI）
- 可选：多模态图像理解（读帧证据用，没有则人工看帧）
