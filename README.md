# 🎬 Video Toolkit

> 产品演示录屏自动化工具链 — 从原始录屏到多语言成片，一键完成。

[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)]()
[![Python](https://img.shields.io/badge/python-3.10%2B-blue)]()

## ✨ 功能

- 🎙️ **语音识别** — Whisper / SenseVoice 自动提取录屏语音，生成带时间戳的 SRT 字幕
- 🤖 **AI 配音** — 微软神经语音 edge-tts，中文/英文自然度接近真人，严格对齐时间轴
- 🌐 **多语言翻译** — DeepSeek API 自动翻译字幕，一键生成英文版演示视频
- 🔧 **模块化管道** — 字幕提取 / AI配音 / 视频合成 各自独立，灵活组合
- ⚡ **硬件加速** — Mac videotoolbox 硬件编码，2 分钟视频 ~15 秒出片
- 📊 **状态管理** — 一键查看所有 feature 的录制和出片进度

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

## 📋 完整命令

| 命令 | 说明 | 依赖 |
|---|---|---|
| `vt all XX` | 全流程: 字幕 → AI配音 → 合成 | ffmpeg + whisper |
| `vt srt XX` | 仅提取字幕 | whisper |
| `vt dub XX` | 仅生成 AI 配音 (试听) | edge-tts |
| `vt mix XX` | 仅合成视频 | ffmpeg |
| `vt trans XX` | 翻译字幕: 中文 → 英文 | DeepSeek API |
| `vt en XX` | **英文全流程** | whisper + DeepSeek + edge-tts |
| `vt dub-en XX` | 仅生成英文配音 | edge-tts |
| `vt mix-en XX` | 仅合成英文视频 | ffmpeg |
| `vt play XX dub` | 播放中文配音 | afplay (macOS) |
| `vt play XX final` | 播放中文成片 | QuickTime |
| `vt status XX` | 查看状态 | — |
| `vt status --all` | 查看全部 feature 状态 | — |
| `vt config` | 查看配置 | — |
| `vt config KEY=val` | 设置配置 | — |
| `vt --version` | 查看版本 | — |
| `vt --update` | 自动更新 | — |

## 🏗️ 架构

```
recording.mov (你的原声讲解 + 操作画面)
        │
        ├──→ Whisper/SenseVoice ──→ subtitles.srt (时间轴 + 文字)
        │                                │
        │                          DeepSeek 翻译
        │                                │
        │                          subtitles_en.srt
        │                                │
        ├──→ edge-tts ──→ ai_dub.wav / ai_dub_en.wav
        │
        └──→ ffmpeg (h264_videotoolbox) ──→ final.mp4 / final_en.mp4
```

## 📁 约定文件结构

```
feature-XX-name/
├── recording.mov               # 原始录屏
├── subtitles.srt               # 中文字幕 (自动/手动)
├── subtitles_en.srt            # 英文字幕 (翻译后，可选)
├── ai_dub.wav                  # 中文 AI 配音
├── ai_dub_en.wav               # 英文 AI 配音 (可选)
├── final.mp4                   # 中文成片
└── final_en.mp4                # 英文成片 (可选)
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

> 切换: `vt config VIDEO_VOICE=zh-CN-YunyangNeural`

## 🔧 配置管理

```bash
vt config                              # 查看全部
vt config DEEPSEEK_API_KEY=sk-xxx      # API Key
vt config VIDEO_ASR=funasr             # ASR 引擎
vt config VIDEO_VOICE=zh-CN-YunyangNeural  # 中文语音
vt config VIDEO_VOICE_EN=en-GB-SoniaNeural # 英文语音
vt config VIDEO_BURN_SUB=0             # 关闭字幕烧录
```

配置文件: `~/.config/video-toolkit/config`

| 配置项 | 默认值 | 说明 |
|---|---|---|
| `DEEPSEEK_API_KEY` | — | DeepSeek API Key |
| `VIDEO_ASR` | faster-whisper | ASR 引擎 |
| `VIDEO_VOICE` | zh-CN-XiaoxiaoNeural | 中文 AI 语音 |
| `VIDEO_VOICE_EN` | en-US-AvaNeural | 英文 AI 语音 |
| `VIDEO_BURN_SUB` | 0 | 字幕烧录开关 |
| `VIDEO_SUB_FONTSIZE` | 18 | 字幕字号 |

## 🧩 组件与依赖

| 组件 | 用途 | 许可 |
|---|---|---|
| [Whisper](https://github.com/openai/whisper) | 语音识别 → 字幕 | MIT |
| [edge-tts](https://github.com/rany2/edge-tts) | 微软神经语音合成 | GPLv3 |
| [FFmpeg](https://ffmpeg.org) | 音视频处理 / 合成 | LGPL |
| [DeepSeek API](https://platform.deepseek.com) | 中英翻译 | 付费 |
| macOS `say` | TTS 回退方案 | 内置 |

## ❓ FAQ

### "Warning: You are sending unauthenticated requests to the HF Hub"

Whisper 模型托管在 HuggingFace。不影响功能，只下载一次后缓存。可设 `export HF_TOKEN=hf_xxx` 提速。

### 模型下载太慢 / 失败

- 设 HF 镜像: `export HF_ENDPOINT=https://hf-mirror.com`
- 手动下载: `curl -L -o ~/.cache/whisper/small.pt <url>`
- 换 SenseVoice (国内满速): `pip3 install funasr-onnx modelscope`

### faster-whisper / edge-tts 不可用

```bash
pip3 install faster-whisper
python3 -m venv .venv && .venv/bin/pip install edge-tts
```

### 中文识别不够准确

`vt config VIDEO_ASR=funasr` 切换到 SenseVoice（需先安装），或修改脚本中 Whisper 模型从 `small` → `medium`。

### DeepSeek API Key 配置

```bash
vt config DEEPSEEK_API_KEY=sk-xxx
```

### 如何试听 AI 配音？

```bash
vt play 01 dub
```

### 字幕没有烧录到视频

当前 ffmpeg 版本默认不含 libass。字幕以 `.srt` 文件外挂，QuickTime/VLC 自动加载。需要内嵌可用 iMovie/剪映手动添加。

### 合成速度太慢

Mac 默认使用硬件编码 `h264_videotoolbox`，2 分钟视频约 15 秒出片。如要更高画质可切换回软编码（慢 5-8 倍）。

### 语音和画面不同步

```bash
vt dub 01 && vt mix 01    # 重生成即可，支持段间静默对齐
```

## 🌐 GitHub Pages

`https://video-toolkit.bitey.ai`

---

## 🔒 开发规范

- **严禁客户信息**：代码、文档、commit 中不得出现客户名称、项目代号
- **commit 前检查**：`grep -rn "关键词" .` 确保零残留

## 📄 License

Apache 2.0
