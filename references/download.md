# 下载层（download）

## 普通视频链接（首选）

`yt-dlp <url> -o '%(title)s.%(ext)s'`（YouTube/B站/抖音通吃）。

**优先拿官方字幕轨当地面真值**（省一次 whisper，且字幕是人工校对的）：

```bash
yt-dlp --dump-json <url>   # 探 subtitles 字段
# 有则:
yt-dlp --write-sub --sub-lang zh --convert-subs srt <url>
# 字幕转纯文本后预放 <out_dir>/transcript/raw.{srt,txt}, extract.sh 会自动跳过 whisper
```

被平台反制时（只下到废片/限速）：切 yt-dlp client（`--extractor-args "youtube:player_client=android"`）、升级 yt-dlp、或换浏览器方案。

**鉴废片**：`ffprobe` 看时长 >3s 且文件 >500KB 才算真视频（有些平台反爬只给 2 秒废片）。

## 视频号 sph 链接（weixin.qq.com/sph/）

SPA 空壳，curl 拿不到内容，需要真实浏览器渲染。通用做法：

1. 用你手头任何浏览器自动化通道（Playwright / agent 自带浏览器 / 浏览器扩展桥）打开第三方解析站（搜"视频号解析"），或登录态下直接从页面 network 面板抓视频 CDN 直链
2. `curl -L -o video.mp4 "<直链>"` — **直链有时效，拿到立刻下载**
3. **完成后立即关闭所有打开的 tab/会话**（平台风控，连续抓取会累积限速）
4. 每条链接前重新加载解析页（累积状态会触发限速）

⚠ 这一段高度依赖你的本地环境（是否登录、用什么自动化工具），脚本层不固化——按你自己可用的通道实现，并遵守平台条款。

## 版权边界

仅处理你自己拥有或已获授权的内容；批量抓取平台内容前先确认范围合规。
