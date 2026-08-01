#!/bin/bash
# ============================================================
# group-merge — 把项目里若干个 feature 的成片按顺序合并成一个对外发布的大视频
#
# 分组定义存在项目级 meta.json 的 groups 数组里（vt-ui 的"分组"页面维护）：
#   { "groups": [ { "id": "onboarding", "title": "新手引导合集",
#                   "features": ["feature-01-xxx", "feature-03-yyy"] } ] }
#
# 只读取每个 feature 现有的成片（优先 -sub.mp4，没有则 .mp4），按 features
# 数组的顺序拼接，输出到项目根目录的 groups/<id>.mp4——不写回、不修改任何
# feature-*/ 目录下的文件，原视频完全不受影响。
# ============================================================

cmd_group_merge() {
    local group_id="$1"
    [ -z "$group_id" ] && { err "用法: vt group-merge <group-id>"; return 1; }
    local project_meta="$BASE/meta.json"
    [ ! -f "$project_meta" ] && { err "找不到项目级 meta.json: $project_meta"; return 1; }

    local group_json
    group_json=$(python3 -c "
import json, sys
with open('$project_meta') as f:
    m = json.load(f)
match = [g for g in m.get('groups', []) if g.get('id') == '$group_id']
if not match:
    sys.exit(1)
print(json.dumps(match[0]))
" 2>/dev/null) || { err "项目 meta.json 里找不到分组: $group_id"; return 1; }

    local title
    title=$(echo "$group_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('title',''))")
    local feature_names
    feature_names=$(echo "$group_json" | python3 -c "import json,sys; print(chr(10).join(json.load(sys.stdin).get('features',[])))")
    [ -z "$feature_names" ] && { err "分组 $group_id 里还没有任何 feature"; return 1; }

    info "分组合并: $group_id${title:+ ($title)}"

    local sources=()
    while IFS= read -r fname; do
        [ -z "$fname" ] && continue
        local fdir="$BASE/$fname"
        [ ! -d "$fdir" ] && { err "feature 目录不存在: $fname"; return 1; }
        local fbase="$fdir/$fname"
        local src=""
        if [ -f "$fbase-sub.mp4" ]; then src="$fbase-sub.mp4"
        elif [ -f "$fbase.mp4" ]; then src="$fbase.mp4"
        else
            err "找不到成片（.mp4 / -sub.mp4）: $fname，请先合成再加入分组"
            return 1
        fi
        info "  + $fname → $(basename "$src")"
        sources+=("$src")
    done <<< "$feature_names"

    local tmp="/tmp/_vt_group_$$"; mkdir -p "$tmp"
    local concat_list="$tmp/concat.txt"; > "$concat_list"
    for s in "${sources[@]}"; do echo "file '$s'" >> "$concat_list"; done

    mkdir -p "$BASE/groups"
    local out="$BASE/groups/$group_id.mp4"
    info "合并 ${#sources[@]} 个 feature → groups/$group_id.mp4"
    # 各 feature 成片编码参数在各自合成阶段已经对齐过（都走同一套 compose_final），
    # 优先尝试无损 stream-copy 拼接，参数偶尔不完全一致时才回退重新编码
    if ! ffmpeg -f concat -safe 0 -i "$concat_list" -c copy "$out" -y 2>/dev/null; then
        warn "stream-copy 拼接失败，回退到重新编码"
        ffmpeg -f concat -safe 0 -i "$concat_list" -c:v h264_videotoolbox -b:v 5M -c:a aac "$out" -y 2>/dev/null
    fi
    rm -rf "$tmp"

    [ -f "$out" ] && ok "groups/$group_id.mp4" || { err "合并失败"; return 1; }
}
