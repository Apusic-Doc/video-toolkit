# meta.json 设计方案

## 目录结构

```
project/
├── meta.json                   ← 2️⃣ 项目级默认配置
├── resources/                  ← 全局共享资源
│   ├── bgm.mp3
│   ├── logo.png
│   ├── cover.png
│   └── outro.png
│
├── feature-01-name/
│   ├── meta.json               ← 1️⃣ Feature 配置（覆盖项目级）
│   ├── recording.mov
│   ├── slides/
│   │   ├── 01.png + 01.txt
│   │   └── 02.png + 02.txt
│   ├── cover.png               ← Feature 专属封面
│   ├── bgm.mp3                 ← Feature 专属 BGM
│   └── subtitles.srt
│
└── feature-02-name/
    └── ...
```

## 配置优先级

```
per_slide > feature meta.json > project meta.json > 内置默认值
     1              2                    3               4
```

- **project/meta.json** — 设一次，所有 feature 继承。如 `voice`、`bgm`、`resolution`。
- **feature/meta.json** — 只覆盖与本 feature 不同的项。如换一种 BGM。
- **per_slide** — 单页覆盖，如某一页用不同语音。

## meta.json 完整 Schema

```json
{
  "type": "auto",

  "voice": "zh-CN-XiaoxiaoNeural",
  "voice_en": "en-US-AvaNeural",

  "cover": null,
  "outro": null,
  "cover_duration": 3,
  "outro_duration": 3,

  "bgm": "../resources/bgm.mp3",
  "bgm_volume": 0.15,

  "resolution": "1920x1080",
  "fps": 30,
  "logo": null,

  "subtitle": {
    "source": "auto",
    "burn": false,
    "font_size": 22,
    "color": "&H00FFFFFF",
    "outline": "&H00000000"
  },

  "slides": {
    "source": "auto",
    "images": [],
    "narration": "narration.txt",
    "transition": "fade",
    "zoom": "none",
    "per_slide": []
  }
}
```

| 属性 | 默认 | 说明 |
|---|---|---|
| `type` | `auto` | `auto` / `video` / `slide` / `mixed` |
| `voice` / `voice_en` | 全局默认 | AI 语音 |
| `cover` | null | 封面：图片/视频路径，null=不启用 |
| `outro` | null | 封底：图片/视频路径 |
| `cover_duration` | 3 | 封面静态图展示秒数 |
| `bgm` | `../resources/bgm.mp3` | 背景音乐路径（跨平台相对路径） |
| `bgm_volume` | 0.15 | BGM 音量 0~1 |
| `resolution` | 1920x1080 | 输出分辨率 |
| `fps` | 30 | 帧率 |
| `logo` | null | 水印图片路径 |
| `subtitle.source` | `auto` | `auto` / srt文件 / null(不启用) |
| `subtitle.burn` | false | 是否烧录进视频 |
| `slides.source` | `auto` | `auto`(检测) / `paired`(配对模式) / `single`(narration.txt) / `meta`(per_slide) |
| `slides.images` | [] | 手动指定图片列表（覆盖 auto） |
| `slides.per_slide` | [] | 方案 B 逐页配置 |

## 自动检测逻辑

```
vt all 01 / vt mix 01 / vt slide 01
         │
         ▼
    读 meta.json?
    ├─ 有 → 按 type 字段
    └─ 无 → 自动检测:
              ├─ 有 slides/ → slide 模式
              ├─ 有 recording.mov → video 模式
              ├─ 两者都有 → 提示指定 type
              └─ 都没有 → 报错
         │
         ▼
    封面/封底:
    ├─ meta.cover 指定 → 用它
    ├─ feature 目录下有 cover.png/mp4 → 用它
    └─ ../resources/cover.png → 用全局默认
         │
         ▼
    BGM:
    ├─ meta.bgm 指定 → 用它
    ├─ feature 目录下有 bgm.mp3 → 用它
    └─ ../resources/bgm.mp3 → 用全局默认
```

## 与现有 vt 命令的关系

| 命令 | 行为 |
|---|---|
| `vt all 01` | 检测 type → 跑对应流程（如果 auto 且只有 recording.mov，跟现在一样） |
| `vt slide 01` | 强制幻灯片模式 |
| `vt mix 01` | 强制视频模式，同时应用 meta 中的 cover/outro/bgm |
| `vt srt 01` | 跟现在一样 |
| `vt dub 01` | 跟现在一样 |

## per_slide 逐页配置（方案 B 高级模式）

```json
{
  "slides": {
    "per_slide": [
      { "image": "01.png", "text": "欢迎使用", "duration": 4, "transition": "fade" },
      { "image": "02.png", "text": "核心功能", "voice": "zh-CN-YunyangNeural" },
      { "image": "03.png", "text": "谢谢观看", "zoom": "out" }
    ]
  }
}
```

## 兼容性

- 无 meta.json → 完全向后兼容，行为不变
- 有 meta.json 但 `type: "auto"` → 行为不变 + 应用 cover/outro/bgm
- 老用户零影响
