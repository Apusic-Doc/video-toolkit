# meta.json 设计方案 v2

## 配置优先级

```
per_slide > feature/meta.json > project/meta.json > 内置默认
     1              2                    3               4
```

- **project/meta.json** — 设一次，所有 feature 继承
- **feature/meta.json** — 只覆盖与 feature 不同的项
- **per_slide** — 单页覆盖，如某页用不同语音

## 目录结构

```
project/
├── meta.json                   ← 项目级默认配置
├── resources/                  ← 全局共享资源
│   ├── bgm.mp3
│   ├── logo.png
│   ├── cover.png
│   └── outro.png
│
├── feature-01-name/
│   ├── meta.json               ← Feature 配置（覆盖项目级，只写差异项）
│   ├── recording.mov
│   ├── slides/
│   │   ├── 01.png + 01.txt     ← 配对模式：图片+解说文件
│   │   └── 02.png + 02.txt
│   ├── cover.png               ← Feature 专属封面
│   ├── bgm.mp3                 ← Feature 专属 BGM
│   └── subtitles.srt
│
└── feature-02-name/
    └── ...
```

## meta.json Schema

```json
{
  "type": "auto",

  "voice": "zh-CN-XiaoxiaoNeural",
  "voice_en": "en-US-AvaNeural",

  "cover": null,
  "outro": null,
  "cover_duration": 3,
  "outro_duration": 3,

  "bgm": null,
  "bgm_volume": 0.15,
  "bgm_loop": true,

  "resolution": "1920x1080",
  "fps": 30,
  "logo": null,
  "logo_position": "bottom-right",

  "subtitle": {
    "mode": "auto",
    "burn": false
  },
  "subtitle_style": {
    "font_size": 22,
    "color": "&H00FFFFFF",
    "outline": "&H00000000"
  },

  "slides": {
    "mode": "auto",
    "narration": null,
    "transition": "fade",
    "zoom": "none",
    "per_slide": []
  }
}
```

## 字段说明

### 顶层

| 字段 | 默认 | 说明 |
|---|---|---|
| `type` | `auto` | `auto` / `video` / `slide` |
| `voice` | Xiaoxiao | 中文 AI 语音 ID |
| `voice_en` | Ava | 英文 AI 语音 ID |
| `cover` | null | 封面：图片/视频路径（相对 project 根）。null=不启用 |
| `outro` | null | 封底：图片/视频路径。null=不启用 |
| `cover_duration` | 3 | 封面**静态图**展示秒数。视频封面忽略此值 |
| `outro_duration` | 3 | 封底静态图展示秒数。视频封底忽略此值 |
| `bgm` | null | 背景音乐路径（相对 project 根）。null=不启用 |
| `bgm_volume` | 0.15 | 音量 0.0~1.0 |
| `bgm_loop` | true | BGM 短于视频时是否循环 |
| `resolution` | 1920x1080 | 输出分辨率 |
| `fps` | 30 | 帧率 |
| `logo` | null | 水印图片路径。null=不启用水印 |
| `logo_position` | bottom-right | `top-left` / `top-right` / `bottom-left` / `bottom-right` |

### subtitle

| 字段 | 默认 | 说明 |
|---|---|---|
| `mode` | `auto` | `auto`(检测) / srt路径 / `paired`(slides配对模式) / `null`(不启用) |
| `burn` | false | 是否烧录进视频（需 ffmpeg libass） |

`subtitle_style` 仅在 `burn: true` 时生效。

### slides

| 字段 | 默认 | 说明 |
|---|---|---|
| `mode` | `auto` | `auto`(文件系统检测) / `manual`(只按 per_slide) |
| `narration` | null | 模式 B：单文件每行对应一张图 |
| `transition` | fade | 默认过渡效果 |
| `zoom` | none | 默认 Ken Burns 效果 |
| `per_slide` | [] | 逐页配置。空数组 = 从文件系统自动推导 |

per_slide 结构：
```json
[
  { "image": "01.png", "text": "欢迎", "duration": 4, "transition": "fade", "zoom": null },
  { "image": "02.png", "text": "核心功能", "voice": "zh-CN-YunyangNeural" }
]
```

## 自动检测逻辑

```
vt all 01 / vt mix 01 / vt slide 01
         │
         ▼
    读 feature/meta.json + project/meta.json，深度 merge
         │
         ▼
    type 判断:
    ├─ "video" → 视频模式
    ├─ "slide" → 幻灯片模式
    ├─ "auto":
    │     ├─ recording.mov 存在 ∧ slides/ 不存在 → video
    │     ├─ slides/ 存在 ∧ recording.mov 不存在 → slide
    │     ├─ 两者都有 → 报错提示用户指定 type
    │     └─ 都没有 → 报错
         │
         ▼
    资源查找（封面/封底/BGM）:
    ├─ meta 中显式设了值（包括 null）→ 以 meta 为准（null=不启用）
    ├─ meta 中未设 → 自动检测:
    │     ├─ feature 目录下有 cover.* → 用它
    │     └─ project/resources/cover.* → 用全局默认
         │
         ▼
    per_slide:
    ├─ 非空数组 → 以 per_slide 为准
    └─ 空数组 → 文件系统自动推导（配对模式 or narration.txt 模式）
```

## 错误处理

- 所有资源文件不存在 → **静默跳过 + `warn "xxx 不存在"`**
- cover/outro/bgm/logo 任意一个缺失不阻断流程
- per_slide 中图片找不到 → warn 跳过该页

## 与 vt 命令关系

| 命令 | 行为 |
|---|---|
| `vt all 01` | 读 meta → 检测 type → 对应流程 |
| `vt slide 01` | 强制 slide 模式 |
| `vt mix 01` | 强制 video 模式 + cover/outro/bgm |
| `vt srt 01` | 不变 |
| `vt dub 01` | 不变 |

## 兼容性

- 无任何 meta.json → 行为完全不变
- 有 meta 但 `type: "auto"` → 行为不变 + 可选 cover/outro/bgm
- 老用户零影响
