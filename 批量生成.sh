#!/bin/bash
# ============================================================
# 尘虚界第1集 场景一致性链式生成脚本（10秒/镜，keyframes模式）
# 链式衔接：分镜N 首帧 = 分镜N-1的真实末帧，末帧 = 分镜N的构图图
# 模型在 [上一镜场景 → 本镜构图] 间平滑过渡，保证场景连续
# ============================================================
set -u

API_KEY="wk-bXicb25bO3bLQ6pNrK1ghXeufrjUZRIez2PcocHF7rMabCFG"
API="https://apihub.agnes-ai.com/v1/videos"
PROJ="/Users/mac/Desktop/Toonflow-app/尘虚界动态漫"
OUT="$PROJ/08-视频/分镜头1"
RAW="https://raw.githubusercontent.com/ylm0302/lubapp/main"
# 获取GitHub raw URL（自动UTF-8编码中文）
raw_url() { python3 -c "import urllib.parse, sys; print('$RAW/' + urllib.parse.quote(sys.argv[1]))" "$1" 2>/dev/null; }
mkdir -p "$OUT"

FRAMES=241  # 10秒 @ 24fps

# 分镜配置：镜头名|构图图文件名(末帧)|提示词文件|seed
SHOTS=(
  "分镜01|分镜01_宋望登场_微型.jpg|prompt_compact/分镜01_精简.txt|20251201"
  "分镜02|分镜02_尘纹异动_微型.jpg|prompt_compact/分镜02_精简.txt|20251202"
  "分镜03|分镜03_恶灵袭击_微型.jpg|prompt_compact/分镜03_精简.txt|20251203"
  "分镜04|分镜04_宋望出手_微型.jpg|prompt_compact/分镜04_精简.txt|20251204"
  "分镜05|分镜05_召唤林冲_微型.jpg|prompt_compact/分镜05_精简.txt|20251205"
  "分镜06|分镜06_林冲击退_微型.jpg|prompt_compact/分镜06_精简.txt|20251206"
  "分镜07|分镜07_林冲回归_微型.jpg|prompt_compact/分镜07_精简.txt|20251207"
  "分镜08|分镜08_裂缝伏笔_微型.jpg|prompt_compact/分镜08_精简.txt|20251208"
  "分镜09|分镜09_片尾预告_微型.jpg|prompt_compact/分镜09_精简.txt|20251209"
)

# 校验URL可访问（重试）
check_url() {
  local url="$1"
  for i in 1 2 3 4 5; do
    local code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 20 "$url")
    [ "$code" = "200" ] && return 0
    echo "    [重试$i] URL HTTP:$code"
    sleep 10
  done
  return 1
}

# 提取末帧并压缩为下一镜首帧
extract_last_frame() {
  local name="$1"
  /opt/homebrew/bin/ffmpeg -y -sseof -0.1 -i "$OUT/${name}_10s.mp4" -update 1 -q:v 2 "$OUT/${name}_末帧.png" 2>/dev/null
  python3 -c "
from PIL import Image
import os
img = Image.open('$OUT/${name}_末帧.png').convert('RGB')
img = img.resize((512, 341), Image.LANCZOS)
img.save('$PROJ/07-图片/${name}_末帧_微型.jpg', 'JPEG', quality=70)
print('  末帧压缩:', os.path.getsize('$PROJ/07-图片/${name}_末帧_微型.jpg')//1024, 'KB')
"
  # 推送下一镜首帧到GitHub
  cd "$PROJ" && git add -A && git commit -m "feat: ${name}末帧" 2>&1 >/dev/null && \
  GIT_TERMINAL_PROMPT=0 git push 2>&1 | tail -1
}

gen_shot() {
  local name="$1" target_img="$2" prompt_file="$3" seed="$4" first_url="$5"
  local target_url=$(raw_url "07-图片/$target_img")
  local prompt=$(python3 -c "import json; print(json.dumps(open('$PROJ/$prompt_file',encoding='utf-8').read()))")

  echo ""
  echo "========== [$name] 开始 $(date +%H:%M:%S) =========="
  echo "  首帧(上一镜末帧): $first_url"
  echo "  末帧(本镜构图): $target_url"

  # 校验两个URL
  check_url "$first_url" || { echo "  ❌ 首帧URL失败"; return 1; }
  check_url "$target_url" || { echo "  ❌ 末帧URL失败"; return 1; }

  # 创建keyframes任务：image=[首帧, 末帧]，模型在两者间过渡
  local resp=""
  for i in 1 2 3 4 5 6; do
    echo "  [尝试$i] 创建任务..."
    resp=$(curl -s --max-time 150 -X POST "$API" \
      -H "Authorization: Bearer $API_KEY" \
      -H "Content-Type: application/json" \
      -d "{
        \"model\": \"agnes-video-v2.0\",
        \"prompt\": $prompt,
        \"extra_body\": {\"image\": [\"$first_url\", \"$target_url\"], \"mode\": \"keyframes\"},
        \"num_frames\": $FRAMES,
        \"frame_rate\": 24,
        \"seed\": $seed
      }")
    echo "$resp" | grep -q '"video_id"' && break
    echo "    失败: $(echo "$resp" | head -c 150)"
    sleep 20
  done

  local video_id=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin).get('video_id',''))" 2>/dev/null)
  [ -n "$video_id" ] || { echo "  ❌ 无video_id"; return 1; }
  echo "  video_id: $video_id"

  # 轮询
  local url=""
  for i in $(seq 1 30); do
    sleep 15
    local resp2=$(curl -s --max-time 30 --location --request GET "https://apihub.agnes-ai.com/agnesapi?video_id=$video_id" \
      --header "Authorization: Bearer $API_KEY")
    local status=$(echo "$resp2" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',''))" 2>/dev/null)
    local prog=$(echo "$resp2" | python3 -c "import json,sys; print(json.load(sys.stdin).get('progress',''))" 2>/dev/null)
    echo "  [$name] 进度: $status $prog%"
    if [ "$status" = "completed" ]; then
      url=$(echo "$resp2" | python3 -c "import json,sys; print(json.load(sys.stdin).get('url',''))" 2>/dev/null)
      break
    elif [ "$status" = "failed" ]; then
      echo "  ❌ 任务失败: $(echo "$resp2" | head -c 300)"
      return 1
    fi
  done
  [ -n "$url" ] || { echo "  ❌ 等待超时"; return 1; }

  curl -s --max-time 180 -o "$OUT/${name}_10s.mp4" "$url" || { echo "  ❌ 下载失败"; return 1; }
  echo "  ✅ 已下载: $OUT/${name}_10s.mp4"
  extract_last_frame "$name"
  echo "========== [$name] 完成 =========="
}

# ============ 主流程：链式生成 ============
START="${1:-01}"
PREV_FRAME=""  # 上一镜末帧URL

for entry in "${SHOTS[@]}"; do
  name="${entry%%|*}"
  num="${name#分镜}"
  if [ "$num" -ge "$START" ] 2>/dev/null; then
    rest="${entry#*|}"
    target_img="${rest%%|*}"
    rest="${rest#*|}"
    prompt_file="${rest%%|*}"
    seed="${rest##*|}"
    target_url=$(raw_url "07-图片/$target_img")

    # 分镜01：首帧=自身构图图；其余：首帧=上一镜末帧
    if [ -z "$PREV_FRAME" ]; then
      FIRST="$target_url"
    else
      FIRST="$PREV_FRAME"
    fi

    gen_shot "$name" "$target_img" "$prompt_file" "$seed" "$FIRST" || { echo "  [继续] $name 失败"; }

    # 记录本镜末帧URL作为下一镜首帧
    PREV_FRAME=$(raw_url "07-图片/${name}_末帧_微型.jpg")
  fi
done
echo ""
echo "=== 全部完成 ==="
