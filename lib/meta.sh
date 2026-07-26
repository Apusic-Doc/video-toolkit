#!/bin/bash
# ============================================================
# meta.json 引擎 — 三级配置合并 + 类型检测 + 资源查找
# ============================================================
# 依赖: python3 (JSON 解析)
# 用法: source lib/meta.sh
#       meta=$(load_meta "$feature_dir")
#       type=$(detect_type "$feature_dir" "$meta")
#       asset=$(resolve_asset "$feature_dir" "$meta" "cover")

# ── 内置默认值 ──
meta_defaults() {
  python3 -c "import json; print(json.dumps({
    'type': 'auto',
    'voice': 'zh-CN-XiaoxiaoNeural',
    'voice_en': 'en-US-AvaNeural',
    'cover': None,
    'outro': None,
    'cover_duration': 3,
    'outro_duration': 3,
    'bgm': None,
    'bgm_volume': 0.15,
    'bgm_loop': True,
    'resolution': '1920x1080',
    'fps': 30,
    'logo': None,
    'logo_position': 'bottom-right',
    'subtitle': {'mode': 'auto', 'burn': False},
    'subtitle_style': {'font_size': 22, 'color': '&H00FFFFFF', 'outline': '&H00000000'},
    'slides': {'mode': 'auto', 'page_duration': 3, 'page_padding': 1.5, 'transition': 'fade', 'zoom': 'none', 'pages': []}
  }))"
}

# ── 深度合并两个 JSON 对象 ──
# 用法: merge_json <base> <override>
merge_json() {
  python3 -c "
import json, sys
base = json.loads(sys.argv[1]) if sys.argv[1] else {}
over = json.loads(sys.argv[2]) if sys.argv[2] else {}

def merge(a, b):
    if isinstance(a, dict) and isinstance(b, dict):
        result = dict(a)
        for k, v in b.items():
            if k in result and isinstance(result[k], dict) and isinstance(v, dict):
                result[k] = merge(result[k], v)
            else:
                result[k] = v
        return result
    return b if b is not None else a

print(json.dumps(merge(base, over)))
" "$1" "$2"
}

# ── 读取 JSON 文件（不存在返回空） ──
read_json() {
  [ -f "$1" ] && python3 -c "import json; print(json.dumps(json.load(open('$1'))))" 2>/dev/null || echo "{}"
}

# ── 三级合并：project/meta.json → feature/meta.json → 内置默认 ──
# 用法: meta=$(load_meta "/path/to/feature-dir")
load_meta() {
  local feature_dir="$1"
  local project_dir="$(cd "$feature_dir/.." && pwd)"

  local proj_json=$(read_json "$project_dir/meta.json")
  local feat_json=$(read_json "$feature_dir/meta.json")
  local defaults=$(meta_defaults)

  # defaults → project → feature
  local merged=$(merge_json "$defaults" "$proj_json")
  merged=$(merge_json "$merged" "$feat_json")
  echo "$merged"
}

# ── 获取单个配置值 ──
# 用法: val=$(meta_get "$meta" "voice")
meta_get() {
  python3 -c "import json,sys; m=json.loads(sys.argv[1]); print(m.get(sys.argv[2],''))" "$1" "$2" 2>/dev/null
}

# ── 类型检测 ──
# 用法: type=$(detect_type "/path/feature" "$meta")
# 返回: video | slide | error_message
detect_type() {
  local dir="$1"; local meta="$2"
  local type=$(meta_get "$meta" "type")

  case "$type" in
    video) echo "video"; return ;;
    slide) echo "slide"; return ;;
  esac

  # auto 模式
  local has_video=0; local has_slide=0
  [ -f "$dir/recording.mov" ] && has_video=1
  [ -d "$dir/slides" ] && [ "$(ls "$dir/slides"/*.png "$dir/slides"/*.jpg 2>/dev/null | head -1)" ] && has_slide=1

  if [ "$has_video" -eq 1 ] && [ "$has_slide" -eq 0 ]; then echo "video"
  elif [ "$has_slide" -eq 1 ] && [ "$has_video" -eq 0 ]; then echo "slide"
  elif [ "$has_video" -eq 1 ] && [ "$has_slide" -eq 1 ]; then
    echo "error: 同时检测到 recording.mov 和 slides/，请在 meta.json 中设置 type"
  else
    echo "error: 未找到 recording.mov 或 slides/"
  fi
}

# ── 资源文件查找 ──
# 用法: path=$(resolve_asset "/path/feature" "$meta" "cover")
# 返回: 文件路径 | "" (不存在/不启用)
resolve_asset() {
  local dir="$1"; local meta="$2"; local key="$3"
  local project_dir="$(cd "$dir/.." && pwd)"

  # 1. meta 中显式设置（包括 null）
  local val=$(meta_get "$meta" "$key")
  if [ "$val" = "None" ] || [ "$val" = "null" ]; then
    echo ""
    return
  fi
  if [ -n "$val" ] && [ "$val" != "" ]; then
    # 路径相对 project 根
    local path="$project_dir/$val"
    if [ -f "$path" ]; then echo "$path"; return; fi
    warn "$key 指定文件不存在: $val"
    echo ""
    return
  fi

  # 2. meta 未设，自动检测
  local names=""
  case "$key" in
    cover) names="cover.png cover.mp4 cover.mov" ;;
    outro) names="outro.png outro.mp4 outro.mov" ;;
    bgm)   names="bgm.mp3 bgm.m4a bgm.wav" ;;
    logo)  names="logo.png logo.jpg" ;;
  esac

  # feature 目录优先
  for name in $names; do
    if [ -f "$dir/$name" ]; then echo "$dir/$name"; return; fi
  done
  # 全局 resources 目录
  for name in $names; do
    if [ -f "$project_dir/resources/$name" ]; then echo "$project_dir/resources/$name"; return; fi
  done

  echo ""
}
