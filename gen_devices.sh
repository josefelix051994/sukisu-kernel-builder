#!/usr/bin/env bash
# 生成 devices.json(供网页使用)。纯 bash 实现, 不依赖 python。
# 用法: bash gen_devices.sh > devices.json
# 注意: 必须用 bash 自己的重定向输出!
#   PowerShell 的 `>` 会把输出写成 UTF-16LE(带 BOM), 浏览器 fetch().json() 和 CI 的
#   python json 都会解析失败。在 PowerShell 里请这样调用:
#     & 'C:\Program Files\Git\bin\bash.exe' -c 'bash gen_devices.sh > devices.json'
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${1:-$SRC/devices.conf}"

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# 品牌/机型推导 (与 build.sh derive_brand_model 一致)
derive_brand_model() {
  local disp="$1" id="$2" repo="$3" brand="" model=""
  case "$disp" in
    Redmi\ *)    brand="Redmi";   model="${disp#Redmi }" ;;
    POCO\ *)     brand="POCO";    model="${disp#POCO }" ;;
    Mi\ *)       brand="Xiaomi";  model="${disp#Mi }" ;;
    Xiaomi\ *)   brand="Xiaomi";  model="${disp#Xiaomi }" ;;
    OnePlus\ *)  brand="OnePlus"; model="${disp#OnePlus }" ;;
    通用\ GKI*)  brand="Google";  model="${disp#通用 GKI · }" ;;
  esac
  if [ -z "$brand" ]; then
    case "$repo" in
      *OnePlusOSS*)                  brand="OnePlus" ;;
      *aosp-mirror*|*kernel_common*) brand="Google"; model="GKI" ;;
      *)                             brand="Xiaomi" ;;
    esac
  fi
  if [ "$disp" = "$id" ] || [ "$model" = "$id" ]; then model=""; fi
  printf '%s|%s\n' "$brand" "$model"
}

declare -A DISPLAY_OF
declare -A REPO_OF
declare -A ORDER_OF
declare -A VERSIONS_OF   # id -> 多行拼接, 行间用 \n
IDS=()

while IFS= read -r line || [ -n "$line" ]; do
  line="${line%%$'\r'}"
  [ -z "$line" ] && continue
  case "$line" in
    \#*) continue ;;
  esac
  IFS='|' read -r f1 f2 f3 f4 f5 f6 f7 f8 f9 <<< "$line"
  trim() { local v="$1"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"; printf '%s' "$v"; }
  did="$(trim "$f1")"; label="$(trim "$f2")"; disp="$(trim "$f3")"
  repo="$(trim "$f4")"; branch="$(trim "$f5")"; kver="$(trim "$f6")"
  android="$(trim "$f7")"; gki="$(trim "$f8")"; defcfg="$(trim "$f9")"
  [ -n "$did" ] || continue
  if [ -z "${ORDER_OF[$did]+x}" ]; then
    ORDER_OF[$did]="${#IDS[@]}"
    IDS+=("$did")
    DISPLAY_OF[$did]="$disp"
    REPO_OF[$did]="$repo"
  fi
  item="    {"
  item+="\"label\": \"$(json_escape "$label")\", "
  item+="\"repo\": \"$(json_escape "$repo")\", "
  item+="\"branch\": \"$(json_escape "$branch")\", "
  item+="\"kver\": \"$(json_escape "$kver")\", "
  item+="\"android\": \"$(json_escape "$android")\", "
  item+="\"gki\": $gki, "
  item+="\"defconfig\": \"$(json_escape "$defcfg")\""
  item+="}"
  if [ -z "${VERSIONS_OF[$did]+x}" ]; then
    VERSIONS_OF[$did]="$item"
  else
    VERSIONS_OF[$did]+=","$'\n'"$item"
  fi
done < "$CONF"

[ "${#IDS[@]}" -gt 0 ] || { echo "devices.conf 中没有有效记录" >&2; exit 1; }

echo "{"
echo "  \"devices\": ["
n="${#IDS[@]}"
i=0
for did in "${IDS[@]}"; do
  i=$((i+1))
  bm="$(derive_brand_model "${DISPLAY_OF[$did]}" "$did" "${REPO_OF[$did]:-}")"
  brand="${bm%%|*}"; model="${bm#*|}"
  echo "    {"
  echo "      \"id\": \"$(json_escape "$did")\","
  echo "      \"display\": \"$(json_escape "${DISPLAY_OF[$did]}")\","
  echo "      \"brand\": \"$(json_escape "$brand")\","
  echo "      \"model\": \"$(json_escape "$model")\","
  echo "      \"versions\": ["
  echo "${VERSIONS_OF[$did]}" | sed 's/^/      /'
  echo "      ]"
  if [ "$i" -lt "$n" ]; then echo "    },"; else echo "    }"; fi
done
echo "  ]"
echo "}"
