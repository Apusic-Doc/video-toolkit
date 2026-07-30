# 🎬 Video Toolkit

> 产品演示录屏自动化工具链 — 从原始录屏到多语言成片，一键完成。支持幻灯片模式，截图+解说文字自动生成演示视频。

[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)]()
[![Python](https://img.shields.io/badge/python-3.10%2B-blue)]()

## ✨ 功能

- 🎙️ **语音识别** — Whisper / SenseVoice 自动提取录屏语音，生成 SRT 字幕
- 🤖 **AI 配音** — edge-tts 神经语音，中英文自然度接近真人，段间静默严格对齐
- 🎞️ **自动化录制** — Playwright 驱动真实浏览器 + 终端，脚本化走完整个演示流程并录屏
- 🔥 **字幕硬烧录** — 真烧进画面（libass），字体/字号/颜色/描边/位置可配，非外挂 `.srt`
- ⏱️ **配音手工偏移** — `dub_offset` 微调配音相对画面的整体快慢，字幕同步跟着偏移
- 🖥️ **可视化管理台（`vt ui`）** — 网页里改封面/字体/语音/字幕，点击试听/放大预览，跑任务看实时日志（⭐ 新）
- 📸 **幻灯片生成** — 截图 + 解说 → 自动配音合成演示视频
- 🎬 **通用合成器** — 封面/封底/BGM，录屏和幻灯片共用
- 🌐 **多语言翻译** — DeepSeek API 自动翻译字幕，一键英文版
- ⚙️ **meta.json 三级配置** — 项目 / Feature / 单页三层合并，字体语音配色一处统一
- 🔧 **模块化管道** — 字幕提取 / AI配音 / 视频合成 / 烧字幕 各自独立，可单步重跑
- ⚡ **硬件加速** — videotoolbox 硬件编码，2 分钟 ~15 秒出片
- 📊 **状态管理** — 一键查看全部 feature 进度

## 📦 安装

```bash
curl -sSf https://video-toolkit.bitey.ai/install.sh | bash
```

安装后全局可用。`samples/` 目录包含示例项目，无需录制即可体验：

```bash
cd samples && vt all feature-01-demo
```

## 🔄 升级

```bash
vt upgrade
```

`vt ui` 是单独的前端/后端子项目，升级完仓库代码后第一次运行 `vt ui` 会自动检测依赖/源码是否比
上次新，需要就自动重新 `npm install` + build，不用手动操作。

## 🚀 快速开始

```bash
# 1. 录制（Mac Cmd+Shift+5）→ 保存到 feature 目录: recording.mov

# 2. 一键出片
vt all 01

# 3. 试听 AI 配音
vt play 01 dub

# 4. 调整字幕后重新合成
vt dub 01    # 重生成 AI 配音（试听）
vt mix 01    # 合成最终视频
```

## 🖥️ 可视化管理台（`vt ui`）

不想手改 `meta.json`/`subtitles.srt` 的话，用网页版：

```bash
vt ui              # 打开首页
vt ui 01           # 直接定位到某个 feature
```

首次运行会自动装依赖、build 前端，之后改过前端源码也会自动检测重新 build。功能：

- **封面 / 配置**：标题、副标题、配音偏移常驻显示；字体/字号/配色/BGM/Logo 等收进「高级设置」，封面改一项就实时重新渲染预览
- **字幕**：逐条编辑文案和时间码，「保存并生效」自动把重新配音→重新烧字幕串起来跑
- **字体 / 语音选择**：字体点小图放大看真实渲染效果，语音点击直接试听样例（不用先合成整条视频）
- **任务 / 预览**：常用操作（录制、一键生效、状态检查）默认可见，单步命令和英文版流水线收进「高级操作」；配音/成片/英文版都能直接在页面里听/看
- **项目设置**：字体/字号/语音/封面配色这些"整个项目该统一"的默认值，一处改全项目 feature 生效
- **说明**：直接看每个 feature 的 `README.md`

**安全**：不设 `VT_UI_PASSWORD` 环境变量时只允许本机访问；`vt record` / `vt codegen` 这类会真实操控本机屏幕的命令，不管有没有设密码，都只允许本机/内网触发——发布到公网也不会有人能远程摆弄你的屏幕，最多看看任务日志和进度。

```bash
export VT_UI_PASSWORD=your-password   # 需要远程/公网访问再设
```

## 📸 幻灯片模式（v2）

截图 + 解说文字 → 自动配音合成演示视频：

```bash
feature-XX-slides/slides/
├── 01.png               # 截图
├── 02.png
├── 03.png
└── narration.txt        # 每行一段解说

vt slide feature-XX-slides
```

## 📋 完整命令

| 命令 | 说明 | 依赖 |
|---|---|---|
| `vt ui [XX]` | **可视化管理台**，不带参数打开首页，带参数直接定位 feature | Node.js |
| `vt codegen XX` | 弹出真实浏览器，手动走一遍管控台操作路径，选择器存到 `nav-draft.spec.js`（本机专用） | Playwright |
| `vt record XX` | 按 `record.spec.js` 自动跑一遍并录屏（本机专用） | Playwright |
| `vt sync XX` | 把 `nav-draft.spec.js` 的选择器同步合并进 `record.spec.js` | — |
| `vt all XX` | 全流程: 字幕 → AI配音 → 合成（自动检测 slide/video，**不烧字幕**） | ffmpeg + whisper |
| `vt srt XX` | 仅提取字幕 | whisper |
| `vt dub XX` | 仅生成 AI 配音 (试听) | edge-tts |
| `vt redub XX` | 复用已有录屏，重新配音 + 合成（改完字幕/meta 后最常用） | edge-tts + ffmpeg |
| `vt mix XX` | 合成视频 + 可选 cover/outro/bgm（v2） | ffmpeg |
| `vt burn XX` | **烧录字幕**到已合成的成片（真烧进画面，不是外挂字幕） | ffmpeg-full (libass) |
| `vt slide XX` | 幻灯片模式（v2） | edge-tts + ffmpeg |
| `vt trans XX` | 翻译字幕: 中文 → 英文 | DeepSeek API |
| `vt en XX` | **英文全流程** | whisper + DeepSeek + edge-tts |
| `vt dub-en XX` | 仅生成英文配音 | edge-tts |
| `vt mix-en XX` | 仅合成英文视频 | ffmpeg |
| `vt cover XX` | 单独重新渲染封面 | ImageMagick |
| `vt play XX dub` | 播放中文配音 | afplay |
| `vt play XX final` | 播放成片 | QuickTime |
| `vt status XX` | 查看状态 | — |
| `vt status --all` | 查看全部 feature 状态 | — |
| `vt config` | 查看配置 | — |
| `vt config KEY=val` | 设置配置 | — |
| `vt config list voice` | 列出可用语音 | — |
| `vt config list asr` | 列出 ASR 引擎 | — |
| `vt --version` | 查看版本 | — |
| `vt upgrade` | **升级**到最新版（`git pull`） | git |

## 🏗️ 架构

```
recording.mov / slides/
        │
   load_meta() → detect_type()
        │
   ┌────┴────┐
   ▼         ▼
 video     slide
   │         │
   │    build_pages()
   │    gen_slide_video()
   │         │
   └────┬────┘
        ▼
  compose_final(content, meta)
   ├── cover (图片/视频)
   ├── content (dubbed or slides)
   ├── outro (图片/视频)
   ├── bgm  (循环/截断/混音)
   └── final.mp4
```

## 📁 约定文件结构

```
project/
├── meta.json                   ← 项目级默认配置（v2）
├── resources/
│   ├── bgm.mp3
│   ├── cover.png
│   └── outro.png
│
├── feature-01-name/
│   ├── meta.json               ← Feature 配置（v2，可选，覆盖项目级）
│   ├── record.spec.js          ← 自动化录制脚本（Playwright）
│   ├── recording.mov           ← 录屏
│   ├── slides/                 ← 幻灯片（v2）
│   │   ├── 01.png + 01.txt
│   │   └── narration.txt
│   ├── subtitles.srt
│   ├── ai_dub.wav
│   ├── ai_dub_en.wav
│   ├── feature-01-name.mp4          ← 带封面成片
│   ├── feature-01-name-no-cover.mp4 ← 不带封面（画面+配音）
│   ├── feature-01-name-sub.mp4      ← 带封面+烧录字幕（vt burn 产出）
│   ├── feature-01-name-no-cover-sub.mp4
│   └── feature-01-name_en.mp4       ← 英文版
```

### meta.json 常用字段

| 字段 | 默认 | 说明 |
|---|---|---|
| `title` / `subtitle` | — | 封面标题/副标题（内容层，一般只在 Feature 级设置） |
| `company` | — | 封面底部公司名 |
| `logo` | 自动探测 `resources/logo.png` | 封面左上角 Logo，保留原色 |
| `cover_accent_color` | `#222222` | 封面标题强调色，跟产品/品牌配色统一时用 |
| `cover_duration` | 3 | 封面停留秒数 |
| `bgm` | 关闭 | 背景音乐，必须显式 `true`/给路径才启用，不会因为 `resources/bgm.mp3` 存在就自动混入 |
| `subtitle_style.font_name` | PingFang SC | 字幕字体（真实系统字体名，如 Heiti SC / Songti SC / Kaiti SC） |
| `subtitle_style.font_size` / `margin_v` | 44 / 45 | 字幕字号 / 下边距（真实像素，所见即所得） |
| `subtitle_style.color` / `outline` | 白字黑边 | ASS 格式 `&HAABBGGRR`（`vt ui` 里用取色器改，自动转换） |
| `dub_offset` | 0 | 配音相对画面整体快/慢多少秒（负数=配音提前，正数=配音延后），`vt burn` 时字幕会跟着同步偏移 |

## 🎙️ AI 语音

### 中文

| 语音 | 风格 |
|---|---|
| `zh-CN-XiaoxiaoNeural` ★ | 温暖清晰，默认 |
| `zh-CN-YunyangNeural` | 专业可靠 |
| `zh-CN-YunjianNeural` | 激情有力 |
| `zh-CN-YunxiNeural` | 活泼阳光 |
| `zh-CN-XiaoyiNeural` | 可爱轻快 |

### 英文

| 语音 | 风格 |
|---|---|
| `en-US-AvaNeural` ★ | 清晰亲和，默认 |
| `en-US-AriaNeural` | 自信 |
| `en-US-ChristopherNeural` | 权威 |
| `en-GB-SoniaNeural` | 英式女声 |
| `en-GB-RyanNeural` | 英式男声 |

## 🔧 配置管理

```bash
vt config                          # 查看全部
vt config DEEPSEEK_API_KEY=sk-xxx  # API Key
vt config VIDEO_ASR=funasr         # ASR 引擎
vt config VIDEO_VOICE=zh-CN-YunyangNeural
vt config VIDEO_BURN_SUB=0         # 关闭字幕烧录
```

| 配置项 | 默认 | 说明 |
|---|---|---|
| `DEEPSEEK_API_KEY` | — | 翻译 API Key |
| `VIDEO_ASR` | faster-whisper | ASR 引擎 |
| `VIDEO_VOICE` | zh-CN-XiaoxiaoNeural | 中文 AI 语音 |
| `VIDEO_VOICE_EN` | en-US-AvaNeural | 英文 AI 语音 |
| `VIDEO_BURN_SUB` | 0 | 字幕烧录开关 |

> v2 完整 meta.json 配置见 [docs/SPEC.md](docs/SPEC.md)

## 🧩 组件与依赖

| 组件 | 用途 | 许可 |
|---|---|---|
| [Whisper](https://github.com/openai/whisper) | 语音识别 | MIT |
| [edge-tts](https://github.com/rany2/edge-tts) | 神经语音合成 | GPLv3 |
| [FFmpeg](https://ffmpeg.org) | 音视频处理 | LGPL |
| [DeepSeek API](https://platform.deepseek.com) | 中英翻译 | 付费 |

## ❓ FAQ

### 模型下载太慢

`export HF_ENDPOINT=https://hf-mirror.com` 或用 `VIDEO_ASR=funasr` 切换 SenseVoice。

### 字幕烧不进视频 / `vt burn` 报错找不到 ffmpeg-full

标准 `brew install ffmpeg` 不带 libass，烧不了字幕。装完整版：

```bash
brew install ffmpeg-full   # keg-only，不会覆盖/影响你现有的 ffmpeg
vt burn 01                 # 对 xxx.mp4 / xxx-no-cover.mp4 各产出一份 -sub.mp4，原文件不动
```

### 配音和画面/字幕不同步

先确认是不是单纯没有实测过配音真实时长（`record.spec.js` 里按估算值停留会有落差，改成实测真实
edge-tts 时长最准）。如果只是整体感觉配音快了/慢了几秒，不用重录，直接调 `dub_offset`：

```json
{ "dub_offset": -2 }
```

```bash
vt redub 01 && vt burn 01   # 或在 vt ui 里改完点"一键生效"
```

### `vt ui` 打不开 / 页面报错找不到某个模块

八成是前端依赖装完之后没重新 build。正常情况下 `vt ui` 会自动检测 `package.json` 比
`node_modules`/`dist` 新就自动重装+重build，不需要手动干预；如果还是不行，手动清一次缓存：

```bash
rm -rf ~/.local/share/video-toolkit/ui-client/{node_modules,dist}
vt ui
```

### DeepSeek API Key

```bash
vt config DEEPSEEK_API_KEY=sk-xxx
```

### 查看可用 AI 语音

```bash
vt config list voice
```

### 试听 AI 配音

```bash
vt play 01 dub
```

### 幻灯片如何配置封面和 BGM

参考 `docs/SPEC.md` — 完整的 meta.json 三级配置说明。

## 🌐 GitHub Pages

`https://video-toolkit.bitey.ai`

## 🔒 开发规范

- **严禁客户信息**：代码、文档、commit 中不得出现客户名称、项目代号
- **commit 前检查**：`grep -rn "关键词" .` 确保零残留

## 📄 License

Apache 2.0
