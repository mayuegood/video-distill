# 蒸馏层（distill）

## 硬规则

**输入必须是 verified.txt**。raw.txt 里的错字会原样渗进蒸馏产物的引文——实测发生过（`都江宴`/`禮賓`/`明江` 渗进发布版 DIGEST 的引文块）。如果用户跳过纠错直接要蒸馏，先提醒一次，用户坚持则在产物顶部标注"基于未校验转录"。

## 收尾（必做，prove-it-works）

蒸馏产物写完后，**全量跑一次收尾自检**（完整模式，三层全查）：

```bash
bash "$SKILL_DIR/scripts/verify-output.sh" <out_dir>   # $SKILL_DIR = 本 skill 安装目录
```

exit 0 = 管线（提取→纠错→蒸馏）整体通过，可宣告完成；FAIL = 修复后重跑。
这是管线的**最后一道闸**：同时验证 verified.txt 在蒸馏后仍完好、DIGEST 来源标注在位。
另外 2 项脚本查不了的手动核对（SKILL.md ⑤ 节）：抽查 1 处纠错对应帧、DIGEST 引文逐条 grep verified.txt。

## 优先路径：cangjie-skill（仓颉，可选）

检查是否已装 cangjie-skill。未装可取：

```bash
gh api repos/kangarooking/cangjie-skill/contents/SKILL.md --jq .content | base64 -d
```

把 verified.txt 交给 cangjie，按其 SKILL.md 七阶段执行（Adler 分析 → 并行提取 → 三重验证 → RIA++ → Zettelkasten → 压测 → 交付）。产物：DIGEST.md + 若干可安装 SKILL.md + GLOSSARY.md + INDEX.md。

注意：cangjie 很重（适合 ≥10 分钟、信息密度高的视频）。短视频用下面的 RIA-lite。

## Fallback：RIA-lite（无 cangjie 或短视频）

结构（实测认可的形态）：

```markdown
# <标题> — 精华
> 由 video-distill 蒸馏，只呈现经帧证据校验的内容。

## 这个视频在讲什么（3-5 句，含论证结构）

## 方法论卡片（每张四要素）
### <方法论名>
- 它解决什么问题
- 核心逻辑
- 视频里的用法（引文用 verified.txt 原句，标秒数）
- 什么时候会失效

## 陷阱与反例
（为什么人会掉进去 / 机制 / 预警信号）

## 作者的局限（读这个视频要打的折扣）

## 关键术语速查表（术语 | 作者的用法 | 和常识的差异）

## 如果只带走三句话
```

## 与笔记库联动（可选收尾）

蒸馏完成后可回填你自己的笔记系统（如飞书多维表格 / Notion / Obsidian）：更新对应记录的正文 + 状态改为已读。仅在用户明确要求回填时做。
