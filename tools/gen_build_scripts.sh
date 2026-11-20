#!/usr/bin/env bash
# ============================================================================
#  gen_build_scripts.sh — 为 devices.conf 里每个"设备机型 + 内核版本"生成独立编译脚本
#
#  生成位置: builds/<设备ID>/v<版本序号>.sh
#  版本序号与 build.sh 的 --version N 完全一致(同一设备在 devices.conf 中出现的第 N 行)
#
#  用法:
#    bash tools/gen_build_scripts.sh            # 生成/刷新全部脚本
#    bash tools/gen_build_scripts.sh --clean    # 先删除旧生成物再生成
#
#  提示: 修改 devices.conf 后需要重新运行本脚本;builds/ 目录为生成产物, 不要手改。
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONF="$ROOT/devices.conf"
OUT_DIR="$ROOT/builds"

CLEAN=0
case "${1:-}" in
  --clean) CLEAN=1 ;;
  -h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) echo "未知参数: $1 (试 -h)" >&2; exit 1 ;;
esac

[ -f "$CONF" ] || { echo "错误: 未找到 $CONF" >&2; exit 1; }

if [ "$CLEAN" = 1 ]; then
  rm -rf "$OUT_DIR"
fi
mkdir -p "$OUT_DIR"

trim() { printf '%s' "$1" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }

declare -A COUNTER=()
COUNT=0
while IFS='|' read -r f1 f2 f3 f4 f5 f6 f7 f8 f9; do
  id="$(trim "$f1")"
  [ -z "$id" ] && continue
  case "$id" in \#*) continue ;; esac

  verlabel="$(trim "$f2")"
  display="$(trim "$f3")"
  repo="$(trim "$f4")"
  branch="$(trim "$f5")"
  kver="$(trim "$f6")"
  android="$(trim "$f7")"
  gki="$(trim "$f8")"
  defconfig="$(trim "$f9")"

  n=$(( ${COUNTER[$id]:-0} + 1 ))
  COUNTER[$id]=$n

  dir="$OUT_DIR/$id"
  mkdir -p "$dir"
  out="$dir/v$n.sh"
  cat > "$out" <<EOF
#!/usr/bin/env bash
# ============================================================================
#  自动生成脚本 (tools/gen_build_scripts.sh), 请勿手改。
#  设备   : $id ($display)
#  版本   : 第 $n 个 — $verlabel
#  仓库   : $repo @ $branch
#  内核   : Linux $kver · Android $android · GKI=$gki
#  defconfig: ${defconfig:-自动探测}
#
#  用法:
#    bash builds/$id/v$n.sh                # 正式开始编译
#    bash builds/$id/v$n.sh --dry-run      # 演练(不下载不编译)
#    bash builds/$id/v$n.sh --kpm          # 追加任意 build.sh 参数
# ============================================================================
set -euo pipefail
DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
exec bash "\$DIR/../../build.sh" --device "$id" --version "$n" --yes "\$@"
EOF
  chmod +x "$out"
  COUNT=$((COUNT + 1))
done < "$CONF"

# 每个设备目录附带一个说明
{
  echo "# builds/ — 自动生成的独立编译脚本"
  echo
  echo "由 \`bash tools/gen_build_scripts.sh\` 根据 devices.conf 生成, **不要手改**。"
  echo "每个文件对应一个设备机型 + 内核版本组合, 直接执行即可编译;"
  echo "也可以运行根目录的 \`bash build-all.sh\` 一次性跑完全部组合。"
  echo
  echo "| 设备 | 版本 | 脚本 |"
  echo "| --- | --- | --- |"
  for d in "$OUT_DIR"/*/; do
    [ -d "$d" ] || continue
    id="$(basename "$d")"
    for f in "$d"/v*.sh; do
      [ -f "$f" ] || continue
      n="$(basename "$f" .sh)"
      label="$(sed -n 's/^#  版本   : 第 [0-9]* 个 — //p' "$f" | head -n1)"
      echo "| $id | $n | [builds/$id/$n.sh](builds/$id/$n.sh) |"
    done
  done
} > "$OUT_DIR/README.md"

echo "已生成 $COUNT 个独立编译脚本 → $OUT_DIR/<设备ID>/v<版本序号>.sh"
echo "  索引: $OUT_DIR/README.md"
