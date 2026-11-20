#!/usr/bin/env bash
# ============================================================================
#  SukiSU-Ultra 内核编译工具  v1.0
#  依据官方集成教程: https://sukisu.org/zh/guide/how-to-integrate
#
#  功能: 选择设备型号 + 内核版本 → 自动:
#         1. 下载对应内核源码与编译工具链
#         2. 集成 SukiSU-Ultra (main / builtin 分支)
#         3. 启用 CONFIG_KSU 等配置并编译内核
#         4. 打包 AnyKernel3 zip (内置模式) 或输出 kernelsu.ko (LKM 模式)
#
#  运行环境: Linux (Ubuntu / Debian / WSL2), 需要网络, 建议 8GB+ 内存、50GB+ 磁盘
#  用法:     ./build.sh            # 交互式引导
#            ./build.sh --help     # 全部参数
# ============================================================================
set -euo pipefail

# ------------------------------- 路径与常量 --------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICES_CONF="$SCRIPT_DIR/devices.conf"
BASE_DIR="$SCRIPT_DIR/work"
TOOLCHAIN_DIR="$BASE_DIR/toolchains"
KERNEL_DIR="$BASE_DIR/kernel"
OUT_DIR="$KERNEL_DIR/out"
OUTPUT_DIR="$SCRIPT_DIR/output"
AK3_DIR="$BASE_DIR/AnyKernel3"
PKG_DIR="$BASE_DIR/ak3-pkg"
LOG_FILE="$SCRIPT_DIR/build.log"

CLANG_REPO="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86"
GCC64_REPO="https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9"
GCC32_REPO="https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9"
GCC64_MIRROR="https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9"
GCC32_MIRROR="https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9"
GCC_MIRROR_BR="lineage-19.1"
SUKISU_REPO="https://github.com/SukiSU-Ultra/SukiSU-Ultra"
SUKISU_SETUP_URL="https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh"
AK3_REPO="https://github.com/osm0sis/AnyKernel3"

# --------------------------------- 默认值 ----------------------------------
OPT_LIST=0
OPT_RESUME=0
OPT_CLEAN=0
OPT_YES=0
OPT_KPM=0
OPT_KSU_DEBUG=0
OPT_SUSFS=0
OPT_GCC=0
OPT_NO_PACK=0
OPT_DRY_RUN=0
OPT_BRANCH_GIVEN=0
SEL_DEVICE_ID=""
SEL_REPO=""
SEL_BRANCH=""
SEL_DEFCONFIG=""
SEL_KVER=""
SEL_ANDROID=""
SEL_GKI=0
SEL_DISPLAY=""
SEL_VERLABEL=""
SEL_ROW=""
KSU_BRANCH=""
KSU_MODE=""
OPT_VERSION=""
OPT_CLANG=""
USE_CLANG=1
CLANG_BRANCH=""
CLANG_DIR=""
GCC64_DIR=""
GCC32_DIR=""
DEFCONFIG=""
KVER=""
KSU_VERSION="unknown"
BUILD_BRAND=""
BUILD_MODEL=""
ARTIFACT_PATH=""
JOBS="$(nproc 2>/dev/null || echo 4)"
DEV_ROWS=()

# --------------------------------- 基础函数 --------------------------------
info() { echo -e "\033[1;34m[信息]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[完成]\033[0m $*"; }
warn() { echo -e "\033[1;33m[警告]\033[0m $*" >&2; }
die()  { echo -e "\033[1;31m[错误]\033[0m $*" >&2; exit 1; }
# 打印日志尾部后报错退出 (便于在 CI 日志里直接看到失败原因)
die_log() {
  local f="$1"; shift
  if [ -f "$f" ]; then
    # 先单独摘出错误行, 避免错误被淹没在 60 行编译进度里
    if grep -nE 'error:|fatal error|Error [0-9]|undefined reference|cannot be defined|No space left|prerequisites|internal compiler error' "$f" >/dev/null 2>&1; then
      echo -e "\033[1;33m[警告]\033[0m 日志中的错误行 (最后 8 条):" >&2
      grep -nE 'error:|fatal error|Error [0-9]|undefined reference|cannot be defined|No space left|prerequisites|internal compiler error' "$f" \
        | tail -n 8 | cut -c1-300 >&2 || true
    fi
    echo -e "\033[1;33m[警告]\033[0m 日志末尾 ($f, 最后 60 行):" >&2
    tail -n 60 "$f" >&2 || true
  fi
  die "$@"
}

usage() {
  cat <<'EOF'
SukiSU-Ultra 内核编译工具

用法: ./build.sh [选项]

  不带参数           交互式引导: 选设备型号 → 选内核版本 → 选集成分支 → 编译打包
  --list             列出设备库全部条目
  --device <id>      直接指定设备 ID (如 alioth)
  --version <n>      该设备第 n 个内核版本 (从 1 开始, 配合 --device)
  --branch <名称>    直接指定内核分支 (可单独使用, 自动反查设备)
  --repo <url>       自定义内核仓库 (配合 --branch, 绕过设备库)
  --defconfig <路径> 指定 defconfig, 如 vendor/alioth_user_defconfig
  --kver <x.y>       自定义源时声明内核版本 (用于选择编译器)
  --android <n>      自定义源时声明 Android 版本 (用于选择 Clang 版本)
  --gki              标记为 GKI 通用内核 (默认 LKM 模式)
  --ksu <main|builtin>  SukiSU 集成分支 (默认: GKI 设备=main, 传统内核=builtin)
  --ksu-mode <y|m>    KSU 编译形态: y=内置(默认), m=LKM 模块(GKI 默认)
  --kpm              启用 KPM (CONFIG_KPM=y)
  --debug-ksu        启用 CONFIG_KSU_DEBUG
  --susfs            启用 CONFIG_KSU_SUSFS (要求内核已集成 susfs4ksu 补丁, 否则会失败)
  --clang <分支:目录>  覆盖 Clang 预编译 (如 llvm-r522817:clang-r522817)
  --gcc              强制使用 GCC 4.9 工具链 (老内核)
  --jobs <n>         并行编译数 (默认 nproc)
  --no-pack          只编译不打包
  --resume           复用已存在的 work/kernel 源码
  --clean            开始前清空 work/ 目录
  --yes              跳过确认直接开始
  --dry-run          演练模式: 只解析选择、打印任务, 不下载不编译
  -h, --help         显示本帮助

环境变量:
  EXTRA_MAKE_ARGS    追加透传给 make 的参数 (如 EXTRA_MAKE_ARGS="LLVM_IAS=1")
EOF
}

check_deps() {
  local -a missing=()
  local bin
  for bin in git curl make gcc g++ bc bison flex python3 zip cpio; do
    if ! command -v "$bin" >/dev/null 2>&1; then missing+=("$bin"); fi
  done
  if [ ! -f /usr/include/openssl/ssl.h ]; then missing+=("libssl-dev"); fi
  # libelf 仅 5.4+ 内核开启 CONFIG_DEBUG_INFO_BTF 时才会用到 (resolve_btfids), 缺失只告警
  if [ ! -f /usr/include/libelf.h ] && [ ! -f /usr/include/gelf.h ]; then
    warn "缺少 libelf 头文件 (libelf-dev): 5.4+ 内核若开启 CONFIG_DEBUG_INFO_BTF 会在 tools/bpf/resolve_btfids 处失败"
    echo "    sudo apt install -y libelf-dev"
  fi
  if (( ${#missing[@]} > 0 )); then
    warn "缺少依赖: ${missing[*]}"
    echo "  Debian/Ubuntu 安装命令:"
    echo "    sudo apt update && sudo apt install -y git curl make gcc g++ bc bison flex libssl-dev libncurses-dev zip cpio python3"
    die "请先安装依赖后重试"
  fi
}

load_devices() {
  [ -f "$DEVICES_CONF" ] || die "找不到设备库: $DEVICES_CONF"
  DEV_ROWS=()
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ""|\#*) continue ;; esac
    DEV_ROWS+=("$line")
  done < "$DEVICES_CONF"
  (( ${#DEV_ROWS[@]} > 0 )) || die "设备库为空: $DEVICES_CONF"
}

row_field() {
  local row="$1" idx="$2" f
  IFS='|' read -r -a f <<< "$row"
  echo "${f[$((idx-1))]:-}"
}

# ------- 产物命名 (品牌_机型_机型代码_内核版本_SukiSU版本_日期时间) ----------

# 从设备显示名推导 品牌 + 机型, 输出 "品牌|机型"
# 机型可为空: 自动枚举的设备显示名就是代码, 此时命名里只出现一次代码
derive_brand_model() {
  local disp="$1" id="$2" brand="" model=""
  case "$disp" in
    Redmi\ *)    brand="Redmi";   model="${disp#Redmi }" ;;
    POCO\ *)     brand="POCO";    model="${disp#POCO }" ;;
    Mi\ *)       brand="Xiaomi";  model="${disp#Mi }" ;;
    Xiaomi\ *)   brand="Xiaomi";  model="${disp#Xiaomi }" ;;
    OnePlus\ *)  brand="OnePlus"; model="${disp#OnePlus }" ;;
    通用\ GKI*)  brand="Google";  model="${disp#通用 GKI · }" ;;
  esac
  if [ -z "$brand" ]; then
    case "$SEL_REPO" in
      *OnePlusOSS*)                  brand="OnePlus" ;;
      *aosp-mirror*|*kernel_common*) brand="Google"; model="GKI" ;;
      *)                             brand="Xiaomi" ;;
    esac
  fi
  if [ "$disp" = "$id" ] || [ "$model" = "$id" ]; then model=""; fi
  printf '%s|%s\n' "$brand" "$model"
}

# 文件名安全化: 空白与 / 保留语义(变 +), 其余非法字符变 _, 合并连续 _
sanitize_name() {
  printf '%s' "$1" \
    | sed -e 's/[[:space:]]*\/[[:space:]]*/+/g' \
          -e 's/[^A-Za-z0-9._+-]/_/g' \
          -e 's/__*/_/g' -e 's/^_//' -e 's/_$//'
}

# 解析 SukiSU 版本 (best-effort): git describe > 短提交 > unknown
# setup.sh 的浅克隆常常没有 tag (describe 只回落到提交号), 此时补拉一次 tag 再描述,
# 让产物名/发布说明里带上语义版本, 例如 v3.0.0_4bec532
resolve_ksu_version() {
  local d="$KERNEL_DIR/KernelSU" v="" v2=""
  if [ -d "$d/.git" ]; then
    v="$(git -C "$d" describe --tags --always 2>/dev/null || true)"
    case "$v" in
      ""|*-g*) : ;;               # 空 或 已带 -g<hash> (说明有 tag)
      *)                            # 纯提交号 => 浅克隆缺 tag, 补拉后重试
         git -C "$d" fetch --tags --depth=1 origin >/dev/null 2>&1 || true
         v2="$(git -C "$d" describe --tags --always 2>/dev/null || true)"
         [ -n "$v2" ] && v="$v2" ;;
    esac
    case "$v" in
      *-g[0-9a-f]*-g*) : ;;
      *-g[0-9a-f]*)                 # v3.0.0-12-g4bec532 => v3.0.0_4bec532
         v="$(printf '%s' "$v" | sed -E 's/-[0-9]+-g([0-9a-f]+)$/_\1/')" ;;
    esac
    [ -n "$v" ] || v="$(git -C "$d" rev-parse --short HEAD 2>/dev/null || true)"
  fi
  [ -n "$v" ] || v="unknown"
  sanitize_name "$v"
}

# 产物基础名: 品牌_机型_机型代码_内核版本_SukiSU-<版本>_<北京时间>
# 可选参数 3~5: 内核版本 / 时间戳 / SukiSU 版本 (预览用占位符)
build_artifact_base() {
  local brand="$1" model="$2"
  local kver="${3:-$KVER}"
  local ts="${4:-$(TZ=Asia/Shanghai date +%Y%m%d-%H%M)}"
  local ksuv="${5:-${KSU_VERSION:-unknown}}"
  local -a p=()
  [ -n "$brand" ] && p+=("$(sanitize_name "$brand")")
  [ -n "$model" ] && p+=("$(sanitize_name "$model")")
  p+=("$(sanitize_name "$SEL_DEVICE_ID")")
  p+=("$(sanitize_name "$kver")")
  p+=("SukiSU-$(sanitize_name "$ksuv")")
  p+=("$(sanitize_name "$ts")")
  local IFS=_
  printf '%s\n' "${p[*]}" | sed 's/__*/_/g'
}

# 生成发布备注 (output/release-notes.md) 与产物清单 (output/LAST_ARTIFACT)
write_release_notes() {
  local base="$1" art="$2" kind="AnyKernel3 刷机包 (zip)"
  [ "$KSU_MODE" = m ] && kind="LKM 模块 (kernelsu.ko)"
  {
    echo "## ${base}"
    echo
    echo "| 项目 | 内容 |"
    echo "|---|---|"
    echo "| 品牌 / 机型 | ${BUILD_BRAND} ${BUILD_MODEL} (${SEL_DEVICE_ID}) |"
    echo "| 内核版本 | ${KVER} |"
    echo "| Android 版本 | ${SEL_ANDROID} |"
    echo "| 内核源码 | ${SEL_REPO} @ ${SEL_BRANCH} |"
    echo "| SukiSU-Ultra | ${KSU_BRANCH} 分支 · CONFIG_KSU=${KSU_MODE} · 版本 ${KSU_VERSION} |"
    echo "| 产物类型 | ${kind} |"
    echo "| 编译时间 | $(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S') (UTC+8) |"
    echo "| 编译环境 | GitHub Actions · ubuntu-latest |"
    echo
    echo "### 安装说明"
    echo
    if [ "$KSU_MODE" = m ]; then
      echo "1. 安装 SukiSU-Ultra 管理器 App;"
      echo "2. 管理器 → 安装 → 选择「使用本地 LKM 文件」, 选中本 .ko (需与设备 KMI 匹配);"
      echo "3. 重启后打开管理器确认工作状态。"
    else
      echo "1. 先备份原机 boot 分区 (TWRP 备份或用工具导出);"
      echo "2. 用 TWRP 等支持 AnyKernel3 的 Recovery 刷入本 zip;"
      echo "3. 重启后安装 SukiSU-Ultra 管理器 App 并确认;"
      echo "4. 若卡第一屏, 用备份恢复 boot 分区。"
    fi
    echo
    echo "### 说明"
    echo
    echo "- 由 [SukiSU-Ultra 内核编译工具](https://github.com/xingyiqaq/sukisu-kernel-builder) 自动构建;"
    echo "- 源码取自上述开源内核仓库, 未包含闭源组件; 仅供个人学习研究使用;"
    echo "- 刷机有风险, 请自行承担。"
  } > "$OUTPUT_DIR/release-notes.md"
  printf '%s\n' "$art" > "$OUTPUT_DIR/LAST_ARTIFACT"
}


list_devices() {
  local row
  echo
  echo "设备库 (共 ${#DEV_ROWS[@]} 条):"
  printf "%-10s %-8s %-40s %-32s %s\n" "设备ID" "Android" "型号" "内核版本" "分支"
  echo "------------------------------------------------------------------------------------------------------------------"
  for row in "${DEV_ROWS[@]}"; do
    printf "%-10s %-8s %-40s %-32s %s\n" \
      "$(row_field "$row" 1)" "$(row_field "$row" 7)" "$(row_field "$row" 3)" \
      "$(row_field "$row" 2)" "$(row_field "$row" 5)"
  done
  echo
  echo "用法示例:"
  echo "  ./build.sh --device alioth --version 1 --ksu main"
  echo "  ./build.sh --branch oneplus/SM8250_R_11.0 --ksu builtin"
  echo
}

# 交互式选择菜单: 打印列表(走 stderr), 返回所选条目在 items 中的 1 基序号(走 stdout)。
# 支持关键词过滤; q 退出 → 返回码 2。
menu_select() {
  local title="$1"; shift
  local -a items=("$@")
  local ans i sel n
  while :; do
    echo >&2
    echo >&2 "  $title"
    for ((i=0; i<${#items[@]}; i++)); do
      printf >&2 "  %3d) %s\n" $((i+1)) "${items[$i]}"
    done
    echo >&2 "    q) 退出"
    if ! read -rp "  >> 输入编号选择, 或输入关键词过滤 [默认 1]: " ans; then ans=""; fi
    ans="${ans%$'\r'}"
    ans="${ans:-1}"
    case "$ans" in q|Q) echo >&2 "已取消。"; return 2 ;; esac
    if [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= ${#items[@]} )); then
      echo "$ans"; return 0
    fi
    local -a sub=() idx=()
    for ((i=0; i<${#items[@]}; i++)); do
      if [[ "${items[$i],,}" == *"${ans,,}"* ]]; then
        sub+=("${items[$i]}")
        idx+=($((i+1)))
      fi
    done
    if (( ${#sub[@]} == 0 )); then
      echo >&2 "  ! 没有匹配 \"$ans\" 的条目, 请重新输入"
      continue
    fi
    if (( ${#sub[@]} == 1 )); then echo "${idx[0]}"; return 0; fi
    if ! n="$(menu_select "按 \"$ans\" 过滤后的结果:" "${sub[@]}")"; then return 2; fi
    echo "${idx[$((n-1))]}"; return 0
  done
}

# -------------------------------- 选择流程 --------------------------------
choose_device() {
  local -a ids=() items=()
  local row id display
  for row in "${DEV_ROWS[@]}"; do
    id="$(row_field "$row" 1)"
    if [[ ! " ${ids[*]} " == *" $id "* ]]; then
      ids+=("$id")
      items+=("$(row_field "$row" 3)")
    fi
  done
  local sel
  if ! sel="$(menu_select "请选择设备型号:" "${items[@]}")"; then exit 0; fi
  SEL_DEVICE_ID="${ids[$((sel-1))]}"
}

choose_version() {
  local -a rows=() labels=()
  local row id i
  for row in "${DEV_ROWS[@]}"; do
    id="$(row_field "$row" 1)"
    if [[ "$id" == "$SEL_DEVICE_ID" ]]; then
      rows+=("$row")
      labels+=("$(row_field "$row" 2)")
    fi
  done
  if (( ${#rows[@]} == 0 )); then
    die "设备库中没有设备 ID: $SEL_DEVICE_ID (用 --list 查看)"
  fi
  local idx=""
  if [ "$OPT_BRANCH_GIVEN" = 1 ]; then
    for ((i=0; i<${#rows[@]}; i++)); do
      if [[ "$(row_field "${rows[$i]}" 5)" == "$SEL_BRANCH" ]]; then idx=$((i+1)); break; fi
    done
    [ -n "$idx" ] || die "--branch $SEL_BRANCH 不属于设备 $SEL_DEVICE_ID"
  elif [ -n "$OPT_VERSION" ]; then
    idx="$OPT_VERSION"
  elif (( ${#rows[@]} == 1 )); then
    idx=1
  else
    local sel
    if ! sel="$(menu_select "为 $SEL_DEVICE_ID 选择内核版本:" "${labels[@]}")"; then exit 0; fi
    idx="$sel"
  fi
  if ! [[ "$idx" =~ ^[0-9]+$ ]] || (( idx < 1 || idx > ${#rows[@]} )); then
    die "--version $idx 超出范围 (该设备共 ${#rows[@]} 个版本)"
  fi
  SEL_ROW="${rows[$((idx-1))]}"
  SEL_VERLABEL="$(row_field "$SEL_ROW" 2)"
  SEL_DISPLAY="$(row_field "$SEL_ROW" 3)"
  SEL_REPO="$(row_field "$SEL_ROW" 4)"
  SEL_BRANCH="$(row_field "$SEL_ROW" 5)"
  SEL_KVER="$(row_field "$SEL_ROW" 6)"
  SEL_ANDROID="$(row_field "$SEL_ROW" 7)"
  SEL_GKI="$(row_field "$SEL_ROW" 8)"
  SEL_DEFCONFIG="$(row_field "$SEL_ROW" 9)"
}

choose_ksu_branch() {
  if [ -z "$KSU_BRANCH" ]; then
    # 默认: GKI → main (kprobes 运行时 hook); 非 GKI 老内核 → builtin (backslashxx 式, 官方 4.4+ 兼容分支)
    if [ "$SEL_GKI" = 1 ]; then KSU_BRANCH=main; else KSU_BRANCH=builtin; fi
    info "集成分支(自动): $KSU_BRANCH (GKI 设备用 main, 传统内核用 builtin; 可用 --ksu 覆盖)"
  fi
  case "$KSU_BRANCH" in main|builtin) ;; *) die "--ksu 只能是 main 或 builtin" ;; esac
  if [ -z "$KSU_MODE" ]; then
    if [ "$SEL_GKI" = 1 ]; then KSU_MODE=m; else KSU_MODE=y; fi
  fi
  case "$KSU_MODE" in y|m) ;; *) die "--ksu-mode 只能是 y(内置) 或 m(LKM 模块)" ;; esac
  if [ "$KSU_BRANCH" = builtin ] && [ "$KSU_MODE" = m ]; then
    warn "builtin 分支的 CONFIG_KSU 是 bool 类型, 不支持 LKM (m), 已强制为 y"
    KSU_MODE=y
  fi
  if [ "$KSU_MODE" = m ] && [ "$SEL_GKI" != 1 ]; then
    warn "非 GKI 内核使用 LKM 模式 (CONFIG_KSU=m) 可能无法正常工作, 建议改用 --ksu-mode y"
  fi
}

# -------------------------------- 工具链 ----------------------------------
# AOSP 已于 2024 年删除全部 clang-r* 分支, 现在每个版本是 llvm-r* 分支下的
# clang-r* 子目录 (分支与目录已逐一核实, 见 2026-11 实测):
#   版本 → llvm 分支:clang 目录
#   r353983c → llvm-r365631:clang-r353983c
#   r370808  → llvm-r416183:clang-r370808
#   r416183b → llvm-r450784:clang-r416183b
#   r450784d → llvm-r487747:clang-r450784d1
#   r487747c → llvm-r510928:clang-r487747c
#   r510928  → llvm-r510928:clang-r510928
#   r522817  → llvm-r522817:clang-r522817
# 下载用 gitiles 子目录 tarball: +archive/refs/heads/<分支>/<目录>.tar.gz
clang_spec_candidates() {
  case "$1" in
    1[5-9]) echo "llvm-r522817:clang-r522817 llvm-r510928:clang-r510928" ;;
    14)     echo "llvm-r510928:clang-r510928 llvm-r487747:clang-r487747b" ;;
    13)     echo "llvm-r510928:clang-r487747c llvm-r487747:clang-r487747" ;;
    12)     echo "llvm-r487747:clang-r450784d1 llvm-r487747:clang-r450784e llvm-r450784:clang-r450784b" ;;
    11)     echo "llvm-r450784:clang-r416183b llvm-r416183:clang-r416183" ;;
    10)     echo "llvm-r416183:clang-r370808 llvm-r365631:clang-r365631b" ;;
    *)      echo "llvm-r365631:clang-r353983c llvm-r353983:clang-r353983b" ;;
  esac
}

decide_toolchain() {
  USE_CLANG=1
  if [ "$OPT_GCC" = 1 ]; then
    USE_CLANG=0
    return 0
  fi
  local kv maj min
  kv="$(echo "$SEL_KVER" | grep -oE '[0-9]+\.[0-9]+' | head -n1 || true)"
  maj="${kv%%.*}"; min="${kv##*.}"
  if [ -z "$maj" ] || [ -z "$min" ]; then
    warn "未知内核版本, 默认使用 Clang"
    return 0
  fi
  if [ "$maj" -lt 4 ] || { [ "$maj" -eq 4 ] && [ "$min" -lt 14 ]; }; then
    USE_CLANG=0
    warn "内核 $kv < 4.14, 自动改用 GCC 4.9 工具链"
  fi
}

setup_toolchain() {
  mkdir -p "$TOOLCHAIN_DIR"
  if [ "$USE_CLANG" = 1 ]; then
    CLANG_DIR="$TOOLCHAIN_DIR/clang"
    if [ ! -x "$CLANG_DIR/bin/clang" ]; then
      info "下载 Clang 工具链, 约 1~2 GB, 请耐心等待..."
      rm -rf "$CLANG_DIR.tmp" "$CLANG_DIR.tar"
      local ok=0 spec br dir url
      if [ -n "$OPT_CLANG" ]; then
        set -- "$OPT_CLANG"      # --clang 用户指定: 分支:目录
      else
        set -- $(clang_spec_candidates "$SEL_ANDROID")
      fi
      for spec in "$@"; do
        br="${spec%%:*}"; dir="${spec##*:}"
        if [ -z "$br" ] || [ -z "$dir" ] || [ "$br" = "$dir" ]; then
          warn "忽略无效的 Clang 规格: $spec (应为 分支:目录)"
          continue
        fi
        info "下载 $br/$dir ..."
        url="$CLANG_REPO/+archive/refs/heads/$br/$dir.tar.gz"
        if curl -fL --retry 3 --connect-timeout 30 --speed-time 60 -o "$CLANG_DIR.tar" "$url"; then
          mkdir -p "$CLANG_DIR.tmp"
          if tar -xzf "$CLANG_DIR.tar" -C "$CLANG_DIR.tmp" 2>/dev/null; then
            if [ -x "$CLANG_DIR.tmp/$dir/bin/clang" ]; then
              mv "$CLANG_DIR.tmp/$dir" "$CLANG_DIR"; ok=1; break
            elif [ -x "$CLANG_DIR.tmp/bin/clang" ]; then
              mv "$CLANG_DIR.tmp" "$CLANG_DIR"; ok=1; break
            fi
          fi
        fi
        warn "规格 $spec 下载或解压失败, 尝试下一个..."
        rm -rf "$CLANG_DIR.tmp" "$CLANG_DIR.tar"
      done
      rm -f "$CLANG_DIR.tar"
      if [ "$ok" != 1 ]; then
        rm -rf "$CLANG_DIR.tmp"
        die "Clang 下载失败: 尝试过的规格 [$*] 均不可用 (可用 --clang 分支:目录 覆盖)"
      fi
    else
      info "复用已下载的 Clang: $CLANG_DIR"
    fi
  fi
  # GCC 4.9 (clang 经典模式也需要它的 binutils 作交叉前缀)
  # 优先 LineageOS 的 GitHub 镜像 (快且稳定), 失败回退 googlesource
  GCC64_DIR="$TOOLCHAIN_DIR/gcc-arm64"
  if [ ! -x "$GCC64_DIR/bin/aarch64-linux-android-gcc" ]; then
    info "下载 GCC 4.9 (aarch64-linux-android) ..."
    rm -rf "$GCC64_DIR.tmp"
    if ! git clone --depth 1 -b "$GCC_MIRROR_BR" "$GCC64_MIRROR" "$GCC64_DIR.tmp" \
      && ! git clone --depth 1 "$GCC64_REPO" "$GCC64_DIR.tmp"; then
      rm -rf "$GCC64_DIR.tmp"
      die "GCC aarch64 4.9 下载失败"
    fi
    mv "$GCC64_DIR.tmp" "$GCC64_DIR"
  fi
  GCC32_DIR="$TOOLCHAIN_DIR/gcc-arm32"
  if [ ! -x "$GCC32_DIR/bin/arm-linux-androideabi-gcc" ]; then
    info "下载 GCC 4.9 (arm-linux-androideabi) ..."
    rm -rf "$GCC32_DIR.tmp"
    if ! git clone --depth 1 -b "$GCC_MIRROR_BR" "$GCC32_MIRROR" "$GCC32_DIR.tmp" \
      && ! git clone --depth 1 "$GCC32_REPO" "$GCC32_DIR.tmp"; then
      rm -rf "$GCC32_DIR.tmp"
      die "GCC arm 4.9 下载失败"
    fi
    mv "$GCC32_DIR.tmp" "$GCC32_DIR"
  fi

  # 把 Android GCC 的 binutils 暴露成 aarch64-linux-gnu-* / arm-linux-gnueabi-* 前缀链接:
  # 老内核 (如 4.14) 的 vdso 用 $(CC) 直接链接, clang 会按 triple 前缀去找 GNU ld,
  # 找不到时回退主机 x86 ld.bfd → "unrecognised emulation mode: aarch64linux";
  # LLVM=1 模式下 kbuild 也需要从 CROSS_COMPILE 推导 --target, 统一用 gnu triples 最稳。
  local LINKBIN="$TOOLCHAIN_DIR/bin" t
  mkdir -p "$LINKBIN"
  for t in ld as ar nm objcopy objdump ranlib readelf strip; do
    if [ -x "$GCC64_DIR/bin/aarch64-linux-android-$t" ]; then
      ln -sf "$GCC64_DIR/bin/aarch64-linux-android-$t" "$LINKBIN/aarch64-linux-gnu-$t"
    fi
    if [ -x "$GCC32_DIR/bin/arm-linux-androideabi-$t" ]; then
      ln -sf "$GCC32_DIR/bin/arm-linux-androideabi-$t" "$LINKBIN/arm-linux-gnueabi-$t"
    fi
  done
  export PATH="$LINKBIN:$PATH"
}

# -------------------------------- 内核源码 --------------------------------
# 老内核与新工具链 (bison 3.8+ / flex 2.6+ / clang IAS / 新版主机头) 的兼容修复
compat_fixups() {
  cd "$KERNEL_DIR"
  # dtc-lexer.l 里定义了全局 yylloc, 而 bison 3.8+ 生成的 parser 也会定义一份 → 链接期重复定义
  if grep -q '^YYLTYPE yylloc;' scripts/dtc/dtc-lexer.l 2>/dev/null; then
    info "兼容修复: dtc-lexer.l 的 yylloc 改为 extern (bison 3.8+ 重复定义冲突)"
    sed -i 's/^YYLTYPE yylloc;/extern YYLTYPE yylloc;/' scripts/dtc/dtc-lexer.l
  fi
  # 4.14 等老树还带 flex/bison 预生成文件 (*_shipped), make 有时直接用它们 → 同样处理
  local f
  for f in scripts/dtc/dtc-lexer.lex.c_shipped scripts/dtc/dtc-lexer.lex.c; do
    if [ -f "$f" ] && grep -q '^YYLTYPE yylloc;' "$f"; then
      info "兼容修复: ${f} 的 yylloc 改为 extern (预生成 lexer 与 bison 3.8 parser 冲突)"
      sed -i 's/^YYLTYPE yylloc;/extern YYLTYPE yylloc;/' "$f"
    fi
  done
  # selinux classmap.h 的 "PF_MAX > N" 维护性断言: 主机内核头比内核树新时 (runner 上是 6.x 头)
  # genheaders 会误报 #error New address family defined → 注释掉该断言 (只影响维护提示, 不影响生成内容)
  local cm=security/selinux/include/classmap.h
  if [ -f "$cm" ] && grep -q '^#error New address family defined' "$cm"; then
    info "兼容修复: security/selinux/include/classmap.h 注释 PF_MAX 上限断言 (主机头较新时 genheaders 误报)"
    sed -i 's@^#error New address family defined.*@/* & */@' "$cm"
  fi
  # 老 arm64 vdso (<=4.14) 用 GNU as 的 "宏名, 形参=值" 形式 (前导逗号), clang 集成汇编器不支持
  # → 报 "too many positional arguments"; 去掉前导逗号改成标准的 "宏名 形参=值"
  local vd=arch/arm64/kernel/vdso/gettimeofday.S
  if [ -f "$vd" ] && grep -q 'clock_gettime_return, shift=' "$vd"; then
    info "兼容修复: arch/arm64/kernel/vdso/gettimeofday.S 去掉宏调用前导逗号 (clang IAS 兼容)"
    sed -i 's/clock_gettime_return, shift=/clock_gettime_return shift=/g' "$vd"
  fi
  # 厂商驱动的 Makefile 常自带 subdir-ccflags-y := -Werror (如 drivers/misc/mediatek/Makefile),
  # 会把 clang 独有告警 (pointer-to-int-cast 等) 升格成错误, 而 gcc 构建不报 →
  # 老厂商树用 clang 编不过 (run #40/#47: agate 的 mediatek eccci)。从 ccflags 行里剥掉 -Werror。
  local mkvm mknum=0
  while IFS= read -r mkvm; do
    sed -i -E 's/^((subdir-)?ccflags[-A-Za-z0-9_$()]*[[:space:]]*[:+]?=[^#]*)[[:space:]]-Werror/\1/g' "$mkvm" 2>/dev/null && mknum=$((mknum+1))
  done < <(find drivers arch/arm64 -name 'Makefile' -exec grep -lE '^(subdir-)?ccflags[-A-Za-z0-9_$()]*[[:space:]]*[:+]?=.*-Werror' {} + 2>/dev/null || true)
  if [ "$mknum" -gt 0 ]; then
    info "兼容修复: 移除 $mknum 个厂商 Makefile 的 ccflags -Werror (clang 专属告警在 gcc 下只是警告)"
  fi
  # 部分厂商树直接 #include 未公开的闭源固件数组 (*.i, 如 focaltech 触摸的 fw_sample.i、
  # himax 的 HX83100_Firmware_Version_*.i、dandelion 的 fw_helitai_v0e.i), 公开源码里没有该
  # 文件 → fatal error: 'xxx.i' file not found, 整台设备编译失败 (批跑: 4.14.186 十台全挂在这)。
  # 这类 .i 只被当作 `u8 fw_file[] = { #include "x.i" };` 的字节初始化表用, 编译期内容多为
  # "失效样本"(厂商注释原话 the sample one is invalid), 运行时由 request_firmware 加载真实固件
  # → 写入占位字节即可让驱动编译通过。
  local hit hf hcontent trimmed hp blobn=0 hrel
  # 只认"行内容本身以 #include 开头"的真引用; 注释里的 #include (如 `* *#include "x.i"`,
  # `// #include "x.i"`) 一律跳过 —— run #72/73/76 的教训: 直接把 grep 原始行当路径,
  # 拼出 `…/68:/* #include "ft5x0x_fw_6127_ht.i" */` 这种目录名 → printf 报 Is a directory
  # → build.sh 直接 exit 1, 设备在 fixup 阶段秒退。
  while IFS= read -r hit; do
    hf="${hit%%:*}"
    hcontent="${hit#*:}"; hcontent="${hcontent#*:}"   # 丢掉 grep -n 的行号
    trimmed="${hcontent#"${hcontent%%[![:space:]]*}"}"
    [[ "$trimmed" == '#include'* ]] || continue
    [[ "$trimmed" == *'.i"'* ]] || continue
    hrel="${trimmed#*\"}"; hrel="${hrel%%\"*}"
    [[ "$hrel" == *.i ]] || continue
    hp="$(dirname "$hf")/$hrel"
    if [ -d "$hp" ]; then continue; fi
    if [ ! -e "$hp" ] && [ ! -e "$hrel" ]; then
      mkdir -p "$(dirname "$hp")"
      printf '0x00, 0x00, 0x00, 0x00\n' > "$hp"
      warn "厂商源码缺失闭源固件: ${hf#$KERNEL_DIR/} → $hrel —— 已写入占位字节 (仅用于编译通过, 运行时由 firmware 加载真实固件)"
      blobn=$((blobn+1))
    fi
  done < <(grep -rIn --include='*.c' --include='*.h' -E '^[[:space:]]*#include[[:space:]]*"[^"]+\.i"' drivers 2>/dev/null || true)
  if [ "$blobn" -gt 0 ]; then
    warn "以上闭源固件缺失共 $blobn 处, 已用占位字节兜底 (厂商源码不完整)"
  fi
  # focaltech_spi 触摸驱动把 FTS_UPGRADE_FW_FILE 指向 include/firmware/fw_sample.i,
  # 而 Xiaomi 从未公开该样本 (focaltech_config.h 注释: "the sample one to be replaced is invalid"),
  # 厂商构建时用自家固件替换; 公开树直接编会 fatal error: 'include/firmware/fw_sample.i' not found
  # (批跑: ares 等 4.14.186 十台设备全挂在这)。FTS_FW_REQUEST_SUPPORT=1 时运行时会从
  # firmware 目录加载真实固件, 编译期内嵌样本只是兜底 → 写入占位字节让驱动能编译。
  local fcfg=drivers/input/touchscreen/focaltech_spi/focaltech_config.h
  if [ -f "$fcfg" ]; then
    local fw fw2
    while IFS= read -r fw; do
      [ -n "$fw" ] || continue
      # 引号 include 先按"源文件所在目录"解析 → 驱动目录下那份是编译时真正要的;
      # 同时补一份相对内核树根的路径 (部分厂商代码用 -I 根目录写法)。
      for fw2 in "drivers/input/touchscreen/focaltech_spi/$fw" "$fw"; do
        if [ ! -e "$fw2" ]; then
          mkdir -p "$(dirname "$fw2")"
          printf '0x00, 0x00, 0x00, 0x00\n' > "$fw2"
          warn "厂商源码缺失闭源固件样本: $fw2 -> 已写入占位字节 (驱动可编译, 运行时由 firmware 加载真实固件)"
        fi
      done
    done < <(grep -E '^#define[[:space:]]+FTS_UPGRADE_FW[0-9]*_FILE[[:space:]]+"[^"]+"' "$fcfg" \
               | sed -E 's/.*"([^"]+)".*/\1/' | sort -u 2>/dev/null || true)
  fi
  # include/linux/input/qpnp-power-on.h 的 #else 分支 (CONFIG_INPUT_QPNP_POWER_ON 未开) 里
  # qpnp_pon_wd_config 是非 static 定义 → 每个包含该头的 .c 各生成一份 → vmlinux 链接重复定义
  # (run #56: veux 5.4 的 panic.o 与 arch/arm64/kernel/bootinfo.o)。声明行带分号不受影响, 只改定义行。
  local qpon=include/linux/input/qpnp-power-on.h
  if [ -f "$qpon" ] && grep -qE '^int qpnp_pon_wd_config\(bool enable\)[[:space:]]*$' "$qpon"; then
    info "兼容修复: qpnp-power-on.h 的 qpnp_pon_wd_config 定义加 static (多 TU 重复定义冲突)"
    sed -i -E 's/^int qpnp_pon_wd_config\(bool enable\)[[:space:]]*$/static int qpnp_pon_wd_config(bool enable)/' "$qpon"
  fi
}

# 小米公开源码树常引用未公开的 vendor 驱动 Kconfig (如 drivers/misc/hwid/Kconfig),
# 导致 olddefconfig 直接报 "can't open file" (run #20/#21 marble)。把指向不存在
# 路径的 source 行注释掉 (Kconfig source 路径相对内核树根)。
# 注意 (run #24/#25 教训): 绝不能动带变量的引用, 如 source "arch/$(SRCARCH)/Kconfig"
# —— 字面存在性检查必然失败, 误注释会断开整个 Kconfig 树 (arch/arm64/Kconfig 不被加载,
# CONFIG_ARM64/CONFIG_64BIT 全部丢失, 表现为 atomic64_t 未定义)。同理只处理带 "/"
# 的真实路径, 避免误伤 scripts/kconfig/tests 里的夹具。
fix_missing_kconfig_sources() {
  cd "$KERNEL_DIR"
  local list_file missing_file cnt total
  list_file="$(mktemp)"; missing_file="$(mktemp)"
  grep -rhoE '^[[:space:]]*source[[:space:]]+"[^"]+"' --include='Kconfig*' . 2>/dev/null \
    | sed -E 's/^[[:space:]]*source[[:space:]]+"([^"]+)"/\1/' | sort -u > "$list_file" || true
  total=0; cnt=0
  while IFS= read -r p; do
    case "$p" in
      *'$'*|*'{'*|*'}'*|/*) continue ;;   # 变量/绝对路径: 无法用字面判断, 跳过
    esac
    case "$p" in
      */*) ;;                             # 必须是带 "/" 的真实路径
      *) continue ;;
    esac
    total=$((total+1))
    [ -e "$p" ] || { printf '%s\n' "$p" >> "$missing_file"; cnt=$((cnt+1)); }
  done < "$list_file"
  if [ "$cnt" -eq 0 ]; then
    rm -f "$list_file" "$missing_file"
    return 0
  fi
  warn "内核树引用了 $cnt 个不存在的 Kconfig 目录 (厂家未公开 vendor 驱动), 将注释对应 source 行: $(head -n3 "$missing_file" | tr '\n' ' ')"
  while IFS= read -r f; do
    awk -v miss="$missing_file" '
      BEGIN { while ((getline l < miss) > 0) M[l] = 1 }
      {
        if (match($0, /source[[:space:]]+"[^"]+"/)) {
          p = substr($0, RSTART, RLENGTH)
          sub(/^[^"]*"/, "", p); sub(/".*$/, "", p)
          if (p in M) { print "# " $0; next }
        }
        print
      }' "$f" > "$f.dsh.tmp" && mv "$f.dsh.tmp" "$f"
  done < <(grep -rlE '^[[:space:]]*source[[:space:]]+"' --include='Kconfig*' . 2>/dev/null)
  rm -f "$list_file" "$missing_file"
  ok "已注释 $cnt 处缺失 Kconfig 引用"
}

# 厂商私有子树未公开时, 除了 Kconfig 的 source 行, Makefile 里的
# `obj-y += hwid/` 之类子目录也会导致 "No rule to make target .../hwid/Makefile"
# (run: ingres 5.10.43)。这里把指向不存在目录的 obj-/subdir- 行注释掉。
# 只处理 drivers/ 与 arch/arm64/ 下的 Makefile, 含变量的条目跳过。
fix_missing_makefile_objs() {
  cd "$KERNEL_DIR"
  local files f cnt=0
  files="$(grep -rlE '^[[:space:]]*(obj|subdir)-[A-Za-z0-9_$()]*[[:space:]]*[:+]?=[^#]*/' \
    --include='Makefile' --include='Makefile.*' drivers arch/arm64 2>/dev/null || true)"
  [ -n "$files" ] || return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    awk -v dir="$(dirname "$f")" '
      BEGIN { bad = 0 }
      {
        line = $0
        if (line ~ /^[[:space:]]*#/) { print line; next }
        if (match(line, /^[[:space:]]*(obj|subdir)-[A-Za-z0-9_$()]*[[:space:]]*[:+]?=[[:space:]]*/)) {
          rhs = substr(line, RLENGTH + 1)
          # 含 make 变量/函数/引号的行无法按字面路径判断, 整行跳过。
          # 教训 (ares 等 MTK 4.14): `obj-y += $(subst ",,mt6885)/` 按空格拆成
          # `$(subst` 与 `",,mt6885)/` 两块, 后者不含 $ 却像目录 → 被误注释 →
          # 平台 HAL 目录不再编译 → vmlinux 链接缺 mt_*_hal 等符号。
          if (rhs ~ /[$"()]/) { print line; next }
          if (rhs ~ /[[:space:]]*$/) {
            n = split(rhs, w, /[[:space:]]+/)
            hit = 0
            for (i = 1; i <= n; i++) {
              p = w[i]
              if (p == "" || p ~ /^#/) break
              sub(/\\$/, "", p)
              if (p !~ /\/$/ || p ~ /\$/) continue
              if (system("test -d \"" dir "/" p "\"") != 0) hit = 1
            }
            if (hit) { print "# " line; next }
          }
        }
        print line
      }' "$f" > "$f.dsh.tmp"
    if [ -s "$f.dsh.tmp" ] && ! cmp -s "$f" "$f.dsh.tmp"; then
      mv "$f.dsh.tmp" "$f"
      cnt=$((cnt+1))
    else
      rm -f "$f.dsh.tmp"
    fi
  done <<< "$files"
  [ "$cnt" -gt 0 ] && ok "已注释 $cnt 个 Makefile 中指向缺失目录的 obj-/subdir- 条目"
  return 0
}

fetch_kernel() {
  local repo="$SEL_REPO"
  [[ "$repo" == *.git ]] || repo="${repo}.git"
  if [ -d "$KERNEL_DIR/.git" ]; then
    if [ "$OPT_RESUME" = 1 ]; then
      local cur
      cur="$(cd "$KERNEL_DIR" && git rev-parse --abbrev-ref HEAD)"
      info "复用已有内核源码: $KERNEL_DIR (当前分支: $cur)"
      return 0
    fi
    die "$KERNEL_DIR 已存在。重新开始请先删除该目录; 想复用请加 --resume"
  fi
  if [ "$OPT_CLEAN" = 1 ]; then rm -rf "$BASE_DIR"; fi
  mkdir -p "$BASE_DIR"
  info "克隆内核源码: $repo"
  info "  分支: $SEL_BRANCH (--depth 1)"
  rm -rf "$KERNEL_DIR"
  if ! git clone --depth 1 --single-branch -b "$SEL_BRANCH" "$repo" "$KERNEL_DIR"; then
    die "内核源码克隆失败: 检查分支名/网络 (分支: $SEL_BRANCH)"
  fi
}

detect_kver() {
  local v p s
  v="$(sed -n 's/^VERSION[[:space:]]*=[[:space:]]*//p' "$KERNEL_DIR/Makefile" | head -n1)"
  p="$(sed -n 's/^PATCHLEVEL[[:space:]]*=[[:space:]]*//p' "$KERNEL_DIR/Makefile" | head -n1)"
  s="$(sed -n 's/^SUBLEVEL[[:space:]]*=[[:space:]]*//p' "$KERNEL_DIR/Makefile" | head -n1)"
  KVER="${v}.${p}.${s}"
  if [ "$KVER" = ".." ]; then
    KVER="${SEL_KVER:-unknown}"
    warn "无法从 Makefile 解析内核版本, 使用提示值: $KVER"
  else
    info "检测到内核版本: $KVER"
  fi
}

# ------------------------------ SukiSU 集成 -------------------------------
integrate_sukisu() {
  (
    cd "$KERNEL_DIR"
    info "集成 SukiSU-Ultra (分支: $KSU_BRANCH) ..."
    if [ "$KSU_BRANCH" = main ]; then
      # main: 先尝试官方 setup.sh (zako 私有源, runner 可达但可能不稳), 失败回退 GitHub 手动集成
      info "  尝试官方 setup.sh: curl .../setup.sh | bash -s $KSU_BRANCH"
      if curl -LSs "$SUKISU_SETUP_URL" | bash -s "$KSU_BRANCH" >>"$LOG_FILE" 2>&1; then
        ok "官方 setup.sh 集成成功"
        return 0
      fi
      warn "官方 setup.sh 失败(其私有 Git 源可能不可达), 改用 GitHub 手动集成... (日志: $LOG_FILE)"
      tail -n 5 "$LOG_FILE" >&2 || true
    fi
    # builtin: 官方 setup.sh 指向 zako 私有源且默认拉 main, 直接走 GitHub 手动集成 (确定性最高)
    if [ ! -d KernelSU/.git ]; then
      rm -rf KernelSU
      info "克隆 SukiSU 源码: $SUKISU_REPO (分支 $KSU_BRANCH)"
      if ! git clone --depth 1 -b "$KSU_BRANCH" "$SUKISU_REPO" KernelSU; then
        die "SukiSU 源码克隆失败"
      fi
    fi
    # 与官方 setup.sh 相同的三处补丁
    ln -sf "$(realpath --relative-to=drivers KernelSU/kernel)" drivers/kernelsu
    if ! grep -q "drivers/kernelsu" drivers/Makefile; then
      printf 'obj-$(CONFIG_KSU) += kernelsu/\n' >> drivers/Makefile
    fi
    if ! grep -q 'source "drivers/kernelsu/Kconfig"' drivers/Kconfig; then
      sed -i '/^endmenu$/i source "drivers/kernelsu/Kconfig"' drivers/Kconfig
    fi
    ok "手动集成完成 (KernelSU/kernel → drivers/kernelsu, Makefile/Kconfig 已打补丁)"
  )
}

# 集成后的 SukiSU 源码兼容修复 (依赖 KVER, 须在 detect_kver + integrate_sukisu 之后调用)
ksu_compat_fixups() {
  local kd="$KERNEL_DIR/drivers/kernelsu"
  [ -d "$kd" ] || return 0
  local maj min
  maj="${KVER%%.*}"
  min="$(echo "$KVER" | sed -n 's/^[0-9]*\.\([0-9]*\).*/\1/p')"
  # ltXX=1 表示 kver < X.Y (maj/min 由 Makefile 解析而来, 均为数字)
  local lt411=0 lt51=0 lt52=0 lt54=0 lt55=0 lt58=0 lt59=0 lt511=0
  if { [ "$maj" -lt 4 ] 2>/dev/null; } || { [ "$maj" = 4 ] && [ "${min:-0}" -lt 11 ]; }; then lt411=1; fi
  if { [ "$maj" -lt 5 ] 2>/dev/null; } || { [ "$maj" = 5 ] && [ "${min:-0}" -lt 1 ]; }; then lt51=1; fi
  if { [ "$maj" -lt 5 ] 2>/dev/null; } || { [ "$maj" = 5 ] && [ "${min:-0}" -lt 2 ]; }; then lt52=1; fi
  if { [ "$maj" -lt 5 ] 2>/dev/null; } || { [ "$maj" = 5 ] && [ "${min:-0}" -lt 4 ]; }; then lt54=1; fi
  if { [ "$maj" -lt 5 ] 2>/dev/null; } || { [ "$maj" = 5 ] && [ "${min:-0}" -lt 5 ]; }; then lt55=1; fi
  if { [ "$maj" -lt 5 ] 2>/dev/null; } || { [ "$maj" = 5 ] && [ "${min:-0}" -lt 8 ]; }; then lt58=1; fi
  if { [ "$maj" -lt 5 ] 2>/dev/null; } || { [ "$maj" = 5 ] && [ "${min:-0}" -lt 9 ]; }; then lt59=1; fi
  if { [ "$maj" -lt 5 ] 2>/dev/null; } || { [ "$maj" = 5 ] && [ "${min:-0}" -lt 11 ]; }; then lt511=1; fi
  # === builtin 分支: 自带 kernel_compat.h 兼容层, 只需 3 处修复 (2026-11 全树扫描结论) ===
  if [ "$KSU_BRANCH" = builtin ]; then
    # B1) kernel_includes.h 无守卫地 include <linux/static_call.h> (5.10+ 才有, 4.19 无此头; 全树仅此一处使用)
    #     注意: 不能粗暴 grep 整个文件是否含 KERNEL_VERSION(5, 10, 0) —— 该文件其他地方本来就有这句,
    #     那样会永远判定"已加守卫"而跳过修复 (run #26 踩过)。只检查 include 行的前一行。
    local ki="$kd/kernel_includes.h"
    if [ -f "$ki" ] && grep -q '^#include <linux/static_call.h>' "$ki" \
       && [ ! -f "$KERNEL_DIR/include/linux/static_call.h" ]; then
      local guarded=0
      if awk '/^#include <linux\/static_call.h>/{if (prev ~ /KERNEL_VERSION\(5, 10, 0\)/) g=1} {prev=$0} END{exit !g}' "$ki"; then
        guarded=1
      fi
      if [ "$guarded" = 0 ]; then
        info "兼容修复(builtin): kernel_includes.h 的 static_call.h include 加 ≥5.10 守卫 (目标内核无此头)"
        sed -i 's|^#include <linux/static_call.h>|#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)\n#include <linux/static_call.h>\n#endif|' "$ki"
      fi
    fi
    # B2) app_profile.c 使用 clear_syscall_work(SECCOMP) (5.4+ 的 syscall_work 机制, 4.19 无);
    #     下一行已有 clear_thread_flag(TIF_SECCOMP) (4.19 及更老的等价操作) → 删除该行
    local ap="$kd/policy/app_profile.c"
    if [ -f "$ap" ] && grep -q 'clear_syscall_work' "$ap" \
       && ! grep -rq 'syscall_work' "$KERNEL_DIR/include/linux/thread_info.h"; then
      info "兼容修复(builtin): app_profile.c 删除 clear_syscall_work 行 (目标内核无 syscall_work, 已有 clear_thread_flag 兜底)"
      sed -i '/clear_syscall_work(SECCOMP);/d' "$ap"
    fi
    # B3) fallthrough; 语句 (5.4+ 宏; 目标内核 compiler 头无定义时替换为注释)
    if ! grep -rq 'define[[:space:]]\+fallthrough' "$KERNEL_DIR/include/linux/compiler.h" "$KERNEL_DIR/include/linux/compiler_types.h" "$KERNEL_DIR/include/linux/compiler_attributes.h" 2>/dev/null; then
      local bf
      while IFS= read -r bf; do
        info "兼容修复(builtin): ${bf#$KERNEL_DIR/} 的 fallthrough; 改为 /* fallthrough */"
        sed -i 's/\bfallthrough;/\/* fallthrough *\//g' "$bf"
      done < <(find -L "$kd" -type f -name '*.c' -exec grep -l '\bfallthrough;' {} + 2>/dev/null || true)
    fi
    # B4) extension/kpm/kpm.c:182 用 2 参 access_ok(5.0+ 签名; 4.19 是 access_ok(type,addr,size) 3 参) → ksu_access_ok
    local kpmc="$kd/extension/kpm/kpm.c"
    if [ -f "$kpmc" ] && grep -q '!access_ok(' "$kpmc" \
       && grep -rq 'VERIFY_READ' "$KERNEL_DIR/include/linux/uaccess.h"; then
      info "兼容修复(builtin): kpm.c 的 2 参 access_ok 改为 ksu_access_ok (4.19 是 3 参宏)"
      sed -i 's/!access_ok(/!ksu_access_ok(/g' "$kpmc"
    fi
    # B5) kvcalloc 是 4.18+ 才有 (4.14 树 supercall/dispatch.c 使用) → 补兼容宏 (kvzalloc 4.12+)
    local comp="$kd/kernel_compat.h"
    if [ -f "$comp" ] && ! grep -rq 'kvcalloc' "$KERNEL_DIR/include/linux/mm.h" 2>/dev/null \
       && ! grep -q 'ksu_compat_kvcalloc' "$comp"; then
      info "兼容修复(builtin): kernel_compat.h 补 kvcalloc/kvzalloc 兼容宏 (<4.18 无此 API)"
      cat >> "$comp" <<'KSUEOF'

/* dsh: <4.18 没有 kvcalloc (4.14 树 dispatch.c 使用); kvzalloc 自 4.12 起可用,
 * 更老内核由上方 kvmalloc 兼容层兜底, 这里只做补充定义 */
#if LINUX_VERSION_CODE < KERNEL_VERSION(4, 18, 0)
#ifndef kvzalloc
#define kvzalloc(size, flags) kvmalloc((size), (flags) | __GFP_ZERO)
#endif
#ifndef kvcalloc
#define kvcalloc(n, size, flags) kvzalloc((n) * (size), (flags))
#endif
#endif /* dsh kvcalloc compat */
KSUEOF
    fi
    # B6) 上游 kernel_compat.h 认为 KPM 从 4.4 起可用, 但 kpm/compact.c 依赖 linux/set_memory.h
    # 等 4.14+ 接口, kpm.c 还用了 5.0 前的 2 参 access_ok → 4.9/4.4 编译失败 (run #41/#42:
    # dandelion/jasmine)。<4.14 时直接在 compat 头尾部 undef, 让 ksu_main.c 的 #ifdef 编译掉 KPM。
    if [ -f "$comp" ] && [ -n "$maj" ] \
       && { [ "$maj" -lt 4 ] 2>/dev/null || { [ "$maj" -eq 4 ] && [ "${min:-0}" -lt 14 ]; }; } \
       && ! grep -q 'dsh: KPM disabled' "$comp"; then
      info "兼容修复(builtin): <4.14 内核关闭 KPM (kpm/compact.c 依赖 4.14+ 的 set_memory 接口)"
      cat >> "$comp" <<'KSUEOF'

/* dsh: KPM disabled */
#if LINUX_VERSION_CODE < KERNEL_VERSION(4, 14, 0)
#undef KSU_CAN_USE_KPM
#endif
KSUEOF
    fi
    # B7) linux/sched/signal.h、linux/sched/task.h 是 4.11 才从 linux/sched.h 拆出来的;
    # 4.9/4.4 上没有这两个头 (run #45/#46: dandelion/jasmine symbol_resolver.c 直接 include)
    # → <4.11 时整树改回 <linux/sched.h> (该头同时提供 task_pgrp/task_session 等)
    if [ -n "$maj" ] && { [ "$maj" -lt 4 ] 2>/dev/null || { [ "$maj" -eq 4 ] && [ "${min:-0}" -lt 11 ]; }; }; then
      local sf
      while IFS= read -r sf; do
        sed -i 's|#include <linux/sched/signal.h>|#include <linux/sched.h>|; s|#include <linux/sched/task.h>|#include <linux/sched.h>|' "$sf"
      done < <(find -L "$kd" -type f \( -name '*.c' -o -name '*.h' \) -exec grep -lE '#include <linux/sched/(signal|task)\.h>' {} + 2>/dev/null || true)
      info "兼容修复(builtin): <4.11 内核的 linux/sched/signal.h、sched/task.h 改回 linux/sched.h"
    fi
    # B8) DECLARE_STATIC_KEY_FALSE / static_branch_enable 是 4.5+ 的 API, 4.4 上只有
    # static_key_false; 而 kernel_compat.h 里 KSU_COMPAT_USE_STATIC_KEY 是按版本
    # (>=4.3) 判定的 → 4.4 树选用了静态键分支, 编译报 "type defaults to 'int' in
    # declaration of DECLARE_STATIC_KEY_FALSE" (run #63: jasmine 4.4.153)。
    # 以目标内核 jump_label.h 是否真的提供该宏为准, 缺则 undef, 让代码走 bool 开关回退路径。
    if [ -f "$comp" ] && ! grep -q 'DECLARE_STATIC_KEY_FALSE' "$KERNEL_DIR/include/linux/jump_label.h" 2>/dev/null \
       && ! grep -q 'dsh: static key fallback' "$comp"; then
      info "兼容修复(builtin): 目标内核无 DECLARE_STATIC_KEY_FALSE → 关闭 KSU 静态键分支 (走 bool 开关)"
      cat >> "$comp" <<'KSUEOF'

/* dsh: static key fallback */
#if !defined(DECLARE_STATIC_KEY_FALSE)
#undef KSU_COMPAT_USE_STATIC_KEY
#endif /* dsh static key fallback */
KSUEOF
    fi
    return 0
  fi
  # === main 分支: 以下 12 项修复仅对 main 执行 ===
  # 1) MODULE_IMPORT_NS: 符号命名空间 5.4+ 才有, 更老内核上宏不存在 → 删除导入行
  local f="$kd/core/init.c"
  if [ "$lt54" = 1 ] && [ -f "$f" ] && grep -q 'MODULE_IMPORT_NS' "$f"; then
    info "兼容修复: 删除 <5.4 内核上不存在的 MODULE_IMPORT_NS 导入 (core/init.c)"
    sed -i '/^MODULE_IMPORT_NS.*$/d' "$f"
  fi
  # 2) linux/pgtable.h: 5.5+ 才有, 更老内核用 asm/pgtable.h
  # 注意: 必须用 find -L — setup.sh 把 drivers/kernelsu 建成指向 KernelSU/kernel 的符号链接,
  # 不带 -L 的 find 不会进入符号链接目录 (run #12 的 *_nofault 修复因此零文件执行)
  if [ "$lt55" = 1 ]; then
    local g
    while IFS= read -r g; do
      info "兼容修复: ${g#$KERNEL_DIR/} 的 linux/pgtable.h 改为 asm/pgtable.h (<5.5)"
      sed -i 's|#include <linux/pgtable.h>|#include <asm/pgtable.h>|' "$g"
    done < <(find -L "$kd" -type f \( -name '*.c' -o -name '*.h' \) -exec grep -l '#include <linux/pgtable.h>' {} + 2>/dev/null || true)
  fi
  # 3) *_nofault API 族: 5.8 才引入 (5.7 及更老只有 probe_kernel_* / 普通 copy_* 与 strncpy_from_user)
  if [ "$lt58" = 1 ]; then
    info "兼容修复: 替换 <5.8 内核上不存在的 *_nofault API (全 kernelsu 树)"
    find -L "$kd" -type f \( -name '*.c' -o -name '*.h' \) -exec sed -i \
      -e 's/copy_to_kernel_nofault(/probe_kernel_write(/g' \
      -e 's/copy_from_kernel_nofault(/probe_kernel_read(/g' \
      -e 's/copy_from_user_nofault(/copy_from_user(/g' \
      -e 's/copy_to_user_nofault(/copy_to_user(/g' \
      -e 's/strncpy_from_user_nofault(/strncpy_from_user(/g' \
      {} +
  fi
  # 4) uapi/linux/mount.h: 5.2+ 才有; su_mount_ns.c 只用到 MS_PRIVATE|MS_REC (在 uapi/linux/fs.h)
  if [ "$lt52" = 1 ]; then
    local sm="$kd/infra/su_mount_ns.c"
    if [ -f "$sm" ] && grep -q '#include <uapi/linux/mount.h>' "$sm"; then
      info "兼容修复: infra/su_mount_ns.c 的 uapi/linux/mount.h 改为 uapi/linux/fs.h (<5.2)"
      sed -i 's|#include <uapi/linux/mount.h>|#include <uapi/linux/fs.h>|' "$sm"
    fi
  fi
  # 5) linux/minmax.h: 5.1+ 才有; event.c 只用 min/max 宏 (linux/kernel.h 亦有)
  if [ "$lt51" = 1 ]; then
    local ev="$kd/sulog/event.c"
    if [ -f "$ev" ] && grep -q '#include <linux/minmax.h>' "$ev"; then
      info "兼容修复: sulog/event.c 的 linux/minmax.h 改为 linux/kernel.h (<5.1)"
      sed -i 's|#include <linux/minmax.h>|#include <linux/kernel.h>|' "$ev"
    fi
  fi
  # 6) dispatch.c 缺 sched 头: tasklist_lock/init_task 在 sched/task.h, task_pgrp/task_session 在 sched/signal.h
  #    (4.19 的 sched.h 不包含 sched/signal.h; 4.11 之前这两个 split 头还不存在, 用 sched.h 兜底)
  local dp="$kd/supercall/dispatch.c"
  if [ -f "$dp" ] && grep -q '#include <linux/thread_info.h>' "$dp" \
     && ! grep -q '#include <linux/sched/signal.h>' "$dp"; then
    if [ "$lt411" = 1 ]; then
      info "兼容修复: supercall/dispatch.c 补 <linux/sched.h> (<4.11 无 split sched 头)"
      sed -i 's|#include <linux/thread_info.h>|#include <linux/thread_info.h>\n#include <linux/sched.h>|' "$dp"
    else
      info "兼容修复: supercall/dispatch.c 补 sched/signal.h + sched/task.h (task_pgrp/task_session/tasklist_lock)"
      sed -i 's|#include <linux/thread_info.h>|#include <linux/thread_info.h>\n#include <linux/sched/signal.h>\n#include <linux/sched/task.h>|' "$dp"
    fi
  fi
  # 7) allowlist.c 缺 sched/task.h: put_task_struct 声明于 sched/task.h (4.11+)
  local al="$kd/policy/allowlist.c"
  if [ -f "$al" ] && grep -q 'put_task_struct(' "$al" \
     && ! grep -q '#include <linux/sched/task.h>' "$al"; then
    if [ "$lt411" = 1 ]; then
      info "兼容修复: policy/allowlist.c 补 <linux/sched.h> (put_task_struct, <4.11)"
      sed -i 's|#include <linux/version.h>|#include <linux/version.h>\n#include <linux/sched.h>|' "$al"
    else
      info "兼容修复: policy/allowlist.c 补 <linux/sched/task.h> (put_task_struct)"
      sed -i 's|#include <linux/version.h>|#include <linux/version.h>\n#include <linux/sched/task.h>|' "$al"
    fi
  fi
  # 8) TWA_RESUME: 5.9 才引入的枚举; 5.8 及更老 task_work_add 第三参是 bool → 用 true
  if [ "$lt59" = 1 ]; then
    local tf
    for tf in "$kd/policy/allowlist.c" "$kd/supercall/supercall.c"; do
      if [ -f "$tf" ] && grep -q 'TWA_RESUME' "$tf"; then
        info "兼容修复: ${tf#$KERNEL_DIR/} 的 TWA_RESUME 改为 true (<5.9)"
        sed -i 's/TWA_RESUME/true/g' "$tf"
      fi
    done
  fi
  # 9) fallthrough 语句: 5.4+ 才有的宏; 更老内核用 /* fallthrough */ 注释
  if [ "$lt54" = 1 ]; then
    local ff
    while IFS= read -r ff; do
      info "兼容修复: ${ff#$KERNEL_DIR/} 的 fallthrough; 改为 /* fallthrough */ (<5.4)"
      sed -i 's/^\([[:space:]]*\)fallthrough;/\1\/\* fallthrough \*\//' "$ff"
    done < <(find -L "$kd" -type f -name '*.c' -exec grep -l '^[[:space:]]*fallthrough;' {} + 2>/dev/null || true)
  fi
  # 10) seccomp action_cache 与 SECCOMP_ARCH_NATIVE_NR 都是 5.4+ 的; 4.x 内核 struct seccomp_filter
  #     无 cache 字段 (镜像结构体错位有运行时风险) → 整文件替换为桩, 保住 setuid_hook.c 调用的 API
  if [ "$lt54" = 1 ]; then
    local sc="$kd/infra/seccomp_cache.c"
    if [ -f "$sc" ] && grep -q 'SECCOMP_ARCH_NATIVE_NR' "$sc"; then
      info "兼容修复: infra/seccomp_cache.c 整体替换为桩 (<5.4 无 action_cache, 避免结构错位)"
      cat > "$sc" <<'KSU_EOF'
// SPDX-License-Identifier: GPL-2.0
/* seccomp action_cache 与 SECCOMP_ARCH_NATIVE_NR 均为 5.4+, 旧内核退化为空操作 */
#include "infra/seccomp_cache.h"

void ksu_seccomp_clear_cache(struct seccomp_filter *filter, int nr)
{
    (void)filter;
    (void)nr;
}

void ksu_seccomp_allow_cache(struct seccomp_filter *filter, int nr)
{
    (void)filter;
    (void)nr;
}
KSU_EOF
    fi
  fi
  # 11) fsnotify handle_inode_event 指定初始化需要 5.11+; 更老内核用 8 参 handle_event 旧 API
  if [ "$lt511" = 1 ]; then
    local po="$kd/manager/pkg_observer.c"
    if [ -f "$po" ] && grep -q 'handle_inode_event' "$po"; then
      info "兼容修复: manager/pkg_observer.c 替换为 fsnotify 旧 API 实现 (<5.11)"
      cat > "$po" <<'KSU_EOF'
// SPDX-License-Identifier: GPL-2.0
/* <5.11 兼容版: fsnotify 旧 API (8 参 handle_event); 新 API 需 5.11+ */
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/limits.h>
#include <linux/string.h>
#include <linux/namei.h>
#include <linux/fsnotify_backend.h>
#include <linux/sched.h>
#include <linux/slab.h>
#include <linux/rculist.h>
#include <linux/task_work.h>
#include <linux/version.h>
#include "klog.h" // IWYU pragma: keep
#include "manager/throne_tracker.h"

#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 8, 0) && !defined(TWA_RESUME)
#define TWA_RESUME true
#endif

#define MASK_SYSTEM (FS_CREATE | FS_MOVE | FS_EVENT_ON_CHILD)

struct watch_dir {
    const char *path;
    u32 mask;
    struct path kpath;
    struct inode *inode;
    struct fsnotify_mark *mark;
};

static struct fsnotify_group *g;

static void ksu_track_throne_tw_func(struct callback_head *cb)
{
    kfree(cb);
    // Runs after exit_fs() if the task is exiting; path lookups would oops
    if (current->flags & PF_EXITING)
        return;
    track_throne(false);
}

// Never scan from the fsnotify handler: fsnotify_mark_srcu and the rename's dir
// locks would be held for the whole scan. Defer with task_work, not a kthread
// or kworker: the scan must finish before the rename returns, or the manager
// can be opened before it is crowned, and it must run in the renamer's
// (Android's) namespaces, which differ from init_task's on WSA/Waydroid.
static void ksu_defer_track_throne(void)
{
    struct callback_head *cb;

    if (current->flags & PF_KTHREAD)
        goto skipped;

    cb = kzalloc(sizeof(*cb), GFP_KERNEL);
    if (!cb)
        goto skipped;

    cb->func = ksu_track_throne_tw_func;
    if (!task_work_add(current, cb, TWA_RESUME))
        return;
skipped:
    kfree(cb);
    pr_warn("defer track_throne failed, skipping scan\n");
}

/* 5.11 之前的 fsnotify_ops: 8 参 handle_event */
static int ksu_handle_event(struct fsnotify_group *group, struct inode *inode,
                            u32 mask, const void *data, int data_type,
                            const unsigned char *file_name, u32 cookie,
                            struct fsnotify_iter_info *iter_info)
{
    (void)group;
    (void)inode;
    (void)data;
    (void)cookie;
    (void)iter_info;
    if (data_type != FSNOTIFY_EVENT_INODE || !file_name)
        return 0;
    if (mask & FS_ISDIR)
        return 0;
    if (strnlen(file_name, NAME_MAX + 1) == 13 &&
        !memcmp(file_name, "packages.list", 13)) {
        pr_info("packages.list detected: %d\n", mask);
        ksu_defer_track_throne();
    }
    return 0;
}

static const struct fsnotify_ops ksu_ops = {
    .handle_event = ksu_handle_event,
};

static int add_mark_on_inode(struct inode *inode, u32 mask, struct fsnotify_mark **out)
{
    struct fsnotify_mark *m;

    m = kzalloc(sizeof(*m), GFP_KERNEL);
    if (!m)
        return -ENOMEM;

    fsnotify_init_mark(m, g);
    m->mask = mask;

    if (fsnotify_add_inode_mark(m, inode, 0)) {
        fsnotify_put_mark(m);
        return -EINVAL;
    }
    *out = m;
    return 0;
}

static int watch_one_dir(struct watch_dir *wd)
{
    int ret = kern_path(wd->path, LOOKUP_FOLLOW, &wd->kpath);
    if (ret) {
        pr_info("path not ready: %s (%d)\n", wd->path, ret);
        return ret;
    }
    wd->inode = d_inode(wd->kpath.dentry);
    ihold(wd->inode);

    ret = add_mark_on_inode(wd->inode, wd->mask, &wd->mark);
    if (ret) {
        pr_err("Add mark failed for %s (%d)\n", wd->path, ret);
        path_put(&wd->kpath);
        iput(wd->inode);
        wd->inode = NULL;
        return ret;
    }
    pr_info("watching %s\n", wd->path);
    return 0;
}

static void unwatch_one_dir(struct watch_dir *wd)
{
    if (wd->mark) {
        fsnotify_destroy_mark(wd->mark, g);
        fsnotify_put_mark(wd->mark);
        wd->mark = NULL;
    }
    if (wd->inode) {
        iput(wd->inode);
        wd->inode = NULL;
    }
    if (wd->kpath.dentry) {
        path_put(&wd->kpath);
        memset(&wd->kpath, 0, sizeof(wd->kpath));
    }
}

static struct watch_dir g_watch = { .path = "/data/system", .mask = MASK_SYSTEM };

int ksu_observer_init(void)
{
    int ret = 0;

    g = fsnotify_alloc_group(&ksu_ops);
    if (IS_ERR(g))
        return PTR_ERR(g);

    ret = watch_one_dir(&g_watch);
    pr_info("observer init done\n");
    return 0;
}

void __exit ksu_observer_exit(void)
{
    unwatch_one_dir(&g_watch);
    fsnotify_put_group(g);
    pr_info("observer exit done\n");
}
KSU_EOF
    fi
  fi
  # 12) cpu_spoof.c 的通用 vDSO 头 (vdso/datapage.h) 5.2+ 才有; 旧内核移除 vdso 改写段,
  #     保留 MIDR/loops_per_jiffy/elf_hwcap 改写 (kallsyms 方案与版本无关)
  if [ "$lt52" = 1 ]; then
    local cs="$kd/extension/cpu_spoof.c"
    if [ -f "$cs" ] && grep -q '#include <vdso/' "$cs"; then
      info "兼容修复: extension/cpu_spoof.c 移除通用 vDSO 代码段 (<5.2)"
      sed -i '\|#include <vdso/|d' "$cs"
      local st en
      st="$(grep -n 'KERNEL_VERSION(6, 18, 0)' "$cs" | head -n1 | cut -d: -f1)"
      en="$(grep -n 'clear_bit(ARM64_WORKAROUND_1418040' "$cs" | head -n1 | cut -d: -f1)"
      if [ -n "$st" ] && [ -n "$en" ] && [ "$en" -gt "$st" ]; then
        sed -i "${st},$((en + 5))d" "$cs"
      else
        warn "cpu_spoof.c 的 vDSO 段定位失败, 仅移除了 include (编译报错请反馈)"
      fi
    fi
  fi
}

# -------------------------------- 配置选择 --------------------------------
pick_defconfig() {
  local hint="${SEL_DEFCONFIG:-}"
  local rel sel f
  cd "$KERNEL_DIR"
  if [ -n "$hint" ]; then
    if [ -f "arch/arm64/configs/$hint" ]; then
      DEFCONFIG="$hint"
      return 0
    fi
    if [[ "$hint" == *[*?]* ]]; then
      local -a g=()
      while IFS= read -r f; do g+=("$f"); done < <(cd arch/arm64/configs && ls $hint 2>/dev/null)
      if (( ${#g[@]} == 1 )); then DEFCONFIG="$g"; return 0; fi
      if (( ${#g[@]} > 1 )); then
        for f in "${g[@]}"; do
          if [[ "$f" == *user* || "$f" == *perf* ]]; then DEFCONFIG="$f"; return 0; fi
        done
        DEFCONFIG="${g[0]}"
        return 0
      fi
    fi
    warn "defconfig 提示 \"$hint\" 在该内核源码中不存在, 改为自动探测"
  fi
  # 按设备 codename 探测
  local -a found=()
  while IFS= read -r f; do
    found+=("${f#arch/arm64/configs/}")
  done < <(find arch/arm64/configs -maxdepth 3 -type f -name "*${SEL_DEVICE_ID}*" 2>/dev/null | sort)
  if (( ${#found[@]} == 1 )); then DEFCONFIG="${found[0]}"; return 0; fi
  if (( ${#found[@]} > 1 )); then
    for f in "${found[@]}"; do
      if [[ "$f" == *user* ]]; then DEFCONFIG="$f"; return 0; fi
    done
    for f in "${found[@]}"; do
      if [[ "$f" == *perf* ]]; then DEFCONFIG="$f"; return 0; fi
    done
    if ! sel="$(menu_select "为 $SEL_DEVICE_ID 探测到多个 defconfig, 请选择:" "${found[@]}")"; then exit 0; fi
    DEFCONFIG="${found[$((sel-1))]}"
    return 0
  fi
  # 兜底: 列出所有候选
  local -a all=()
  while IFS= read -r f; do
    all+=("${f#arch/arm64/configs/}")
  done < <(find arch/arm64/configs -maxdepth 2 -type f \( -name "*_defconfig" -o -name "*.config" \) 2>/dev/null | sort)
  if (( ${#all[@]} == 0 )); then die "未找到任何 defconfig/.config 文件, 无法确定内核配置"; fi
  if ! sel="$(menu_select "未能自动匹配 defconfig, 请手动选择:" "${all[@]}")"; then exit 0; fi
  DEFCONFIG="${all[$((sel-1))]}"
}

# 生成 make 工具链参数 (CC 必须显式传递: 小米/高通系内核 Makefile 默认把
# CC 指向 python2 时代的 scripts/gcc-wrapper.py, 现代系统无 python2 会导致
# init/Kconfig 的 $(success,$(CC) --version ...) 检查直接语法错误)
toolchain_make_args() {
  local -a a=()
  local kmaj kmin kv
  local CCW=""
  # KERNEL_CCACHE=1 且系统有 ccache 时, 用 ccache 包住编译器复用编译产物缓存
  # (CI 由 actions/cache 缓存 CCACHE_DIR; 同一设备/版本重复编译时可直接命中绝大多数目标文件)
  if [ "${KERNEL_CCACHE:-0}" = 1 ] && command -v ccache >/dev/null 2>&1; then
    CCW="ccache "
  fi
  kv="$(echo "$KVER" | grep -oE '[0-9]+\.[0-9]+' | head -n1 || true)"
  kmaj="${kv%%.*}"; kmin="${kv##*.}"
  if [ "$USE_CLANG" = 1 ]; then
    if [ "$SEL_GKI" = 1 ] \
       || { [ -n "$kmaj" ] && [ "$kmaj" -gt 5 ]; } \
       || { [ -n "$kmaj" ] && [ "$kmaj" -eq 5 ] && [ "$kmin" -ge 10 ]; }; then
      a+=(LLVM=1 CROSS_COMPILE=aarch64-linux-gnu- CC="${CCW}$CLANG_DIR/bin/clang")
    else
      a+=(CC="${CCW}$CLANG_DIR/bin/clang" CLANG_TRIPLE=aarch64-linux-gnu-)
      a+=(CROSS_COMPILE="$GCC64_DIR/bin/aarch64-linux-android-")
      a+=(CROSS_COMPILE_ARM32="$GCC32_DIR/bin/arm-linux-androideabi-")
      # 老内核 (4.14 等) 的 vmlinux 用 $(LD) 链接, 且 arch/arm64 在 RELOCATABLE 时传 -pie -shared;
      # 若 LD 落到主机 ld.lld 会报 "-shared and -pie may not be used together" (run #34)。
      # 显式指定 GCC4.9 工具链里的 GNU bfd ld (binutils 2.27, 主线老内核同款配方)。
      if [ -x "$GCC64_DIR/bin/aarch64-linux-android-ld.bfd" ]; then
        a+=(LD="$GCC64_DIR/bin/aarch64-linux-android-ld.bfd")
      fi
    fi
  else
    a+=(CC="${CCW}$GCC64_DIR/bin/aarch64-linux-android-gcc")
    a+=(CROSS_COMPILE="$GCC64_DIR/bin/aarch64-linux-android-")
    a+=(CROSS_COMPILE_ARM32="$GCC32_DIR/bin/arm-linux-androideabi-")
  fi
  # 老内核 (lib/string.c 无 stpcpy, 5.10 前) 上, clang/gcc 会把 sprintf(p,"%s",s) 优化成 stpcpy 调用
  # (tty_io.c 的 tty_line_name 即中招: undefined reference to `stpcpy' — run #16), 禁用该内置优化
  local kc=""
  if [ -n "$kmaj" ] && { [ "$kmaj" -lt 5 ] || { [ "$kmaj" -eq 5 ] && [ "$kmin" -lt 10 ]; }; }; then
    kc="-fno-builtin-sprintf -fno-builtin-stpcpy"
  fi
  # 4.19 等老树的 KBUILD_CFLAGS 自带 -Werror=strict-prototypes; clang 对"无原型的老式函数定义"
  # (如 drivers/gpu/drm/mediatek/mtk_dsi.c) 也报该警告并升格为错误, 而 gcc 不报 →
  # 厂商树用 gcc 能编、用 clang 编不过 (run #4: agate 4.19.191)。这里统一降级为警告。
  kc="${kc:+$kc }-Wno-error=strict-prototypes"
  # 经典式 clang 上老厂商驱动普遍触发 -Werror=<各种 clang 专属告警>(如 mediatek eccci 的
  # -Wpointer-to-int-cast, run #40: agate), gcc 下不报 → 全局把 -Werror 降级为警告。
  # (GCC 模式不需要; LLVM=1 模式面向 5.10+ 的 GKI 树, 保持严格)
  if [ "$USE_CLANG" = 1 ] && ! { [ "$SEL_GKI" = 1 ] \
       || { [ -n "$kmaj" ] && [ "$kmaj" -gt 5 ]; } \
       || { [ -n "$kmaj" ] && [ "$kmaj" -eq 5 ] && [ "$kmin" -ge 10 ]; }; }; then
    kc="$kc -Wno-error"
  fi
  if [ -n "$kc" ]; then
    a+=(KCFLAGS="$kc")
  fi
  printf '%s\n' "${a[@]}"
}

make_config() {
  cd "$KERNEL_DIR"
  local -a TCA
  mapfile -t TCA < <(toolchain_make_args)
  local -a MK=(make O="$OUT_DIR" ARCH=arm64 "${TCA[@]}")
  local SC="scripts/config --file $OUT_DIR/.config"
  # LLVM=1 模式下 olddefconfig 的 Kconfig.include 会检查 ld.lld 是否在 PATH
  # (run #20: 5.10+ 内核 "linker 'ld.lld' not found" 在配置阶段即失败)
  if [ "$USE_CLANG" = 1 ]; then
    local kmaj kmin kv
    kv="$(echo "$KVER" | grep -oE '[0-9]+\.[0-9]+' | head -n1 || true)"
    kmaj="${kv%%.*}"; kmin="${kv##*.}"
    if [ "$SEL_GKI" = 1 ] \
       || { [ -n "$kmaj" ] && [ "$kmaj" -gt 5 ]; } \
       || { [ -n "$kmaj" ] && [ "$kmaj" -eq 5 ] && [ "$kmin" -ge 10 ]; }; then
      export PATH="$CLANG_DIR/bin:$PATH"
    fi
  fi
  info "生成内核配置 ($DEFCONFIG) ..."
  # Xiaomi 的 GKI 树常带"片段配置"(vendor/*_consolidate.config / *_GKI.config / *.fragment,
  # 通常不足 200 行), 厂家构建脚本会把它合并到基础 defconfig (GKI 树为 gki_defconfig)。
  # 直接把片段当完整 .config 用会得到与厂家意图不符的配置; 且 gki_defconfig 含 FULL LTO/KASAN/DWARF,
  # 在 2 核 7GB runner 上极易超时, 因此合并后裁剪这些调试级选项。
  local is_fragment=0 cfg_lines=0
  if [ -f "arch/arm64/configs/$DEFCONFIG" ]; then
    cfg_lines=$(grep -c '^CONFIG' "arch/arm64/configs/$DEFCONFIG" 2>/dev/null) || true
    [ -z "$cfg_lines" ] && cfg_lines=0
  fi
  case "$DEFCONFIG" in
    *consolidate.config|*_QGKI.config|*_GKI.config|*.fragment) is_fragment=1 ;;
  esac
  if [ "$cfg_lines" -gt 0 ] && [ "$cfg_lines" -lt 200 ]; then
    is_fragment=1
  fi
  # 部分厂商"片段"比较大 (如 blue_defconfig 321 个 CONFIG 行), 但缺少基础核心项
  # (SELinux/ARM64/网络栈), 而树里带 gki_defconfig (厂家构建脚本的合并基线) —— 这类
  # 必须按片段合并, 否则 make <name>_defconfig 会得到缺失 SELinux 的配置,
  # 后续 KSU 的 sepolicy.h → security/selinux/include/security.h 链因 flask.h 未生成而断掉 (run #35/#36)。
  if [ "$is_fragment" = 0 ] && [ "$cfg_lines" -ge 200 ] && [ "$cfg_lines" -lt 400 ] \
     && [ -f arch/arm64/configs/gki_defconfig ] \
     && ! grep -q '^CONFIG_SECURITY_SELINUX=y' "arch/arm64/configs/$DEFCONFIG" 2>/dev/null; then
    is_fragment=1
    info "该配置缺少基础核心项且树内带 gki_defconfig, 按片段配置合并处理: $DEFCONFIG"
  fi
  mkdir -p "$OUT_DIR"
  if [ "$is_fragment" = 1 ]; then
    local base_cfg=""
    if [ -f arch/arm64/configs/gki_defconfig ]; then
      base_cfg=gki_defconfig
    elif [ -f arch/arm64/configs/defconfig ]; then
      base_cfg=defconfig
    fi
    if [ -z "$base_cfg" ]; then
      warn "未找到基础 defconfig, 退回直接使用片段配置: $DEFCONFIG"
      cp "arch/arm64/configs/$DEFCONFIG" "$OUT_DIR/.config"
      if ! "${MK[@]}" olddefconfig >>"$LOG_FILE" 2>&1; then
        die_log "$LOG_FILE" "olddefconfig 失败"
      fi
    else
      info "检测到片段配置, 以 $base_cfg 为基础再合并 $DEFCONFIG ..."
      if ! "${MK[@]}" "$base_cfg" >>"$LOG_FILE" 2>&1; then
        die_log "$LOG_FILE" "基础配置生成失败: $base_cfg"
      fi
      # 高通 GKI 系厂商构建会**依次合并多个片段**: <机型>_GKI.config → <机型>_QGKI.config
      # (调试构建再加 _debug.config)。若只合 QGKI 一个片段, 会漏掉 GKI 片段里的一批 vendor
      # 驱动/依赖开关, 最终 vmlinux 链接报 undefined reference to qcom_smem_get 等 (run #62 veux)。
      local -a frag_list=()
      local ddir dbase stem sib
      ddir="$(dirname "$DEFCONFIG")"
      dbase="$(basename "$DEFCONFIG")"
      case "$dbase" in
        *_QGKI.config)     stem="${dbase%_QGKI.config}" ;;
        *_GKI.config)      stem="${dbase%_GKI.config}" ;;
        *_consolidate.config) stem="${dbase%_consolidate.config}" ;;
        *_debug.config)    stem="${dbase%_debug.config}" ;;
        *)                 stem="" ;;
      esac
      if [ -n "$stem" ]; then
        sib="$ddir/${stem}_GKI.config"
        if [ -f "arch/arm64/configs/$sib" ] && [ "$sib" != "$DEFCONFIG" ]; then
          frag_list+=("arch/arm64/configs/$sib")
          info "  追加同机型基础片段: $sib"
        fi
      fi
      frag_list+=("arch/arm64/configs/$DEFCONFIG")
      if KCONFIG_CONFIG="$OUT_DIR/.config" bash scripts/kconfig/merge_config.sh -m "$OUT_DIR/.config" "${frag_list[@]}" >>"$LOG_FILE" 2>&1; then
        ok "片段配置合并完成 (${#frag_list[@]} 个片段)"
      else
        warn "merge_config.sh 合并片段失败, 继续使用基础配置: $base_cfg"
      fi
      # 裁剪调试/体积型选项: 避免 FULL LTO 链接爆内存、KASAN 拖慢编译、DWARF 撑大产物
      local opt
      for opt in LTO_CLANG LTO_CLANG_FULL LTO_CLANG_THIN KASAN KASAN_HW_TAGS KASAN_INLINE DEBUG_INFO DEBUG_INFO_DWARF4; do
        $SC -d "$opt" >/dev/null 2>&1 || true
      done
      $SC -e LTO_NONE >/dev/null 2>&1 || true
      $SC -e DEBUG_INFO_NONE >/dev/null 2>&1 || true
      info "已裁剪 LTO/KASAN/DWARF 等调试选项以控制编译时间"
    fi
  elif [[ "$DEFCONFIG" == *defconfig ]]; then
    if ! "${MK[@]}" "$DEFCONFIG" >>"$LOG_FILE" 2>&1; then
      die_log "$LOG_FILE" "defconfig 生成失败: $DEFCONFIG"
    fi
  else
    cp "arch/arm64/configs/$DEFCONFIG" "$OUT_DIR/.config"
    if ! "${MK[@]}" olddefconfig >>"$LOG_FILE" 2>&1; then
      die_log "$LOG_FILE" "olddefconfig 失败"
    fi
  fi
  [ -f "$OUT_DIR/.config" ] || die_log "$LOG_FILE" "未生成 $OUT_DIR/.config"
  info "启用 SukiSU 相关配置 (scripts/config) ..."
  if [ "$KSU_BRANCH" = builtin ]; then
    # builtin: KSU 是 bool (KSU_MODE 已被强制为 y); 依赖 SECURITY_SELINUX;
    # SUSFS 需要内核自带 fs/susfs.c 补丁, 默认显式关闭, 仅 --susfs 时开启
    $SC -e KSU || true
    # SELinux 依赖链必须完整打开: CONFIG_SECURITY_SELINUX 关闭时 security/selinux 不产生对象,
    # genheaders 不会生成 flask.h, KSU 的 sepolicy.h→security.h 立刻报 "flask.h: file not found"。
    $SC -e SECURITY || true
    $SC -e SECURITY_NETWORK || true
    $SC -e SECURITY_SELINUX || true
    # security/selinux/Kconfig: select AUDIT, depends on SECURITY_NETWORK && AUDIT && NET && INET
    # 只开 SELINUX 而缺 AUDIT/NET 时, olddefconfig 会把它依赖不满足地关掉 → flask.h 不生成
    # (run #63 批跑: daumier 5.10.81 报 "CONFIG_SECURITY_SELINUX 未生效!")
    $SC -e AUDIT || true
    $SC -e NET || true
    $SC -e INET || true
    if [ "$OPT_SUSFS" = 1 ]; then
      $SC -e KSU_SUSFS || true
      warn "已启用 KSU_SUSFS: 要求目标内核已集成 susfs4ksu 补丁 (fs/susfs.c), 否则编译/链接将失败"
    else
      $SC -d KSU_SUSFS || true
    fi
    if [ "$SEL_GKI" != 1 ]; then
      $SC -e KALLSYMS || true
      $SC -e KALLSYMS_ALL || true
    fi
    if [ "$OPT_KPM" = 1 ]; then
      $SC -e KPM -e KALLSYMS -e KALLSYMS_ALL || true
    fi
    if [ "$OPT_KSU_DEBUG" = 1 ]; then
      $SC -e KSU_DEBUG || true
    fi
    # 厂商树的 BTF 由 tools/bpf/resolve_btfids 生成, 依赖主机 libelf; 老树/厂商树常在此处因
    # clang -Werror(libbpf const 丢弃) 或缺失 libefl.h 失败。KSU 不需要 BTF → 直接关闭。
    $SC -d DEBUG_INFO_BTF >/dev/null 2>&1 || true
    $SC -d DEBUG_INFO_BTF_MODULES >/dev/null 2>&1 || true
  else
    # main: tristate KSU; Kconfig 依赖 KPROBES + EXT4_FS
    if [ "$KSU_MODE" = m ]; then
      $SC -m KSU || true
    else
      $SC -e KSU || true
    fi
    $SC -e KPROBES || true
    $SC -e EXT4_FS || true
    if [ "$SEL_GKI" = 1 ]; then
      $SC -e MODULES || true
    else
      $SC -e KALLSYMS || true
      $SC -e KALLSYMS_ALL || true
    fi
    if [ "$OPT_KPM" = 1 ]; then
      $SC -e KPM -e KALLSYMS -e KALLSYMS_ALL || true
    fi
    if [ "$OPT_KSU_DEBUG" = 1 ]; then
      $SC -e KSU_DEBUG || true
    fi
  fi
  if ! "${MK[@]}" olddefconfig >>"$LOG_FILE" 2>&1; then
    die_log "$LOG_FILE" "olddefconfig 失败"
  fi
  if grep -q "^CONFIG_KSU=[ym]" "$OUT_DIR/.config"; then
    ok "CONFIG_KSU 已生效: $(grep '^CONFIG_KSU=' "$OUT_DIR/.config" | tr -d '\n')"
  else
    warn "CONFIG_KSU 未在最终配置中生效! 常见原因: 依赖不满足 (main 分支需要 KPROBES/EXT4_FS, builtin 分支需要 SECURITY_SELINUX)。请检查 $OUT_DIR/.config"
  fi
  # builtin 依赖 SELinux 内部头文件与 genheaders 产物 (flask.h), SELinux 关闭必然编译失败
  if [ "$KSU_BRANCH" = builtin ] && ! grep -q '^CONFIG_SECURITY_SELINUX=y' "$OUT_DIR/.config"; then
    warn "CONFIG_SECURITY_SELINUX 未生效! builtin 分支必须有 SELinux (否则 flask.h 无法生成, security.h 链断)。请检查基础配置/依赖链"
  fi
  # 诊断: 核心配置项与树内改动 (排查 run #24 的 atomic64_t 未定义问题)
  {
    echo "--- 诊断: 核心 CONFIG 项 ($(date -u +%H:%M:%SZ)) ---"
    grep -E '^CONFIG_(64BIT|ARM64|JUMP_LABEL|ARM64_LSE_ATOMICS|LTO_CLANG|SECURITY_SELINUX|KSU|KALLSYMS)=' "$OUT_DIR/.config" || echo "(以上配置项在 .config 中均不存在)"
    echo "--- 诊断: .config 总行数: $(wc -l < "$OUT_DIR/.config") ---"
    echo "--- 诊断: 内核树改动文件 ---"
    (cd "$KERNEL_DIR" && git status --porcelain 2>/dev/null | head -30) || true
  } >>"$LOG_FILE" 2>&1
}

# --------------------------------- 编译 ------------------------------------
build_kernel() {
  cd "$KERNEL_DIR"
  local -a TCA args
  mapfile -t TCA < <(toolchain_make_args)
  args=(O="$OUT_DIR" ARCH=arm64 "-j$JOBS" "${TCA[@]}")
  local kmaj kmin kv
  kv="$(echo "$KVER" | grep -oE '[0-9]+\.[0-9]+' | head -n1 || true)"
  kmaj="${kv%%.*}"; kmin="${kv##*.}"
  if [ "$USE_CLANG" = 1 ]; then
    if [ "$SEL_GKI" = 1 ] \
       || { [ -n "$kmaj" ] && [ "$kmaj" -gt 5 ]; } \
       || { [ -n "$kmaj" ] && [ "$kmaj" -eq 5 ] && [ "$kmin" -ge 10 ]; }; then
      info "编译方式: LLVM=1 全 LLVM 工具链"
      export PATH="$CLANG_DIR/bin:$PATH"
    else
      info "编译方式: Clang + GCC binutils 交叉前缀 (经典式)"
    fi
    if grep -q '^CONFIG_LTO_CLANG=y' "$OUT_DIR/.config" 2>/dev/null; then
      info "检测到 LTO, 追加 LLVM 链接工具"
      args+=(LD="$CLANG_DIR/bin/ld.lld" LLVM_AR="$CLANG_DIR/bin/llvm-ar" LLVM_NM="$CLANG_DIR/bin/llvm-nm" \
             LLVM_OBJCOPY="$CLANG_DIR/bin/llvm-objcopy" LLVM_STRIP="$CLANG_DIR/bin/llvm-strip")
    fi
  else
    info "编译方式: GCC 4.9"
  fi
  if [ -n "${EXTRA_MAKE_ARGS:-}" ]; then
    args+=($EXTRA_MAKE_ARGS)
    info "附加 make 参数: $EXTRA_MAKE_ARGS"
  fi
  # 快速预检: 单独编译 drivers/kernelsu, 尽早暴露集成兼容错误 (约 2~3 分钟, -k 一次暴露全部错误)
  info "预检: 快速编译 drivers/kernelsu/ (尽早发现兼容错误)..."
  # 诊断: 确认 autoconf.h 中的核心配置 (排查 run #24 的 atomic64_t 未定义)
  {
    echo "--- 诊断2: autoconf.h ($(date -u +%H:%M:%SZ)) ---"
    if [ -f "$OUT_DIR/include/generated/autoconf.h" ]; then
      ls -la "$OUT_DIR/include/generated/autoconf.h" 2>&1 | head -1
      grep -E 'CONFIG_(64BIT|ARM64|AS_LSE|ARM64_LSE_ATOMICS|KASAN)' "$OUT_DIR/include/generated/autoconf.h" 2>/dev/null || echo "(autoconf.h 中未找到上述配置项)"
    else
      echo "(autoconf.h 不存在!)"
    fi
    echo "--- 诊断2: .config 中的 64BIT/ARM64 ---"
    grep -nE '64BIT|^CONFIG_ARM64=' "$OUT_DIR/.config" 2>/dev/null | head -10 || echo "(无)"
  } >>"$LOG_FILE" 2>&1
  # builtin 分支的 kernel_includes.h 包含 <generated/compile.h>, 它由 init/Makefile 里的规则
  # (scripts/mkcompile_h) 生成; 单编译 drivers/kernelsu 不会触达 init/, 故先编译一次 version.o 生成它
  if ! make "${args[@]}" init/version.o >>"$LOG_FILE" 2>&1; then
    die_log "$LOG_FILE" "预检失败: init/version.o 编译出错 (详见日志尾部)"
  fi
  # 5.4+ 内核开启 CONFIG_DEBUG_INFO_BTF 时, kbuild 会先构建 tools/bpf/resolve_btfids (依赖 libelf-dev);
  # 提前单独构建, 缺库时几十秒即报错, 不必等完整编译数十分钟
  if [ -d "$KERNEL_DIR/tools/bpf/resolve_btfids" ] && grep -q '^CONFIG_DEBUG_INFO_BTF=y' "$OUT_DIR/.config" 2>/dev/null; then
    if ! make "${args[@]}" tools/bpf/resolve_btfids >>"$LOG_FILE" 2>&1; then
      die_log "$LOG_FILE" "预检失败: tools/bpf/resolve_btfids 构建失败 (通常缺少 libelf-dev / libz-dev)"
    fi
  fi
  # 4.19 等老内核: KSU 的 selinux 代码 include 内核 security/selinux 生成的 flask.h;
  # 完整构建时 security/ 先于 drivers/ 构建所以没问题, 单独预检则需先生成它
  if ! make "${args[@]}" security/selinux/ >>"$LOG_FILE" 2>&1; then
    warn "预检: security/selinux/ 预构建失败 (完整构建时会重试, 先继续)"
  fi
  if ! make "${args[@]}" -k drivers/kernelsu/ 2>&1 | tee -a "$LOG_FILE"; then
    die_log "$LOG_FILE" "预检失败: drivers/kernelsu 编译出错 (详见上方日志尾部)"
  fi
  info "开始编译内核 (make -j$JOBS, 通常需要 10~60 分钟; 日志: $LOG_FILE) ..."
  if ! make "${args[@]}" Image.gz 2>&1 | tee -a "$LOG_FILE"; then
    # 部分厂商 QGKI 片段把驱动标成 =m(厂家构建会单独打包模块), 而本工具只产出 Image;
    # 这类树首次链接会因引用模块符号 undefined reference(veux 的 qpnp_pon_*/qcom_smem_get)。
    # 仅当确实出现 undefined reference 时, 把 =m 全部转 =y 内置后重试一次(自适应, 避免
    # 影响原本能正常编的 5.10/5.15/6.x 树 —— 盲目全转可能触发重复符号/厂商源码结构问题)。
    if [ "$KSU_BRANCH" = builtin ] && [ "$SEL_GKI" != 1 ] \
       && grep -q 'undefined reference' "$LOG_FILE" \
       && grep -qE '^CONFIG_[A-Za-z0-9_]+=m$' "$OUT_DIR/.config"; then
      local m2n
      m2n="$(grep -cE '^CONFIG_[A-Za-z0-9_]+=m$' "$OUT_DIR/.config" || true)"
      warn "首次链接出现模块符号缺失: 片段把 ${m2n:-0} 个驱动标为 =m, 本工具不打包模块 → 转为 =y 内置后重试"
      sed -i -E 's/^(CONFIG_[A-Za-z0-9_]+)=m$/\1=y/' "$OUT_DIR/.config"
      make "${args[@]}" olddefconfig >>"$LOG_FILE" 2>&1 || true
      if ! make "${args[@]}" Image.gz 2>&1 | tee -a "$LOG_FILE"; then
        die_log "$LOG_FILE" "内核编译失败 (Image.gz, =m 转 =y 重试后仍失败)"
      fi
    else
      die_log "$LOG_FILE" "内核编译失败 (Image.gz)"
    fi
  fi
  if [ ! -f "$OUT_DIR/arch/arm64/boot/Image.gz" ]; then
    if [ -f "$OUT_DIR/arch/arm64/boot/Image" ]; then
      warn "Image.gz 目标缺失, 手动 gzip 压缩 Image"
      gzip -k -f -9 "$OUT_DIR/arch/arm64/boot/Image"
    else
      die_log "$LOG_FILE" "编译产物缺失: 未生成 Image"
    fi
  fi
  info "编译 DTB ..."
  if ! make "${args[@]}" dtbs 2>&1 | tee -a "$LOG_FILE"; then
    warn "DTB 编译失败 (不影响内核本体, 继续)"
  fi
  if [ "$KSU_MODE" = m ]; then
    info "编译内核模块 (kernelsu.ko) ..."
    if ! make "${args[@]}" modules 2>&1 | tee -a "$LOG_FILE"; then
      die_log "$LOG_FILE" "模块编译失败"
    fi
    if [ ! -f "$OUT_DIR/drivers/kernelsu/kernelsu.ko" ]; then
      warn "未找到 kernelsu.ko! 请确认 CONFIG_KSU=m 已生效"
    fi
  fi
  ok "内核编译完成"
}

# --------------------------------- 打包 ------------------------------------
package_output() {
  mkdir -p "$OUTPUT_DIR"
  # 产物命名: 品牌_机型_机型代码_内核版本_SukiSU-<版本>_<日期时间>
  local base
  base="$(build_artifact_base "$BUILD_BRAND" "$BUILD_MODEL")"
  if [ "$KSU_MODE" = m ]; then
    local ko="$OUT_DIR/drivers/kernelsu/kernelsu.ko"
    if [ -f "$ko" ]; then
      ARTIFACT_PATH="$OUTPUT_DIR/${base}.ko"
      cp "$ko" "$ARTIFACT_PATH"
      ok "LKM 产物: $ARTIFACT_PATH"
      info "使用方法: SukiSU 管理器 → 安装 → 使用本地 LKM 文件 (仅支持 .ko)"
      write_release_notes "$base" "$ARTIFACT_PATH"
    else
      die "kernelsu.ko 不存在, 无法产出 LKM 产物"
    fi
    return 0
  fi
  if [ ! -d "$AK3_DIR/.git" ]; then
    info "下载 AnyKernel3 ..."
    rm -rf "$AK3_DIR"
    if ! git clone --depth 1 "$AK3_REPO" "$AK3_DIR"; then
      die "AnyKernel3 克隆失败"
    fi
  fi
  rm -rf "$PKG_DIR"
  mkdir -p "$PKG_DIR"
  ( cd "$AK3_DIR" && tar cf - --exclude=.git . ) | ( cd "$PKG_DIR" && tar xf - )
  # 内核镜像
  local img=""
  if [ -f "$OUT_DIR/arch/arm64/boot/Image.gz" ]; then
    img="$OUT_DIR/arch/arm64/boot/Image.gz"
  else
    img="$OUT_DIR/arch/arm64/boot/Image"
  fi
  [ -n "$img" ] && [ -f "$img" ] || die "未找到内核镜像 Image.gz / Image"
  cp "$img" "$PKG_DIR/"
  # DTB: 只收集设备厂商目录 (dts/vendor) 的 dtb; 若公开源码不含厂商 dtb
  # (如部分小米 sm8250 机型), 不打包任何 dtb, 由 AnyKernel3 保留原机 dtb,
  # 绝不打包 dts/qcom 等上游参考板 dtb (会覆盖原机 dtb 导致无法开机)。
  local -a dtbs=()
  local f
  while IFS= read -r f; do
    case "$f" in *overlay*|*dtbo*) ;; *) dtbs+=("$f") ;; esac
  done < <(find "$OUT_DIR/arch/arm64/boot/dts/vendor" -name "*.dtb" 2>/dev/null | sort)
  if (( ${#dtbs[@]} == 1 )); then
    cp "${dtbs[0]}" "$PKG_DIR/dtb"
    info "打包 DTB: $(basename "${dtbs[0]}")"
  elif (( ${#dtbs[@]} > 1 )); then
    mkdir -p "$PKG_DIR/dtb"
    cp "${dtbs[@]}" "$PKG_DIR/dtb/"
    info "打包 DTB: ${#dtbs[@]} 个 (dtb/ 目录)"
  else
    info "未找到厂商 DTB (dts/vendor): 不打包 dtb, AnyKernel3 将保留原机 dtb"
  fi
  # DTBO
  if [ -f "$OUT_DIR/arch/arm64/boot/dtbo.img" ]; then
    cp "$OUT_DIR/arch/arm64/boot/dtbo.img" "$PKG_DIR/dtbo.img"
  fi
  # anykernel.sh
  cat > "$PKG_DIR/anykernel.sh" <<'AKEOF'
# AnyKernel3 Ramdisk Mod Script
# osm0sis @ xda-developers
properties() { '
kernel.string=SukiSU-Ultra Kernel Builder
do.devicecheck=0
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
supported.versions=
supported.patchlevels=
'; }
block=auto;
is_slot_device=auto;
ramdisk_compression=auto;
. /tmp/anykernel/tools/ak3-core.sh;
split_boot;
flash_boot;
flash_dtbo;
AKEOF
  ARTIFACT_PATH="$OUTPUT_DIR/${base}.zip"
  ( cd "$PKG_DIR" && rm -f "$ARTIFACT_PATH" && zip -r9q "$ARTIFACT_PATH" . )
  ok "AnyKernel3 产物: $ARTIFACT_PATH"
  info "刷入方式: TWRP 等支持 AnyKernel3 的 Recovery 刷入; 刷入前请务必备份原 boot 分区"
  write_release_notes "$base" "$ARTIFACT_PATH"
}

# --------------------------------- 主流程 ----------------------------------
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --list)      OPT_LIST=1 ;;
      --device)    SEL_DEVICE_ID="${2:?--device 需要一个值}"; shift ;;
      --version)   OPT_VERSION="${2:?--version 需要一个值}"; shift ;;
      --repo)      SEL_REPO="${2:?--repo 需要一个值}"; shift ;;
      --branch)    SEL_BRANCH="${2:?--branch 需要一个值}"; OPT_BRANCH_GIVEN=1; shift ;;
      --defconfig) SEL_DEFCONFIG="${2:?--defconfig 需要一个值}"; shift ;;
      --kver)      SEL_KVER="${2:?--kver 需要一个值}"; shift ;;
      --android)   SEL_ANDROID="${2:?--android 需要一个值}"; shift ;;
      --gki)       SEL_GKI=1 ;;
      --ksu)       KSU_BRANCH="${2:?--ksu 需要一个值}"; shift ;;
      --ksu-mode)  KSU_MODE="${2:?--ksu-mode 需要一个值}"; shift ;;
      --kpm)       OPT_KPM=1 ;;
      --debug-ksu) OPT_KSU_DEBUG=1 ;;
      --susfs)     OPT_SUSFS=1 ;;
      --clang)     OPT_CLANG="${2:?--clang 需要一个值}"; shift ;;
      --gcc)       OPT_GCC=1 ;;
      --jobs)      JOBS="${2:?--jobs 需要一个值}"; shift ;;
      --no-pack)   OPT_NO_PACK=1 ;;
      --dry-run)   OPT_DRY_RUN=1 ;;
      --resume)    OPT_RESUME=1 ;;
      --clean)     OPT_CLEAN=1 ;;
      --yes)       OPT_YES=1 ;;
      -h|--help)   usage; exit 0 ;;
      *) die "未知参数: $1 (用 -h 查看帮助)" ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"
  echo
  echo "  SukiSU-Ultra 内核编译工具 v1.0"
  echo "  教程: https://sukisu.org/zh/guide/how-to-integrate"
  echo
  load_devices
  if [ "$OPT_LIST" = 1 ]; then list_devices; exit 0; fi
  if [ "$OPT_DRY_RUN" != 1 ]; then check_deps; fi

  if [ "$OPT_CLEAN" = 1 ] && [ "$OPT_YES" != 1 ]; then
    if ! read -rp "确认清空 work/ 目录并重新开始? [y/N] " yn; then yn=""; fi
    yn="${yn%$'\r'}"
    if [[ ! "$yn" =~ ^[yY] ]]; then echo "已取消。"; exit 0; fi
  fi

  # 1) 选设备 / 内核版本
  if [ -z "$SEL_REPO" ]; then
    if [ -n "$OPT_VERSION" ] && [ -z "$SEL_DEVICE_ID" ]; then
      die "--version 必须配合 --device 使用"
    fi
    if [ -z "$SEL_DEVICE_ID" ]; then
      if [ "$OPT_BRANCH_GIVEN" = 1 ]; then
        local row
        for row in "${DEV_ROWS[@]}"; do
          if [ "$(row_field "$row" 5)" = "$SEL_BRANCH" ]; then
            SEL_DEVICE_ID="$(row_field "$row" 1)"
            break
          fi
        done
        [ -n "$SEL_DEVICE_ID" ] || die "设备库中未找到分支: $SEL_BRANCH"
      else
        choose_device
      fi
    fi
    choose_version
  else
    # 自定义内核源
    SEL_DEVICE_ID="${SEL_DEVICE_ID:-custom}"
    [ -n "$SEL_BRANCH" ] || die "自定义内核源 (--repo) 必须提供 --branch"
    SEL_DISPLAY="自定义内核"
    SEL_VERLABEL="$SEL_REPO @ $SEL_BRANCH"
    SEL_KVER="${SEL_KVER:-}"
    SEL_ANDROID="${SEL_ANDROID:-12}"
    SEL_DEFCONFIG="${SEL_DEFCONFIG:-}"
  fi

  # 2) 集成分支
  choose_ksu_branch
  # 3) 工具链策略
  decide_toolchain

  # 产物命名信息 (品牌 + 机型)
  local _bm
  _bm="$(derive_brand_model "$SEL_DISPLAY" "$SEL_DEVICE_ID")"
  BUILD_BRAND="${_bm%%|*}"
  BUILD_MODEL="${_bm#*|}"

  # 4) 汇总确认
  echo
  info "==================== 编译任务 ===================="
  printf "  设备       : %s (%s)\n" "$SEL_DISPLAY" "$SEL_DEVICE_ID"
  printf "  内核版本   : %s\n" "$SEL_VERLABEL"
  printf "  仓库/分支  : %s @ %s\n" "$SEL_REPO" "$SEL_BRANCH"
  printf "  defconfig  : %s\n" "${SEL_DEFCONFIG:-自动探测}"
  printf "  SukiSU     : %s 分支, CONFIG_KSU=%s\n" "$KSU_BRANCH" "$KSU_MODE"
  if [ "$USE_CLANG" = 1 ]; then
    printf "  编译器     : Clang (%s)\n" "${OPT_CLANG:-$(clang_spec_candidates "$SEL_ANDROID" | awk '{print $1}')}"
  else
    printf "  编译器     : GCC 4.9 (aarch64-linux-android)\n"
  fi
  printf "  并行度     : -j%s\n" "$JOBS"
  if [ "$KSU_MODE" = m ]; then
    printf "  产物       : kernelsu.ko (LKM 模块)\n"
  else
    printf "  产物       : AnyKernel3 zip (内置)\n"
  fi
  local _eg
  _eg="$(build_artifact_base "$BUILD_BRAND" "$BUILD_MODEL" "${SEL_KVER:-4.19.113}" "20261120-2003" "v3.0.0")"
  printf "  产物命名   : <品牌>_<机型>_<代码>_<内核版本>_SukiSU-<版本>_<日期时间>.zip\n"
  printf "               例: %s.zip\n" "$_eg"
  echo "===================================================="
  if [ "$OPT_DRY_RUN" = 1 ]; then
    info "演练模式 (--dry-run): 以上即为将执行的任务, 未下载/编译任何内容。去掉 --dry-run 即可正式开始。"
    exit 0
  fi
  if [ "$OPT_YES" != 1 ]; then
    if ! read -rp "开始编译? [Y/n] " yn; then yn=""; fi
    yn="${yn%$'\r'}"
    if [[ ! "$yn" =~ ^[yY]?$ ]]; then echo "已取消。"; exit 0; fi
  fi

  mkdir -p "$BASE_DIR" "$OUTPUT_DIR"
  : > "$LOG_FILE"

  # 5) 工具链 → 6) 源码 → 7) 集成 → 8) defconfig → 9) 配置 → 10) 编译 → 11) 打包
  setup_toolchain
  fetch_kernel
  compat_fixups
  fix_missing_kconfig_sources
  fix_missing_makefile_objs
  detect_kver
  # SukiSU builtin 面向 4.4+, 3.18/3.10 等更老内核缺太多新内核接口 (nullptr、ns_get_path、
  # d_is_reg、seq_has_overflowed …), 官方也标为实验性 → 提前失败, 不浪费一次完整编译
  local _kvmaj="${KVER%%.*}"
  if [ -n "$_kvmaj" ] && [ "$_kvmaj" -lt 4 ]; then
    die "内核 $KVER 太老: SukiSU-Ultra 仅支持 Linux 4.4+, 3.x 不受支持 (可用自定义源编译但不保证可用)"
  fi
  integrate_sukisu
  KSU_VERSION="$(resolve_ksu_version)"
  info "SukiSU-Ultra 版本: $KSU_VERSION"
  ksu_compat_fixups
  pick_defconfig
  info "使用 defconfig: $DEFCONFIG"
  make_config
  build_kernel

  if [ "$OPT_NO_PACK" = 1 ]; then
    info "已跳过打包 (--no-pack)。编译产物: $OUT_DIR/arch/arm64/boot/"
    if [ "$KSU_MODE" = m ]; then
      info "LKM 模块: $OUT_DIR/drivers/kernelsu/kernelsu.ko"
    fi
  else
    package_output
  fi

  echo
  ok "全部完成! 产物目录: $OUTPUT_DIR"
  [ -n "$ARTIFACT_PATH" ] && ok "产物文件: $ARTIFACT_PATH"
  if [ -n "$ARTIFACT_PATH" ] && [ -f "$OUTPUT_DIR/release-notes.md" ]; then
    info "发布备注: $OUTPUT_DIR/release-notes.md"
  fi
  if [ "$KSU_MODE" = m ]; then
    info "提示: GKI 设备可在管理器中选择对应 KMI, 或直接使用本地 LKM 文件刷入"
  else
    info "提示: 刷入 zip 前请备份原 boot 分区; 遇到卡第一屏可用该备份恢复"
  fi
}

main "$@"
