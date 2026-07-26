# 示例项目

安装后直接体验，无需录制。

## 录屏处理

```bash
vt all feature-01-demo
vt play feature-01-demo final
```

## 幻灯片生成

```bash
vt slide feature-02-slides
vt play feature-02-slides final
```

结构：
```
feature-02-slides/slides/
├── 01.png + narration.txt    ← 截图 + 解说（每行一页）
├── 02.png
└── 03.png
```

## 自定义

参考示例创建自己的项目：

**录屏模式**：
```
feature-XX-name/
└── recording.mov        # Cmd+Shift+5 录制
```

**幻灯片模式**：
```
feature-XX-name/slides/
├── 01.png
├── 02.png
└── narration.txt        # 每行一段解说
```

**v2 高级配置**：添加 `meta.json` 启用封面/BGM/封底，详见 `../docs/SPEC.md`。
