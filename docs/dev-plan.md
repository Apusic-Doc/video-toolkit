# Video Toolkit v2 开发计划

基于 `docs/meta-design.md` 实现。

## Phase 1: meta.json 引擎

- 新增 `lib/meta.sh`：`load_meta(feature_dir)` 三级合并
- `detect_type(feature_dir, meta)` 自动检测 video/slide
- `resolve_asset(feature_dir, meta, key)` 统一资源查找
- 无 meta.json 时完全向后兼容
- 预计 ~150 行

## Phase 2: cover/outro/bgm

- 图片封面用 cover_duration 秒，视频封面用原始时长
- BGM 循环/截断 + 音量控制
- Watermark 图片叠加（先跳过，等 libass 方案）
- 修改 compose() 函数，~100 行

## Phase 3: 幻灯片系统

- `build_pages(slide_dir, meta)` 自动推导 pages
- 解说文本三级回退：配对 txt → narration.txt → warn
- 逐页 AI 配音 + 合成片段 + 拼接
- 先做 fade 转场，zoom 后续迭代
- 新增 lib/slides.sh，~180 行

## Phase 4: 字幕增强

- subtitle.mode: auto / paired / null
- subtitle_style 先跳过（等 libass 方案稳定）
- ~30 行

## Phase 5: 入口整合

- `vt all` 重构：先读 meta → 检测 type → 走对应流程
- `vt slide` / `vt mix` 增强
- 统一错误处理：资源缺失 warn+继续，不阻断
- ~50 行

## Phase 6: 文档

- README + landing page 更新
- samples 加 meta.json 示例

## 不做（本期）

- transition 只做 fade
- zoom (Ken Burns) 跳过
- logo 水印跳过
- subtitle_style 跳过

## 顺序

按 Phase 1 → 2 → 3 → 4 → 5 → 6 依次实现。从 Phase 1 开始。