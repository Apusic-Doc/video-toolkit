# 🎬 Video Toolkit

> 产品演示录屏自动化工具链 — 从原始录屏到多语言成片，一键完成。

[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)]()
[![Python](https://img.shields.io/badge/python-3.10%2B-blue)]()

## ✨ 功能

- 🎙️ **语音识别** — Whisper 自动提取录屏中的语音，生成带时间戳的 SRT 字幕
- 🤖 **AI 配音** — 微软神经语音 edge-tts，中文/英文自然度接近真人
- 🌐 **多语言翻译** — DeepSeek API 自动翻译字幕，一键生成英文版视频
- 🔧 **模块化管道** — 字幕提取 / AI配音 / 视频合成 各自独立，灵活组合
- 📊 **状态管理** — 一键查看所有 feature 的录制和出片进度

## 📦 安装

```bash
git clone https://github.com/Apusic-Doc/video-toolkit.git
cd video-toolkit

# Prerequisites: Python 3.10+ (pre-installed on macOS)

# Install dependencies
brew install ffmpeg
pip3 install faster-whisper

# Set up edge-tts neural TTS engine
python3 -m venv .venv
.venv/bin/pip install edge-tts
```

## 🚀 快速开始

```bash
# 1. 录制（Mac Cmd+Shift+5）
#    → 终端操作 + 自然讲解
#    → 保存: feature-05/recording.mov

# 2. 一键出片
./video-toolkit.sh all 05

# 3. 试听 AI 配音
afplay ../feature-05-name/ai_dub.wav

# 4. 调整字幕后重新合成
./video-toolkit.sh dub 05   # 重生成 AI 配音（试听）
./video-toolkit.sh mix 05   # 合成最终视频
```

## 📋 完整命令

| 命令 | 说明 | 依赖 |
|---|---|---|
| `all 05` | 全流程: 字幕 → AI配音 → 合成 | ffmpeg + whisper |
| `srt 05` | 仅提取字幕 | whisper |
| `dub 05` | 仅生成 AI 配音 (试听) | edge-tts / say |
| `mix 05` | 仅合成视频 | ffmpeg |
| `trans 05` | 翻译字幕: 中文 → 英文 | DeepSeek API |
| `en 05` | **英文全流程** | whisper + DeepSeek + edge-tts |
| `dub-en 05` | 仅生成英文配音 | edge-tts |
| `mix-en 05` | 仅合成英文视频 | ffmpeg |
| `status 05` | 查看单个 feature 状态 | 无 |
| `status --all` | 查看全部 feature 状态 | 无 |

## 🏗️ 架构

```
recording.mov (你的原声讲解 + 操作画面)
        │
        ├──→ Whisper 识别 ──→ subtitles.srt (时间轴 + 文字)
        │                          │
        │                    DeepSeek 翻译
        │                          │
        │                    subtitles_en.srt
        │                          │
        ├──→ edge-tts ──→ ai_dub.wav / ai_dub_en.wav
        │
        └──→ ffmpeg 合成 ──→ final.mp4 / final_en.mp4
```

## 📁 约定文件结构

```
feature-05-cli-offline-config/
├── recording.mov        ← 你录制的原始视频
├── subtitles.srt        ← 中文字幕 (自动/手动)
├── subtitles_en.srt     ← 英文字幕 (翻译后)
├── ai_dub.wav           ← 中文 AI 配音
├── ai_dub_en.wav        ← 英文 AI 配音
├── final.mp4            ← 中文成片
└── final_en.mp4         ← 英文成片
```

## 🎙️ 语音选择

### 中文 (edge-tts)

| 语音 | 风格 |
|---|---|
| `zh-CN-XiaoxiaoNeural` ★ | 温暖清晰，默认 |
| `zh-CN-YunyangNeural` | 专业可靠 |
| `zh-CN-YunjianNeural` | 激情有力 |
| `zh-CN-YunxiNeural` | 活泼阳光 |
| `zh-CN-XiaoyiNeural` | 可爱轻快 |

### 英文 (edge-tts)

| 语音 | 风格 |
|---|---|
| `en-US-AvaNeural` ★ | 清晰亲和，默认 |
| `en-US-AriaNeural` | 自信 |
| `en-US-ChristopherNeural` | 权威 |
| `en-GB-SoniaNeural` | 英式女声 |
| `en-GB-RyanNeural` | 英式男声 |

> 切换: 编辑 `video-toolkit.sh` 顶部 `VOICE` / `VOICE_EN` 变量。

## 🔑 配置 DeepSeek API Key (翻译功能)

```bash
# 仅本机，不会被提交到 git
echo 'sk-xxxxxxxxxxxxx' > ~/.aas_deepseek_key
chmod 600 ~/.aas_deepseek_key

# 或使用环境变量
export DEEPSEEK_API_KEY=sk-xxxxxxxxxxxxx
```

## 🧩 组件与依赖

| 组件 | 用途 | 许可 |
|---|---|---|
| [Whisper](https://github.com/openai/whisper) | 语音识别 → 字幕 | MIT |
| [edge-tts](https://github.com/rany2/edge-tts) | 微软神经语音合成 | GPLv3 |
| [FFmpeg](https://ffmpeg.org) | 音视频处理 / 合成 | LGPL |
| [DeepSeek API](https://platform.deepseek.com) | 中英翻译 | 付费 |
| macOS `say` | TTS 回退方案 | 内置 |

## 🌐 GitHub Pages

```
https://video-toolkit.bitey.ai
```

## ❓ FAQ

### 如何试听 AI 配音效果？

```bash
afplay feature-XX-name/ai_dub.wav
```

不满意可调整 `subtitles.srt` 后重新生成：`./video-toolkit.sh dub XX`

### "Warning: You are sending unauthenticated requests to the HF Hub"

Whisper 模型托管在 HuggingFace。这个警告不影响功能，只是下载速度稍慢。两种处理方式：

1. **忽略**（推荐）— 模型只下载一次，缓存后不再出现
2. **设 Token** — `export HF_TOKEN=hf_xxxxxxxx` 提升速率

### "faster-whisper not found" / edge-tts 不可用

```bash
pip3 install faster-whisper
python3 -m venv .venv && .venv/bin/pip install edge-tts
```

### 中文识别不够准确

在 `video-toolkit.sh` 中将 Whisper 模型从 `small` 改为 `medium` 或 `large`（更准但更慢、更占内存）。

### DeepSeek API Key 在哪设置

```bash
echo 'sk-xxxxxxxxxxxxx' > ~/.aas_deepseek_key
chmod 600 ~/.aas_deepseek_key
```

脚本自动读取，不需要每次设环境变量。

## 📄 License

Apache 2.0

---

## 🔒 开发规范

- **严禁客户信息**：代码、文档、commit 中不得出现客户名称、项目代号等敏感信息。使用通用示例路径。
- **commit 前检查**：`grep -rn "关键词" .` 确保零残留。
