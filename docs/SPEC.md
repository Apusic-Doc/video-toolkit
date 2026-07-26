# Video Toolkit v2 功能规格说明书

## 1. 配置系统

### 1.1 三级优先级

```
pages[N] > feature/meta.json > project/meta.json > 内置默认
   1              2                    3               4
```

- **project/meta.json** — 设一次，所有 feature 继承
- **feature/meta.json** — 只覆盖差异项
- **pages[N]** — 单页覆盖（语音、时长、过渡效果）

### 1.2 目录结构

```
project/
├── meta.json                   ← 项目级默认配置
├── resources/                  ← 全局共享资源
│   ├── bgm.mp3
│   ├── logo.png
│   ├── cover.png
│   └── outro.png
├── feature-01-name/
│   ├── meta.json               ← Feature 配置（只写差异）
│   ├── recording.mov           ← 录屏模式
│   ├── slides/                 ← 幻灯片模式
│   │   ├── 01.png + 01.txt
│   │   └── 02.png + 02.txt
│   ├── cover.png
│   ├── bgm.mp3
│   └── subtitles.srt
└── ...
```

---

## 2. meta.json 完整 Schema

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

  "subtitle": { "mode": "auto", "burn": false },
  "subtitle_style": {
    "font_size": 22,
    "color": "&H00FFFFFF",
    "outline": "&H00000000"
  },

  "slides": {
    "mode": "auto",
    "page_duration": 3,
    "page_padding": 1.5,
    "transition": "fade",
    "zoom": "none",
    "pages": []
  }
}
```

### 2.1 字段说明

**顶层**

| 字段 | 默认 | 说明 |
|---|---|---|
| `type` | `auto` | `auto` / `video` / `slide` |
| `voice` | Xiaoxiao | 中文 AI 语音 |
| `voice_en` | Ava | 英文 AI 语音 |
| `cover` | null | 封面路径（相对 project 根），null=不启用 |
| `outro` | null | 封底路径，null=不启用 |
| `cover_duration` | 3 | 封面静态图展示秒数（视频封面忽略） |
| `bgm` | null | 背景音乐路径（相对 project 根） |
| `bgm_volume` | 0.15 | BGM 音量 0~1 |
| `bgm_loop` | true | BGM 短于视频时循环 |
| `resolution` | 1920x1080 | 输出分辨率 |
| `logo` | null | 水印图片路径 |
| `logo_position` | bottom-right | 水印位置 |

**slides**

| 字段 | 默认 | 说明 |
|---|---|---|
| `mode` | `auto` | `auto`(文件检测) / `manual`(只按 pages) |
| `page_duration` | 3 | 无 text 时的默认展示秒数 |
| `page_padding` | 1.5 | 解说结束后额外停留秒数 |
| `transition` | fade | 默认过渡效果 |
| `pages` | [] | 逐页配置，空=自动推导 |

**pages[N]**

```json
{ "image": "01.png", "text": "解说词", "duration": 5,
  "voice": null, "page_padding": null, "transition": null, "zoom": null }
```

---

## 3. 架构：统一合成器

```
vt all / mix / slide
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
   │
   ├── cover     (图片/视频)
   ├── content   (video 或 slide 生成)
   ├── outro     (图片/视频)
   ├── bgm       (叠加混音)
   └── logo      (水印叠加)
        │
        ▼
    final.mp4
```

**核心理念**：video 和 slide 只负责生成"内容段"，封面/BGM/封底全由 `compose_final` 统一处理，零重复代码。

---

## 4. 幻灯片处理

### 4.1 build_pages

```python
if meta.slides.pages:
    pages = meta.slides.pages           # 以配置为准
else:
    pages = detect_pages(slide_dir)    # 文件系统自动推导
```

### 4.2 解说文本三级回退

当 `page.text` 为空时：

1. 配对文件：`01.png` → `01.txt`
2. `narration.txt`：第 N 行对应第 N 页
3. 都没有 → warn，该页静默展示 `page_duration` 秒

首次读取后缓存内存，后续页直接命中。

### 4.3 页间切换

- 有 `text` → 展示时长 = 解说实际时长 + `page_padding`
- 无 `text` → 展示时长 = `page_duration`
- 说完 + `page_padding` 后 → 切下一页

### 4.4 生成内容段

逐页：edge-tts 配音 + 图片 = 视频片段。拼接所有片段 = 内容段视频。

---

## 5. 错误处理

| 场景 | 行为 |
|---|---|
| 资源文件不存在 | warn + **继续**，不阻断 |
| pages 图片找不到 | warn + 跳过该页 |
| BGM 文件不存在 | warn + 无 BGM |
| meta.json 语法错误 | warn + 用内置默认 |
| 无 meta.json | 完全向后兼容 |

---

## 6. 兼容性

- 无 meta.json → 行为完全不变
- 有 meta.json 但 `type: "auto"` → 老流程 + 可选 cover/outro/bgm
- 老用户零影响

---

## 7. 开发计划

| Phase | 内容 | 行数 |
|---|---|---|
| 1 | `lib/meta.sh`：三级合并 + type 检测 + 资源查找 | ~150 |
| 2 | `compose_final`：通用合成器（cover/outro/bgm/logo） | ~120 |
| 3 | `lib/slides.sh`：build_pages + 解说回退 + 内容段生成 | ~180 |
| 4 | 字幕增强：subtitle.mode | ~30 |
| 5 | 入口整合：vt all/slide/mix 统一接入 | ~50 |
| 6 | 文档 + samples 示例 | — |

**本期不做**：复杂 transition / zoom / logo 水印 / subtitle_style

---

## 8. 与现有 vt 命令关系

| 命令 | v2 行为 |
|---|---|
| `vt all 01` | load_meta → detect_type → 生成内容段 → compose_final |
| `vt slide 01` | 强制 slide 模式 |
| `vt mix 01` | 强制 video 模式 + cover/outro/bgm |
| `vt srt 01` | 不变 |
| `vt dub 01` | 不变 |
| `vt play 01 dub` | 不变 |
| `vt config` | 不变 |
| `vt --version / --update` | 不变 |
