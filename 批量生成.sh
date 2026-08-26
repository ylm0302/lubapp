#!/bin/bash
# 尘虚界视频批量生成脚本（keyframes模式 + 自动重试）
# 用法: bash 批量生成.sh
set -u

API_KEY="wk-bXicb25bO3bLQ6pNrK1ghXeufrjUZRIez2PcocHF7rMabCFG"
API="https://apihub.agnes-ai.com/v1/videos"
PROJ="/Users/mac/Desktop/Toonflow-app/尘虚界动态漫"
OUT="$PROJ/08-视频/分镜头1"
mkdir -p "$OUT"

# 分镜配置：序号|图片文件名|提示词文件|输出名
# 提示词统一用英文（模型英文能力更强），关键帧用同一张图锁定人物

gen_shot() {
  local name="$1" img="$2" prompt_file="$3" seed="$4"
  local img_url="https://raw.githubusercontent.com/ylm0302/lubapp/main/07-%E5%9B%BE%E7%89%87/$img"
  local prompt=$(cat "$prompt_file")

  echo "=== [$name] 开始 ($(date +%H:%M:%S)) ==="

  # 先验证URL可访问
  local ok=0
  for i in 1 2 3; do
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 20 "$img_url")
    if [ "$code" = "200" ]; then ok=1; break; fi
    echo "  URL检查失败(HTTP:$code)，重试$i..."
    sleep 8
  done
  [ "$ok" = "1" ] || { echo "  [失败] URL无法访问: $img_url"; return 1; }

  # 创建keyframes任务（带重试，最多5次）
  local task_resp=""
  for i in 1 2 3 4 5; do
    echo "  创建任务尝试$i..."
    task_resp=$(curl -s --max-time 150 -X POST "$API" \
      -H "Authorization: Bearer $API_KEY" \
      -H "Content-Type: application/json" \
      -d "{
        \"model\": \"agnes-video-v2.0\",
        \"prompt\": $(python3 -c "import json; print(json.dumps(open('$prompt_file').read()))"),
        \"extra_body\": {\"image\": [\"$img_url\", \"$img_url\"], \"mode\": \"keyframes\"},
        \"num_frames\": 361,
        \"frame_rate\": 24,
        \"seed\": $seed
      }")
    echo "$task_resp" | grep -q '"video_id"' && break
    echo "  任务创建失败: $(echo "$task_resp" | head -c 200)"
    sleep 15
  done

  local video_id=$(echo "$task_resp" | python3 -c "import json,sys; print(json.load(sys.stdin).get('video_id',''))" 2>/dev/null)
  [ -n "$video_id" ] || { echo "  [失败] 无法获取video_id: $task_resp"; return 1; }
  echo "  video_id: $video_id"

  # 轮询等待完成（最长10分钟）
  local url=""
  for i in $(seq 1 40); do
    sleep 15
    resp=$(curl -s --max-time 30 --location --request GET "https://apihub.agnes-ai.com/agnesapi?video_id=$video_id" \
      --header "Authorization: Bearer $API_KEY")
    status=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',''))" 2>/dev/null)
    prog=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin).get('progress',''))" 2>/dev/null)
    echo "  进度: $status $prog%"
    if [ "$status" = "completed" ]; then
      url=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin).get('url',''))" 2>/dev/null)
      break
    elif [ "$status" = "failed" ]; then
      echo "  [失败] 任务failed: $(echo "$resp" | head -c 300)"
      return 1
    fi
  done

  [ -n "$url" ] || { echo "  [失败] 等待超时"; return 1; }
  echo "  视频URL: $url"

  # 下载视频
  curl -s --max-time 180 -o "$OUT/${name}.mp4" "$url" || { echo "  [失败] 下载失败"; return 1; }
  echo "  已下载: $OUT/${name}.mp4"

  # 提取末帧并压缩（供下一镜使用 + 验证）
  /opt/homebrew/bin/ffmpeg -y -sseof -0.1 -i "$OUT/${name}.mp4" -update 1 -q:v 2 "$OUT/${name}_末帧.png" 2>/dev/null
  python3 -c "
from PIL import Image
import os
try:
    img = Image.open('$OUT/${name}_末帧.png').convert('RGB')
    img = img.resize((512, 341), Image.LANCZOS)
    img.save('$PROJ/07-图片/${name}_末帧_微型.jpg', 'JPEG', quality=70)
    print('  末帧压缩:', os.path.getsize('$PROJ/07-图片/${name}_末帧_微型.jpg')//1024, 'KB')
except Exception as e:
    print('  末帧处理失败:', e)
"
  echo "=== [$name] 完成 ==="
}

# 说明：本脚本由主流程调用，传入 镜头名 图片名 提示词文件 seed
"$@"
