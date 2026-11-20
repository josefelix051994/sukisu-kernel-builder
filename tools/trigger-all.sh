#!/usr/bin/env bash
# ============================================================================
#  trigger-all.sh — 一键触发 GitHub Actions 全量编译(build-all.yml 矩阵工作流)
#
#  在云端按矩阵并行编译 devices.json 里的每个"机型 + 内核版本"组合,
#  无需本地 Linux 环境, 手机/Windows 上也能用。
#
#  前置: 需要一个有 workflow 权限的 GitHub Token, 传给 GH_TOKEN 环境变量:
#    GH_TOKEN=ghp_xxx bash tools/trigger-all.sh
#
#  用法:
#    GH_TOKEN=... bash tools/trigger-all.sh                     # 触发全部组合(真实编译)
#    GH_TOKEN=... bash tools/trigger-all.sh --dry-run           # 只做参数检查(不编译)
#    GH_TOKEN=... bash tools/trigger-all.sh --only alioth,marble
#    GH_TOKEN=... bash tools/trigger-all.sh --device gki-a15    # 单个设备
#    GH_TOKEN=... bash tools/trigger-all.sh --max-parallel 3    # 并发任务数(默认 2)
#    GH_TOKEN=... bash tools/trigger-all.sh --wait              # 触发后持续等待并输出结果
#
#  说明: 公共仓库的 Actions 分钟免费; 组合很多时请控制 --max-parallel,
#        避免单机并发过高导致 runner 内存不足超时。
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONF="$ROOT/devices.conf"

OWNER="xingyiqaq"
REPO="sukisu-kernel-builder"
WORKFLOW="build-all.yml"
REF="main"
API="https://api.github.com"

OPT_ONLY=""
OPT_MAX_PAR="2"
OPT_DRY=0
OPT_WAIT=0

usage() { sed -n '3,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --only)          shift; OPT_ONLY="${1:-}" ;;
    --device)        shift; OPT_ONLY="${1:-}" ;;
    --max-parallel)  shift; OPT_MAX_PAR="${1:-2}" ;;
    --dry-run)       OPT_DRY=1 ;;
    --wait)          OPT_WAIT=1 ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "未知参数: $1 (试 -h)" >&2; exit 1 ;;
  esac
  shift
done

[ -n "${GH_TOKEN:-}" ] || { echo "错误: 请通过环境变量提供 GH_TOKEN(需要 workflow 权限)" >&2; exit 1; }
[ -f "$CONF" ] || { echo "错误: 未找到 $CONF" >&2; exit 1; }

declare -A COUNTER=()
N=0
LIST=""
while IFS='|' read -r id rest; do
  id="$(printf '%s' "$id" | tr -d '\r' | xargs)"
  [ -z "$id" ] && continue
  case "$id" in \#*) continue ;; esac
  if [ -n "$OPT_ONLY" ]; then
    hit=0
    IFS=',' read -ra ids <<< "$OPT_ONLY"
    for one in "${ids[@]}"; do
      one="$(echo "$one" | xargs)"
      [ "$one" = "$id" ] && hit=1
    done
    [ "$hit" = 1 ] || continue
  fi
  COUNTER[$id]=$(( ${COUNTER[$id]:-0} + 1 ))
  N=$((N + 1))
  LIST+="  - $id v${COUNTER[$id]}: $(printf '%s' "$rest" | cut -d'|' -f1 | tr -d '\r' | xargs)"$'\n'
done < "$CONF"

if [ "$N" -eq 0 ]; then
  echo "没有匹配的组合(--only 为空或匹配不到设备)。用 bash build.sh --list 查看设备 ID。"
  exit 1
fi

echo
echo "==================== 触发云端全量编译 ===================="
echo "  工作流   : $WORKFLOW"
echo "  组合数   : $N"
echo "  并发上限 : $OPT_MAX_PAR"
echo "  模式     : $([ "$OPT_DRY" = 1 ] && echo 演练 || echo 真实编译)"
echo "  仓库     : https://github.com/$OWNER/$REPO"
echo "========================================================="
printf '%s' "$LIST" | head -n 200
[ "$N" -gt 200 ] && echo "  ...(共 $N 个)"
echo

if [ "$OPT_DRY" = 1 ]; then
  DRY_JSON=true
else
  DRY_JSON=false
fi

BODY=$(printf '{"ref":"%s","inputs":{"only":"%s","max_parallel":"%s","dry_run":%s}}' \
  "$REF" "$OPT_ONLY" "$OPT_MAX_PAR" "$DRY_JSON")

http_code=$(curl -s -o /tmp/trigger-all.out -w '%{http_code}' \
  -X POST "$API/repos/$OWNER/$REPO/actions/workflows/$WORKFLOW/dispatches" \
  -H "Authorization: Bearer $GH_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -H "User-Agent: sukisu-kernel-builder" \
  -H "Content-Type: application/json" \
  -d "$BODY")

if [ "$http_code" != "204" ]; then
  echo "触发失败 (HTTP $http_code):" >&2
  cat /tmp/trigger-all.out >&2
  exit 1
fi
echo "已触发 ✓ (查看: https://github.com/$OWNER/$REPO/actions/workflows/$WORKFLOW)"

if [ "$OPT_WAIT" != 1 ]; then
  echo "提示: 加 --wait 可等待编译结束并输出结果汇总。"
  exit 0
fi

echo
echo "等待编译结束(每 60 秒检查一次)..."
sleep 10
RUN_ID=""
for _ in 1 2 3 4 5 6; do
  RUNS=$(curl -s "$API/repos/$OWNER/$REPO/actions/runs?event=workflow_dispatch&per_page=5" \
    -H "Authorization: Bearer $GH_TOKEN" -H "User-Agent: sukisu-kernel-builder")
  RUN_ID=$(printf '%s' "$RUNS" | grep -o '"id":[0-9]*' | head -n1 | cut -d: -f2)
  [ -n "$RUN_ID" ] && break
  sleep 5
done
if [ -z "$RUN_ID" ]; then
  echo "未能获取运行 ID, 请到 Actions 页面查看。"
  exit 0
fi

while :; do
  RUN=$(curl -s "$API/repos/$OWNER/$REPO/actions/runs/$RUN_ID" \
    -H "Authorization: Bearer $GH_TOKEN" -H "User-Agent: sukisu-kernel-builder")
  STATUS=$(printf '%s' "$RUN" | grep -o '"status":"[a-z_]*"' | head -n1 | cut -d'"' -f4)
  CONC=$(printf '%s' "$RUN" | grep -o '"conclusion":"[a-z_]*"' | head -n1 | cut -d'"' -f4 || true)
  echo "  $(date '+%H:%M:%S') 状态: $STATUS ${CONC:+($CONC)}"
  [ "$STATUS" = "completed" ] && break
  sleep 60
done

echo
echo "编译结束: $STATUS $( [ "${CONC:-}" = "success" ] && echo '✓ 全部成功' || echo "($CONC)" )"
echo "详情与产物: https://github.com/$OWNER/$REPO/actions/runs/$RUN_ID"
