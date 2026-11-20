#!/usr/bin/env bash
# ============================================================================
#  build-all.sh — 一键全量编译(本地 Linux/WSL2)
#
#  依次执行 builds/<设备ID>/v<版本序号>.sh 里的每个"机型 + 内核版本"编译脚本,
#  每个组合的日志单独保存, 最后汇总成功/失败清单。支持断点续跑与并行。
#
#  用法:
#    bash build-all.sh                       # 全量编译(串行)
#    bash build-all.sh --dry-run             # 全量演练(不下载不编译, 检查参数链路)
#    bash build-all.sh --only alioth,marble  # 只编译指定设备(逗号分隔)
#    bash build-all.sh --limit 5             # 只跑前 5 个组合(冒烟测试)
#    bash build-all.sh --resume              # 跳过上次已成功的组合
#    bash build-all.sh -j 2                  # 2 个组合并行(内存/CPU 有限时慎用)
#    bash build-all.sh --fail-fast           # 遇到第一个失败就停
#
#  产物: output/ 下各设备的内核 zip; 日志: logs/<设备>_v<序号>.log
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR"
BUILDS="$ROOT/builds"
LOG_DIR="$ROOT/logs"
STATE="$LOG_DIR/build-all.state"

OPT_DRY_RUN=0
OPT_ONLY=""
OPT_LIMIT=0
OPT_RESUME=0
OPT_JOBS=1
OPT_FAIL_FAST=0

usage() { sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) OPT_DRY_RUN=1 ;;
    --only)    shift; OPT_ONLY="${1:-}" ;;
    --limit)   shift; OPT_LIMIT="${1:-0}" ;;
    --resume)  OPT_RESUME=1 ;;
    -j|--jobs) shift; OPT_JOBS="${1:-1}" ;;
    --fail-fast) OPT_FAIL_FAST=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1 (试 -h)" >&2; exit 1 ;;
  esac
  shift
done

[ -d "$BUILDS" ] || { echo "错误: 未找到 $BUILDS, 请先运行 bash tools/gen_build_scripts.sh" >&2; exit 1; }

if [ "$(uname -s)" != "Linux" ]; then
  echo "提示: build-all.sh 需要 Linux/WSL2 环境(内核编译依赖 linux 工具链)。" >&2
  echo "      Windows 下请用 WSL2, 或改用: bash tools/trigger-all.sh (走 GitHub Actions 云端编译)" >&2
fi

mkdir -p "$LOG_DIR"
touch "$STATE"

# 收集脚本清单(按设备名排序)
mapfile -t ALL < <(find "$BUILDS" -mindepth 2 -maxdepth 2 -name 'v*.sh' | sort -V)

# 过滤 --only
SCRIPTS=()
for s in "${ALL[@]}"; do
  [ -n "$s" ] || continue
  if [ -n "$OPT_ONLY" ]; then
    id="$(basename "$(dirname "$s")")"
    hit=0
    IFS=',' read -ra ids <<< "$OPT_ONLY"
    for one in "${ids[@]}"; do
      one="$(echo "$one" | xargs)"
      [ "$one" = "$id" ] && hit=1
    done
    [ "$hit" = 1 ] || continue
  fi
  SCRIPTS+=("$s")
done

# --resume: 跳过上次 OK 的组合
if [ "$OPT_RESUME" = 1 ] && [ -s "$STATE" ]; then
  FILTERED=()
  for s in "${SCRIPTS[@]}"; do
    rel="${s#"$ROOT"/}"
    grep -q "^OK ${rel}$" "$STATE" || FILTERED+=("$s")
  done
  SCRIPTS=("${FILTERED[@]}")
fi

# --limit
if [ "$OPT_LIMIT" -gt 0 ] && [ "${#SCRIPTS[@]}" -gt "$OPT_LIMIT" ]; then
  SCRIPTS=("${SCRIPTS[@]:0:$OPT_LIMIT}")
fi

TOTAL="${#SCRIPTS[@]}"
if [ "$TOTAL" -eq 0 ]; then
  echo "没有需要编译的组合(可能是 --only/--resume 过滤后为空)。"
  exit 0
fi

echo
echo "==================== 全量编译 ===================="
echo "  组合总数 : $TOTAL"
echo "  并行度   : $OPT_JOBS"
echo "  演练模式 : $([ "$OPT_DRY_RUN" = 1 ] && echo 是 || echo 否)"
echo "  断点续跑 : $([ "$OPT_RESUME" = 1 ] && echo 是 || echo 否)"
echo "  日志目录 : $LOG_DIR"
echo "================================================="
echo

run_one() {
  local s="$1" id n log
  id="$(basename "$(dirname "$s")")"
  n="$(basename "$s" .sh)"
  log="$LOG_DIR/${id}_${n}.log"
  local -a extra=()
  [ "$OPT_DRY_RUN" = 1 ] && extra+=(--dry-run)
  echo ">>> [$id $n] 开始 ($(date '+%H:%M:%S'))"
  if bash "$s" "${extra[@]}" >"$log" 2>&1; then
    echo "    [$id $n] 成功"
    echo "OK  ${s#"$ROOT"/}" >> "$STATE"
    return 0
  else
    echo "    [$id $n] 失败 — 日志: ${log#"$ROOT"/}"
    echo "FAIL ${s#"$ROOT"/}" >> "$STATE"
    return 1
  fi
}

DONE=0; OK=0; FAIL=0; FAILED_LIST=()
if [ "$OPT_JOBS" -le 1 ]; then
  for s in "${SCRIPTS[@]}"; do
    DONE=$((DONE + 1))
    echo "[$DONE/$TOTAL]"
    if run_one "$s"; then OK=$((OK + 1)); else
      FAIL=$((FAIL + 1)); FAILED_LIST+=("$s")
      [ "$OPT_FAIL_FAST" = 1 ] && break
    fi
  done
else
  running=0
  for s in "${SCRIPTS[@]}"; do
    DONE=$((DONE + 1))
    run_one "$s" &
    running=$((running + 1))
    if [ "$running" -ge "$OPT_JOBS" ]; then
      wait -n || true
      running=$((running - 1))
    fi
  done
  wait || true
  # 并行模式下按日志尾部判定成败
  for s in "${SCRIPTS[@]}"; do
    id="$(basename "$(dirname "$s")")"; n="$(basename "$s" .sh)"
    log="$LOG_DIR/${id}_${n}.log"
    if [ -f "$log" ]; then
      if tail -n 5 "$log" | grep -qE "失败|错误|error:|Error 1"; then
        FAIL=$((FAIL + 1)); FAILED_LIST+=("$s")
      else
        OK=$((OK + 1))
      fi
    fi
  done
fi

echo
echo "==================== 编译结果汇总 ===================="
echo "  成功: $OK   失败: $FAIL   共: $TOTAL"
if [ "$FAIL" -gt 0 ]; then
  echo "  失败清单:"
  for s in "${FAILED_LIST[@]}"; do echo "    - ${s#"$ROOT"/}"; done
  echo
  echo "  排查: 查看 logs/<设备>_v<序号>.log 结尾的错误信息;"
  echo "        修好后可运行 bash build-all.sh --resume 只重跑失败的组合。"
  exit 1
fi
echo "  全部编译成功, 产物在 output/ 目录。"
