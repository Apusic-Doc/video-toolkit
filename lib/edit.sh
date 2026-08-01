#!/bin/bash
# ============================================================
# recut — 对已合成的成片做时间区间剪辑（去掉念白间的长停顿等）
#
# 只在最终产物（<feature>.mp4 / -sub.mp4 / -no-cover.mp4 / ...）上操作，
# 不碰 recording.mov / subtitles.srt / ai_dub.wav —— 这几个文件的时间戳
# 是录制时脚本 step() 实时打的，事后剪 recording.mov 会让整套时间戳系统失效。
# 成片如果已经烧了字幕，画面/声音/字幕是同一份像素，直接剪成片天然不会错位。
#
# 用法:
#   1. 在 feature 目录下写 cuts.json：
#      [{"start": "00:00:59", "end": "00:01:02"}, {"start": "00:02:10", "end": "00:02:15"}]
#      （要去掉的时间区间，可以写多个，顺序、有无重叠都会校验）
#   2. vt recut <feature>
#
# 每次剪之前都会把当前文件备份到 backups/<原文件名>-<时间戳>.mp4，不覆盖旧备份、
# 原文件名不变——cuts.json 是可重复执行的"最后一道精修步骤"：如果之后重新
# vt redub/vt burn 生成了新的成片，再跑一次 vt recut 就能重新应用同一批剪辑点。
# ============================================================

# 读 cuts.json，校验区间合法（结束>开始、不超出时长、互相不重叠），
# 按开始时间排序后逐行打印 "start_sec end_sec"；任何一条不合法就整体失败退出
_recut_parse_cuts() {
    local cuts_json="$1" duration="$2"
    python3 -c "
import json, sys

def to_sec(t):
    parts = [float(p) for p in str(t).split(':')]
    while len(parts) < 3: parts.insert(0, 0)
    h, m, s = parts
    return h * 3600 + m * 60 + s

with open('$cuts_json') as f:
    cuts = json.load(f)

if not isinstance(cuts, list) or len(cuts) == 0:
    print('cuts.json 必须是一个非空数组', file=sys.stderr)
    sys.exit(1)

duration = float('$duration')
ranges = []
for c in cuts:
    try:
        s, e = to_sec(c['start']), to_sec(c['end'])
    except Exception:
        print(f'区间格式不对，需要 {{\"start\":..,\"end\":..}}: {c}', file=sys.stderr)
        sys.exit(1)
    if e <= s:
        print(f'区间不合法（结束早于/等于开始）: {c[\"start\"]} - {c[\"end\"]}', file=sys.stderr)
        sys.exit(1)
    if s < 0 or e > duration + 0.5:
        print(f'区间超出视频时长({duration:.2f}s): {c[\"start\"]} - {c[\"end\"]}', file=sys.stderr)
        sys.exit(1)
    ranges.append((s, min(e, duration)))

ranges.sort()
for i in range(1, len(ranges)):
    if ranges[i][0] < ranges[i-1][1]:
        print(f'区间互相重叠: {ranges[i-1]} 和 {ranges[i]}', file=sys.stderr)
        sys.exit(1)

for s, e in ranges:
    print(f'{s:.3f} {e:.3f}')
"
}

# 对单个视频文件应用 cuts.json，成功后原地覆盖 $src（已提前备份）
# 用法: _recut_apply_one <视频文件> <cuts.json路径> <feature目录>
_recut_apply_one() {
    local src="$1" cuts_json="$2" dir="$3"
    [ ! -f "$src" ] && return 0   # 这个变体本来就不存在，跳过，不算错误

    local name; name=$(basename "$src")
    local duration
    duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$src" 2>/dev/null)
    if [ -z "$duration" ]; then err "拿不到时长，跳过: $name"; return 1; fi

    local ranges
    ranges=$(_recut_parse_cuts "$cuts_json" "$duration") || { err "cuts.json 校验失败: $name"; return 1; }

    # 备份（每次都留一份新的，不覆盖旧备份）
    mkdir -p "$dir/backups"
    local ts; ts=$(date +%Y%m%d-%H%M%S)
    local backup="$dir/backups/${name%.mp4}-${ts}.mp4"
    cp "$src" "$backup"
    info "已备份: backups/$(basename "$backup")"

    # 总时长减去所有 cut 区间 = 要保留的区间列表
    local keep_ranges
    keep_ranges=$(python3 -c "
duration = float('$duration')
cuts = []
import sys
for line in '''$ranges'''.strip().split(chr(10)):
    s, e = map(float, line.split())
    cuts.append((s, e))
keep = []
cursor = 0.0
for s, e in cuts:
    if s > cursor:
        keep.append((cursor, s))
    cursor = e
if cursor < duration:
    keep.append((cursor, duration))
for s, e in keep:
    print(f'{s:.3f} {e:.3f}')
")
    if [ -z "$keep_ranges" ]; then
        err "剪完之后没有剩余内容，取消: $name"
        return 1
    fi

    # 逐段重新编码（输出端 -ss/-to 精确到帧，不用 -c copy 直切避免落在关键帧之间导致的偏差），
    # 编码参数跟 compose.sh 用的完全一致，方便后面 concat 阶段能 -c copy 无损拼接
    local tmp="/tmp/_vt_recut_$$"; mkdir -p "$tmp"
    local concat_list="$tmp/concat.txt"; > "$concat_list"
    local i=0
    while read -r s e; do
        i=$((i + 1))
        local seg="$tmp/seg_$i.mp4"
        ffmpeg -i "$src" -ss "$s" -to "$e" \
            -c:v h264_videotoolbox -b:v 5M -r 30 -pix_fmt yuv420p \
            -c:a aac -ar 48000 -ac 2 "$seg" -y 2>/dev/null
        [ -f "$seg" ] && echo "file '$seg'" >> "$concat_list"
    done <<< "$keep_ranges"

    local result="$tmp/result.mp4"
    if ! ffmpeg -f concat -safe 0 -i "$concat_list" -c copy "$result" -y 2>/dev/null; then
        warn "拼接失败，回退到重新编码: $name"
        ffmpeg -f concat -safe 0 -i "$concat_list" -c:v h264_videotoolbox -b:v 5M -c:a aac "$result" -y 2>/dev/null
    fi

    if [ ! -f "$result" ]; then
        err "剪辑失败，原文件未改动（备份在 backups/$(basename "$backup")）: $name"
        rm -rf "$tmp"
        return 1
    fi

    mv "$result" "$src"
    rm -rf "$tmp"
    local new_duration
    new_duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$src" 2>/dev/null)
    ok "$name: ${duration%.*}s → ${new_duration%.*}s"
}

cmd_recut() {
    local dir="$1"
    local cuts_json="$dir/cuts.json"
    [ ! -f "$cuts_json" ] && { err "缺少 $dir/cuts.json，先写好要剪掉的时间区间，格式见 lib/edit.sh 顶部注释"; return 1; }

    local base="$dir/$(basename "$dir")"
    local any=0 failed=0
    for variant in "$base.mp4" "$base-sub.mp4" "$base-no-cover.mp4" "$base-no-cover-sub.mp4" "${base}_en.mp4"; do
        if [ -f "$variant" ]; then
            any=1
            _recut_apply_one "$variant" "$cuts_json" "$dir" || failed=1
        fi
    done
    [ "$any" = "0" ] && { err "找不到任何成片（.mp4/-sub.mp4/-no-cover.mp4...），请先 vt mix"; return 1; }
    [ "$failed" = "1" ] && { err "部分文件剪辑失败，见上面的错误信息"; return 1; }
    ok "剪辑完成"
}
