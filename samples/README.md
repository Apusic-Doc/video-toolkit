# 示例项目

无需录制即可体验 Video Toolkit 全流程。

## 快速体验

```bash
# 1. 进入示例目录
cd samples
vt all feature-01-demo

# 2. 查看生成的文件
ls feature-01-demo/
# → recording.mov  subtitles.srt  ai_dub.wav  final.mp4

# 3. 播放成片
vt play feature-01-demo final
```

## 自定义

参考 `feature-01-demo/` 结构创建自己的项目：

```
feature-XX-name/
└── recording.mov    ← 用 Cmd+Shift+5 录制，放这里
```

然后 `vt all XX` 即可。
