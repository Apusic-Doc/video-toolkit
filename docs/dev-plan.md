# Video Toolkit v2 开发计划（统一架构版）

## 核心架构

```
Phase 1: meta 引擎
    │
    ├──→ video 模式 ──→ recording.mov + dub = 内容段
    │                         │
    └──→ slide 模式 ──→ pages[] + dub = 内容段
                              │
                    Phase 2: 通用合成器
                    ┌─────────┼─────────┐
                    │  封面    内容段    封底  │
                    │         BGM           │
                    │       Watermark       │
                    └──────────────────────┘
                              │
                         final.mp4
```

**关键**：Phase 2 合成器 = 唯一输出入口。video/slide 只负责生成"内容段"，然后交给合成器统一处理。

---

## Phase 1: meta.json 引擎

- `lib/meta.sh`：三级合并 + type 检测 + 资源查找
- 无 meta 时向后兼容
- ~150 行

## Phase 2: 通用合成器（共享核心）

- `compose_final(content_segment, meta)` — 唯一输出函数
- 输入：内容段视频 + meta 配置
- 输出：带 cover + outro + BGM + watermark 的 final.mp4
- 替换现有 `compose()` 和 `compose_en()`
- ~120 行

### 2.1 内容段生成：video 模式

- 现有 `srt_to_dub()` + `ffmpeg` 替换音频 → 内容段
- **调整**：去掉现有 compose 中的合成逻辑，只生成"内容段"临时文件

### 2.2 内容段生成：slide 模式

- `build_pages()` — 从 meta.pages 或文件系统推导
- 三级解说回退（配对 txt → narration.txt → 跳过）
- 每页：图片 + AI 配音 = 视频片段，`page_duration` 控制最短/最长
- 拼接全部片段 → 内容段
- ~150 行

### 2.3 页间切换规则

- 有 `text` → 解说时长 = 该页展示时长
- 无 `text` → 用 `page_duration`（默认 3s）
- 解说结束 + 0.5s 过渡 → 切下一页

---

## Phase 3: 字幕增强

- `subtitle.mode`：auto / paired / null
- `subtitle_style` 先跳过

## Phase 4: 入口整合

- `vt all` → load_meta → detect_type → 生成内容段 → compose_final
- `vt slide` / `vt mix` 强制模式

## Phase 5: 文档

- README / landing page / samples

---

## 不做（本期）

- transition 复杂效果（只做 cut）
- zoom / Ken Burns
- logo 水印
- subtitle_style

---

## 对比旧计划

| | 旧 | 新 |
|---|---|---|
| compose 逻辑 | video/slide 各自实现 | **合成器统一**，只换内容段 |
| 代码重叠 | cover/outro/bgm 写两遍 | **一次搞定** |
| slide 页间切换 | 无定义 | `text 时长` / `page_duration` |
