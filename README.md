# 🎬 Video Toolkit

> 产品演示录屏自动化工具链 — 从原始录屏到多语言成片，一键完成。支持幻灯片模式，截图+解说文字自动生成演示视频。

[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)]()
[![Python](https://img.shields.io/badge/python-3.10%2B-blue)]()

## ✨ 功能

- 🎙️ **语音识别** — Whisper / SenseVoice 自动提取录屏语音，生成 SRT 字幕
- 🤖 **AI 配音** — edge-tts 神经语音，中英文自然度接近真人，段间静默严格对齐
- 📸 **幻灯片生成** — 截图 + 解说 → 自动配音合成演示视频（⭐ v2）
- 🎬 **通用合成器** — 封面/封底/BGM，录屏和幻灯片共用
- 🌐 **多语言翻译** — DeepSeek API 自动翻译字幕，一键英文版
- ⚙️ **meta.json 配置** — 三级配置（项目/Feature/单页），灵活覆盖
- 🔧 **模块化管道** — 字幕提取 / AI配音 / 视频合成 各自独立
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
| `vt all XX` | 全流程: 字幕 → AI配音 → 合成（自动检测 slide/video） | ffmpeg + whisper |
| `vt srt XX` | 仅提取字幕 | whisper |
| `vt dub XX` | 仅生成 AI 配音 (试听) | edge-tts |
| `vt mix XX` | 合成视频 + 可选 cover/outro/bgm（v2） | ffmpeg |
| `vt slide XX` | 幻灯片模式（v2） | edge-tts + ffmpeg |
| `vt trans XX` | 翻译字幕: 中文 → 英文 | DeepSeek API |
| `vt en XX` | **英文全流程** | whisper + DeepSeek + edge-tts |
| `vt dub-en XX` | 仅生成英文配音 | edge-tts |
| `vt mix-en XX` | 仅合成英文视频 | ffmpeg |
| `vt play XX dub` | 播放中文配音 | afplay |
| `vt play XX final` | 播放成片 | QuickTime |
| `vt status XX` | 查看状态 | — |
| `vt status --all` | 查看全部 feature 状态 | — |
| `vt config` | 查看配置 | — |
| `vt config KEY=val` | 设置配置 | — |
| `vt config list voice` | 列出可用语音 | — |
| `vt config list asr` | 列出 ASR 引擎 | — |
| `vt --version` | 查看版本 | — |
| `vt --update` | 自动更新 | — |

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
│   ├── meta.json               ← Feature 配置（v2，可选）
│   ├── recording.mov           ← 录屏
│   ├── slides/                 ← 幻灯片（v2）
│   │   ├── 01.png + 01.txt
│   │   └── narration.txt
│   ├── subtitles.srt
│   ├── ai_dub.wav
│   ├── ai_dub_en.wav
│   ├── final.mp4
│   └── final_en.mp4
```

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

### 字幕没有烧录到视频

当前 ffmpeg 默认不含 libass。字幕以 `.srt` 外挂，QuickTime/VLC 自动加载。

### 语音和画面不同步

```bash
vt dub 01 && vt mix 01  # 重生成，支持段间静默对齐
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
