#!/usr/bin/env bash
# 生成 devices.json(供网页使用)。纯 bash 实现, 不依赖 python。
# 用法: bash gen_devices.sh > devices.json
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${1:-$SRC/devices.conf}"

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

declare -A DISPLAY_OF
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
  echo "    {"
  echo "      \"id\": \"$(json_escape "$did")\","
  echo "      \"display\": \"$(json_escape "${DISPLAY_OF[$did]}")\","
  echo "      \"versions\": ["
  echo "${VERSIONS_OF[$did]}" | sed 's/^/      /'
  echo "      ]"
  if [ "$i" -lt "$n" ]; then echo "    },"; else echo "    }"; fi
done
echo "  ]"
echo "}"
