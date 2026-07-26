# 示例项目

无需录制即可体验 Video Toolkit 全流程。

## 录屏处理

```bash
vt all feature-01-demo
vt play feature-01-demo final
```

## 幻灯片生成

截图 + 解说文字 → 自动配音合成视频：

```bash
vt slide feature-02-slides
vt play feature-02-slides slides.mp4
```

结构：
```
feature-02-slides/slides/
├── 01.png            ← 截图（按顺序命名）
├── 02.png
├── 03.png
└── narration.txt     ← 每行一段解说
```

## 自定义

参考示例目录创建自己的项目：
```
feature-XX-name/
└── recording.mov    ← Cmd+Shift+5 录制
```
