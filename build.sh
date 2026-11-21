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

# 解析 SukiSU 版本 (best-effort): git describe > 远端 tag 列表 + 短提交 > 短提交 > unknown
# setup.sh 的浅克隆 (--depth 1) 没有 tag 历史, describe 只会回落到提交号;
# 这里用 ls-remote 取最新语义 tag 再拼上短提交, 例如 v3.0.0_4bec532
resolve_ksu_version() {
  local d="$KERNEL_DIR/KernelSU" v="" v2="" short="" lt=""
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
    case "$v" in
      *_*)                          # TAG_HASH 形态: tag 部分必须是语义版本, 否则改用远端最新语义 tag
         local _tag="${v%_*}" _hash="${v##*_}"
         case "$_tag" in
           v[0-9]*|[0-9]*) : ;;
           *) lt="$(git -C "$d" ls-remote --tags origin 2>/dev/null |
                    awk -F/ '{print $NF}' | grep -v '\^{}' |
                    grep -E '^v?[0-9]+\.[0-9]+' | sort -V | tail -1 || true)"
              [ -n "$lt" ] && v="${lt}_${_hash}" ;;
         esac ;;
    esac
    case "$v" in
      ""|*[!0-9a-f]*) : ;;          # 空 或 真的带了 tag 名/版本号, 直接用
      *)                            # 纯提交号: 取远端最新语义 tag 拼短提交
         short="$v"
         lt="$(git -C "$d" ls-remote --tags origin 2>/dev/null |
               awk -F/ '{print $NF}' | grep -v '\^{}' |
               grep -E '^v?[0-9]+\.[0-9]+' | sort -V | tail -1 || true)"
         if [ -n "$lt" ]; then
           v="${lt}_${short}"
         fi ;;
    esac
    [ -n "$v" ] || v="$(git -C "$d" rev-parse --short HEAD 2>/dev/null || true)"
  fi
  [ -n "$v" ] || v="unknown"
  sanitize_name "$v"
}

# 中文机型名 (取自 tools/device_zh.tsv; 用于 Release 资产命名)
resolve_device_zh() {
  local id="${1:-$SEL_DEVICE_ID}" tsv="$SCRIPT_DIR/tools/device_zh.tsv"
  [ -n "$id" ] && [ -f "$tsv" ] || return 0
  awk -F'\t' -v want="$id" '$1 == want { print $2; exit }' "$tsv"
}

# Release 资产名清洗: 保留中文/字母/数字/._+-, 空白与路径分隔符换成下划线
sanitize_asset_name() {
  # 只保留 ASCII 字母数字与 ._- : GitHub 会把 Release 资产名里的非 ASCII 字符静默删掉,
  # 所以统一 Release 里一律用 ASCII 资产名, 中文机型名在 README 索引里做映射
  printf '%s' "$1" | sed -e 's/[^A-Za-z0-9._-]/_/g' -e 's/_\{1,\}/_/g' -e 's/^_//' -e 's/_$//'
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
  # 合集 Release 里用的稳定资产名 (同名覆盖, README 里的链接可长期使用)
  # 注意: GitHub 的 Release 资产名不允许非 ASCII 字符 (中文会被直接吃掉, 红米8_x.zip → 8_x.zip),
  # 所以这里用 品牌_机型_代码_内核版本 的 ASCII 形式; 中文机型名在 README「内核下载索引」
  # 与 Release 说明里做映射, 用户按中文名照样能一键找到。
  local ext
  case "$art" in
    *.ko) ext=".ko" ;;
    *) ext=".zip" ;;
  esac
  local -a an=()
  local part
  for part in "$BUILD_BRAND" "$BUILD_MODEL" "$SEL_DEVICE_ID" "$KVER"; do
    part="$(sanitize_asset_name "$part")"
    [ -n "$part" ] && an+=("$part")
  done
  local IFS=_
  printf '%s\n' "${an[*]}${ext}" > "$OUTPUT_DIR/RELEASE_ASSET"
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
    # LKM 模式 (CONFIG_KSU=m) 需要目标内核树导出 kernelsu.ko 依赖的全部符号
    # (path_umount / init_mm / __arm64_sys_setns ...)。上游 AOSP 镜像树导出不全,
    # modpost 会 undefined; 真机 GKI 内核的 KMI 符号表才是完整的。
    # 因此默认两种设备都编内置 (KSU=y, main 分支用 kprobes): 产物是 AnyKernel3 zip,
    # 刷入后由管理器接管。需要 LKM 时显式 --ksu-mode m。
    KSU_MODE=y
    if [ "$SEL_GKI" = 1 ]; then
      info "KSU 模式(自动): 内置 (GKI 也默认内置; 上游镜像树 LKM 符号导出不全, 需要 LKM 请加 --ksu-mode m)"
    fi
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
    # 工具链缓存来自 actions/cache (restore-keys 会回退到"任意"工具链缓存),
    # 可能拿到与目标内核不匹配的旧 clang (如 6.12 需要 Clang>=13, 却恢复了 clang-r416183b
    # 的 12.0.5 → "C compiler is too old")。用 .suki_spec 记录本目录对应的规格,
    # 不匹配则丢弃重下, 保证 "设备/Android 版本 → clang 版本" 的映射真正生效。
    local want_spec=""
    if [ -n "$OPT_CLANG" ]; then
      want_spec="$OPT_CLANG"
    else
      want_spec="$(clang_spec_candidates "$SEL_ANDROID" | awk '{print $1}')"
    fi
    if [ -x "$CLANG_DIR/bin/clang" ] && [ -n "$want_spec" ]; then
      if [ -f "$CLANG_DIR/.suki_spec" ] && [ "$(cat "$CLANG_DIR/.suki_spec" 2>/dev/null)" = "$want_spec" ]; then
        info "复用已下载的 Clang: $CLANG_DIR ($want_spec)"
      else
        warn "已缓存的 Clang 与目标规格不符 (期望 $want_spec, 目录里是 $(cat "$CLANG_DIR/.suki_spec" 2>/dev/null || echo 未知)), 重新下载"
        rm -rf "$CLANG_DIR"
      fi
    fi
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
              mv "$CLANG_DIR.tmp/$dir" "$CLANG_DIR"; ok=1
            elif [ -x "$CLANG_DIR.tmp/bin/clang" ]; then
              mv "$CLANG_DIR.tmp" "$CLANG_DIR"; ok=1
            fi
            if [ "$ok" = 1 ]; then
              printf '%s\n' "$spec" > "$CLANG_DIR/.suki_spec"
              break
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
  # 厂商驱动的 Makefile 常自带 -Werror (subdir-ccflags-y := -Werror / KBUILD_CFLAGS += -Werror /
  # EXTRA_CFLAGS 之类), 会把 clang 独有告警 (pointer-to-int-cast、unused-but-set 等) 升格成错误,
  # 而厂商用 gcc 构建时不报 → 老厂商树用 clang 编不过 (run #40/#47 agate eccci、fire aw87xxx、
  # fire primary_display 等)。把 Makefile/Kbuild 里出现的 -Werror 一律降级为 -Wno-error
  # (-Werror=foo → -Wno-error=foo, 保留按告警的开关语义)。跳过 scripts/ 与 tools/, 避免破坏 kbuild 自身。
  # 只改带 '=' 的 -Werror=foo 与裸 -Werror; 绝不动 -Werror-implicit-function-declaration 这类
  # 短横线形式 (老 gcc 把它当合法独立选项, 被改成 -Wno-error-implicit-... 会变成未知选项 →
  # 任何带 -Werror 的 cc-option 探测都失败 → KBUILD_CFLAGS 相关能力全被误判缺失,
  # 4.9 树上直接报 "Cannot use CONFIG_CC_STACKPROTECTOR_STRONG")。
  # 顶层 Makefile/Kbuild 不在此循环处理 (见下方独立块), 避免破坏 kbuild 的探测链。
  local mkvm mknum=0
  while IFS= read -r mkvm; do
    case "$mkvm" in
      ./Makefile|Makefile|./Kbuild|Kbuild) continue ;;
    esac
    if sed -i -E 's/-Werror=/-Wno-error=/g; s/(^|[^A-Za-z0-9_-])-Werror([[:space:]]|$)/\1-Wno-error\2/g' "$mkvm" 2>/dev/null; then
      mknum=$((mknum + 1))
    fi
  done < <(find . \( -name '.git' -o -name 'scripts' -o -name 'tools' \) -prune -o \
             \( -name 'Makefile' -o -name 'Kbuild' -o -name '*.mk' \) \
             -exec grep -l -- '-Werror' {} + 2>/dev/null || true)
  if [ "$mknum" -gt 0 ]; then
    info "兼容修复: 将 $mknum 个厂商 Makefile/Kbuild 中的 -Werror 全部降级为 -Wno-error (clang 专属告警在 gcc 下只是警告)"
  fi
  # 顶层 Makefile 也可能在 KBUILD_CFLAGS 里追加 -Werror, 且位置在 $(KCFLAGS) 之后 →
  # KCFLAGS 里的 -Wno-error 会被覆盖, clang 专属告警仍变错误 (begonia-q 4.14: mm/rmap.c
  # 的 -Wvoid-pointer-to-enum-cast)。直接从顶层 Makefile 的 KBUILD_CFLAGS/AFLAGS 行里摘掉 -Werror。
  local topmk=Makefile
  if [ -f "$topmk" ] && grep -qE '^[[:space:]]*KBUILD_(CFLAGS|AFLAGS)[^#]*-Werror' "$topmk"; then
    info "兼容修复: 顶层 Makefile 的 KBUILD_CFLAGS -Werror 降级为 -Wno-error (厂商追加, 会让 clang 专属告警升格成错误)"
    sed -i -E '/^[[:space:]]*KBUILD_(CFLAGS|AFLAGS)/{ s/-Werror=/-Wno-error=/g; s/-Werror([[:space:]]|$)/-Wno-error\1/g }' "$topmk"
  fi
  # 部分 5.10 树把 `-std=gnu89 -Werror` 与 `-Werror=implicit-function-declaration` 写在
  # KBUILD_CFLAGS 的**续行**里(不在赋值行首), 上面的行首匹配抓不到 → rubens/yunluo 5.10.66/.81
  # 的 ged_bridge.c 仍报 [-Werror,-Wimplicit-function-declaration]。这里补一遍具名告警降级 +
  # 裸 -Werror 降级; $(call cc-option,-Werror=...) 是 ",-Werror" 形式, 前后都不是空白, 不会误伤。
  if [ -f "$topmk" ] && grep -q -- '-Werror' "$topmk"; then
    sed -i -E 's/-Werror=(implicit-function-declaration|implicit-int|return-type|incompatible-pointer-types|int-conversion|static-declaration|format|array-bounds|unused-but-set-variable|unused-variable|unused-function|designated-init)/-Wno-error=\1/g' "$topmk"
    sed -i -E 's/(^|[[:space:]])-Werror([[:space:]])/\1-Wno-error\2/g; s/(^|[[:space:]])-Werror$/\1-Wno-error/g; s/(^|[[:space:]])-Werror\\($| )/\1-Wno-error\\\2/g' "$topmk"
    info "兼容修复: 顶层 Makefile 续行里的 -Werror / -Werror=<具名告警> 一并降级"
  fi
  # __start_builtin_fw 若未 8 字节对齐, clang 生成的 adrp+ldr 会触发
  # "relocation truncated to fit: R_AARCH64_LDST64_ABS_LO12_NC against __start_builtin_fw"
  # (biloba/camellian 4.14.186 实测, firmware_class.c:58)。在 .builtin_fw 里插入 ALIGN(8)。
  local vl=include/asm-generic/vmlinux.lds.h
  if [ -f "$vl" ] && grep -q 'VMLINUX_SYMBOL(__start_builtin_fw)' "$vl" \
     && ! grep -q 'suki-builder: align builtin_fw' "$vl"; then
    if awk '
      /VMLINUX_SYMBOL\(__start_builtin_fw\)/ && !done {
        if (prev !~ /ALIGN\(8\)/) {
          print "\t\t. = ALIGN(8); /* suki-builder: align builtin_fw */\t\\"
          done = 1
        }
      }
      { print; prev = $0 }
    ' "$vl" > "$vl.tmp_bfw" 2>/dev/null && mv "$vl.tmp_bfw" "$vl"; then
      info "兼容修复: vmlinux.lds.h 的 __start_builtin_fw 前加 ALIGN(8) (clang LDST64 重定位截断)"
    else
      rm -f "$vl.tmp_bfw"
    fi
  fi
  # 兜底: 在顶层 Makefile 末尾追加 -Wno-error。部分厂商树把 -Werror 藏在 include/其它 Makefile
  # 或 cc-option 里 (begonia-q 4.14: mm/rmap.c 的 -Wvoid-pointer-to-enum-cast 仍被 -Werror 升格),
  # 追加到文件末尾可确保位于所有 KBUILD_CFLAGS += 之后, 后出现的 -Wno-error 覆盖 -Werror。
  if [ -f "$topmk" ] && ! grep -q 'sukisu-builder: demote -Werror' "$topmk"; then
    {
      printf '\n# suki-builder: demote -Werror to warning (vendor trees 混入 -Werror, 会让 clang 专属告警变错误)\n'
      printf 'KBUILD_CFLAGS += -Wno-error\n'
    } >> "$topmk"
    info "兼容修复: 顶层 Makefile 末尾追加 KBUILD_CFLAGS += -Wno-error (兜底抑制 -Werror)"
  fi
  # drivers/char/rpmb/rpmb-mtk.c: mtk_mmc_host 数组的声明在 #if IS_ENABLED(CONFIG_MMC_MTK_PRO) 里,
  # 但 TEE 路径 (#if IS_ENABLED(CONFIG_TRUSTONIC_TEE_SUPPORT)) 也引用它。厂商 defconfig 同时写了
  # CONFIG_MMC_MTK=m 与 CONFIG_MMC_MTK_PRO=m, 而 Kconfig 里 MMC_MTK_PRO depends on !MMC_MTK →
  # olddefconfig 把 MMC_MTK_PRO 丢掉 → "use of undeclared identifier 'mtk_mmc_host'"
  # (yunluo 5.10.101 / daumier 5.10.81 / yuechu 5.10.136 实测)。
  # 给这个 #if 补一个 TEE 分支的 #elif 声明: 若 MMC_MTK_PRO 已启用则走原分支, 新分支不会生效,
  # 不存在重复定义; 只在两个开关都关时两条都不生效。
  local rmf=drivers/char/rpmb/rpmb-mtk.c
  if [ -f "$rmf" ] && grep -qE 'static struct mmc_host \*mtk_mmc_host\[\] = \{NULL\};' "$rmf" \
     && ! grep -q 'suki-builder: rpmb mtk_mmc_host fallback' "$rmf"; then
    if awk '
      /static struct mmc_host \*mtk_mmc_host\[\] = \{NULL\};/ && !decl { decl = 1; print; next }
      decl && /^[[:space:]]*#endif/ {
        print "#elif IS_ENABLED(CONFIG_TRUSTONIC_TEE_SUPPORT) /* suki-builder: rpmb mtk_mmc_host fallback */"
        print "static struct mmc_host *mtk_mmc_host[] = {NULL};"
        print "#endif"
        decl = 0; next
      }
      { print }
    ' "$rmf" > "$rmf.tmp_rpmb" 2>/dev/null && mv "$rmf.tmp_rpmb" "$rmf"; then
      info "兼容修复: rpmb-mtk.c 的 mtk_mmc_host 声明补 TEE 分支 (MMC_MTK_PRO 依赖 !MMC_MTK 被配置系统丢弃)"
    else
      rm -f "$rmf.tmp_rpmb"
    fi
  fi
  # 厂商改过的 scripts/mkcompile_h (如 OnePlus sm8250 4.19 的 L57) 会写 bash 专属展开
  # `${CURRENT_RELEASE//\//\\\\}`, 而 kbuild 用 CONFIG_SHELL(/bin/sh=dash) 调用它 →
  # "mkcompile_h: 57: Bad substitution" → include/generated/compile.h 生成失败 (op9 5.4/op8t 4.19)。
  # 在最前面插入一段 dash 兼容的 bash 重执行守卫, 让脚本用 bash 跑完 (不改原逻辑)。
  local mkc=scripts/mkcompile_h
  if [ -f "$mkc" ] && grep -qE '\$\{[A-Za-z_][A-Za-z0-9_]*//' "$mkc" \
     && ! grep -q 'suki-builder: ensure bash' "$mkc"; then
    if awk '
      NR == 1 { print; print "# suki-builder: ensure bash (脚本含 bash 专属参数展开, dash 会 Bad substitution)"; print "[ -z \"${BASH_VERSION}\" ] && [ -x /bin/bash ] && exec /bin/bash \"$0\" \"$@\""; next }
      { print }
    ' "$mkc" > "$mkc.tmp_sh" 2>/dev/null && mv "$mkc.tmp_sh" "$mkc"; then
      chmod +x "$mkc" 2>/dev/null || true
      info "兼容修复: scripts/mkcompile_h 加 bash 重执行守卫 (厂商脚本含 dash 不支持的 \${var//} 展开)"
    else
      rm -f "$mkc.tmp_sh"
    fi
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
  # 宏形式的固件数组: `#define XXX_FW_FILE "include/firmware/xyz.i"` + 源码里 `#include XXX_FW_FILE`
  # (focaltech_spi / fts8719 / 其它触摸驱动的通病; 宏值路径不会出现在 include 行字面里,
  # 上面的字面扫描抓不到, 表现为 begonia-q 的 'include/firmware/focal_g7_01.i' not found)。
  # 处理方式: 取宏值路径, 在树根与"每个 #include 该宏的源文件所在目录"下各写一份占位字节
  # (引号 include 优先相对源文件目录解析, 同时兼容 -I 根目录写法)。
  local md mname mpath csrc cdir
  while IFS= read -r md; do
    [ -n "$md" ] || continue
    mname=$(printf '%s\n' "$md" | sed -E 's/^[[:space:]]*#define[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/')
    mpath=$(printf '%s\n' "$md" | sed -E 's/^[^"]*"([^"]+\.i)".*/\1/')
    [ -n "$mname" ] && [ -n "$mpath" ] || continue
    if [ ! -e "$mpath" ]; then
      mkdir -p "$(dirname "$mpath")"
      printf '0x00, 0x00, 0x00, 0x00\n' > "$mpath"
      warn "厂商源码缺失闭源固件(宏 $mname): $mpath -> 已写入占位字节"
      blobn=$((blobn+1))
    fi
    while IFS= read -r csrc; do
      [ -n "$csrc" ] || continue
      cdir=$(dirname "$csrc")
      if [ ! -e "$cdir/$mpath" ]; then
        mkdir -p "$(dirname "$cdir/$mpath")"
        printf '0x00, 0x00, 0x00, 0x00\n' > "$cdir/$mpath"
        blobn=$((blobn+1))
      fi
    done < <(grep -rIl --include='*.c' --include='*.h' -E "^[[:space:]]*#include[[:space:]]+${mname}([[:space:]]*|[[:space:]]*//.*)$" drivers 2>/dev/null || true)
  done < <(grep -rIh --include='*.c' --include='*.h' -E '^[[:space:]]*#define[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+"[^"]+\.i"' drivers 2>/dev/null | sort -u || true)
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
  # 小米 5.10 公开树 (marble/mayfly/garnet/sky/yudi 等) 的 drivers/usb/gadget/udc/core.c
  # 把 usb_gadget_{enable,disable}_async_callbacks 的 static inline 实现写了两遍(厂商合并
  # 上游 commit 65e6c2f3 时重复应用) → "error: redefinition of 'usb_gadget_enable_async_callbacks'"
  # (报在第二份定义行, 批跑 #11 的 mayfly/marble/garnet 等 5.10 树)。两份实现完全相同,
  # 首次定义无人调用(调用点都在文件后部) → 把第一份重命名为 suki_dup_* 即可。
  local udcc=drivers/usb/gadget/udc/core.c
  if [ -f "$udcc" ]; then
    local dupn=0 fnn
    for fnn in usb_gadget_enable_async_callbacks usb_gadget_disable_async_callbacks; do
      [ "$(grep -c "^static inline void $fnn" "$udcc")" -ge 2 ] || continue
      awk -v fn="$fnn" '
        index($0, "static inline void " fn) == 1 {
          c++
          if (c == 1) sub("static inline void " fn, "static inline void suki_dup_" fn)
        }
        { print }
      ' "$udcc" > "$udcc.tmp_usb" 2>/dev/null && mv "$udcc.tmp_usb" "$udcc" || rm -f "$udcc.tmp_usb"
      dupn=$((dupn+1))
    done
    [ "$dupn" -gt 0 ] && info "兼容修复: usb gadget core.c 里重复的 static inline async_callbacks 定义已重命名 ($dupn 处)"
  fi
  # OnePlus(sm8250/sm8350) 公开树缺 include/linux/sched_assist/ (厂商私有调度增强头),
  # 但 OplusKernelEnvConfig.mk 的 ALLOWED_MCROS 会自动 -DOPLUS_FEATURE_SCHED_ASSIST →
  # include/linux/mutex.h 里的 #include <linux/sched_assist/sched_assist_mutex.h> 直接
  # fatal error (op8t 4.19 实测)。公开树里该特性不完整, 安全做法=只注释包含行
  # (绝不能改 OplusKernelEnvConfig.mk 列表行, 行尾 \ 续行被破坏会报 missing separator)。
  if [ ! -d include/linux/sched_assist ]; then
    local sasnum=0 sasf
    while IFS= read -r sasf; do
      sed -i -E 's@^([[:space:]]*)#include <linux/sched_assist/[^>]+>@\1/* suki-builder: sched_assist header not published */@' "$sasf"
      sasnum=$((sasnum+1))
    done < <(grep -rlE '^[[:space:]]*#include <linux/sched_assist/' include/linux 2>/dev/null || true)
    [ "$sasnum" -gt 0 ] && info "兼容修复: 注释 $sasnum 处 include/linux/sched_assist/... (公开树缺该私有目录)"
  fi
  # AOSP vendor hook 头 (include/trace/hooks/*.h) 在部分小米树里未公开, 但经过厂商改造的
  # 驱动仍然 #include 它们并调用 trace_android_vh_/rvh_* 钩子 (mayfly 5.10.81 的
  # drivers/thermal/thermal_core.c:27 → trace/hooks/thermal.h not found)。钩子在公开树里
  # 本来就是空实现, 这里为每个缺失头生成桩: 把树里出现过的 trace_android_vh_/rvh_ 标识符
  # 全部定义成无副作用的可变参宏 (do{}while(0)), 包含该头的文件即可正常编译。
  local hvmiss hvink hvids hvnum=0 hvstub hn
  hvmiss="$(mktemp)"; hvids="$(mktemp)"
  grep -rhoE '#include[[:space:]]*<trace/hooks/[A-Za-z0-9_]+\.h>' --include='*.c' --include='*.h' . 2>/dev/null \
    | sed -E 's@.*<([^>]+)>.*@\1@' | sort -u > "$hvids" || true
  : > "$hvmiss"
  while IFS= read -r hn; do
    [ -n "$hn" ] || continue
    [ -e "include/$hn" ] && continue
    printf '%s\n' "$hn" >> "$hvmiss"
  done < "$hvids"
  # 收集树里实际出现的 vendor hook 名
  local hvnames
  hvnames="$(grep -rhoE 'trace_android_(vh|rvh)_[A-Za-z0-9_]+' --include='*.c' --include='*.h' . 2>/dev/null | sort -u || true)"
  if [ -s "$hvmiss" ] && [ -n "$hvnames" ]; then
    while IFS= read -r hn; do
      mkdir -p "$(dirname "include/$hn")"
      {
        printf '/* suki-builder: AOSP vendor hook 头未公开, 生成空桩 (钩子本为空实现) */\n'
        printf '#ifndef SUKI_TRACE_HOOK_STUB_H\n#define SUKI_TRACE_HOOK_STUB_H\n'
        printf '#include <linux/types.h>\n'
        while IFS= read -r hvink; do
          printf '#define %s(...) do { } while (0)\n' "$hvink"
        done <<< "$hvnames"
        printf '#endif\n'
      } > "include/$hn"
      hvnum=$((hvnum+1))
    done < "$hvmiss"
    [ "$hvnum" -gt 0 ] && warn "厂商源码缺失 AOSP vendor hook 头 $hvnum 个 (trace/hooks/*.h), 已生成空桩 (钩子失效, 不影响基本功能)"
  fi
  rm -f "$hvmiss" "$hvids"
  # OnePlus 公开树的 OplusKernelEnvConfig.mk 会把一批 OPLUS_FEATURE_* 直接 -D 上去,
  # 其中部分特性源码未公开 (如 sched_assist 头、oplus_phoenix 驱动), 导致引用处 fatal error
  # (op8t 4.19: init/main.c 里的 ../drivers/soc/oplus/system/oplus_phoenix/oplus_phoenix.h)。
  # 无害做法: 对确认缺源码的特性, 把 ALLOWED_MCROS 里的宏名改成 *_DISABLED (不追加注释,
  # 行尾续行反斜杠一旦被破坏 make 会报 missing separator —— run #97 的教训)。
  local omk=OplusKernelEnvConfig.mk
  if [ -f "$omk" ]; then
    if [ ! -d include/linux/sched_assist ]; then
      sed -i -E 's/(^|[^A-Za-z0-9_])OPLUS_FEATURE_SCHED_ASSIST([^A-Za-z0-9_]|$)/\1OPLUS_FEATURE_SCHED_ASSIST_DISABLED\2/g' "$omk"
    fi
    if [ ! -d drivers/soc/oplus/system/oplus_phoenix ]; then
      sed -i -E 's/(^|[^A-Za-z0-9_])OPLUS_FEATURE_PHOENIX([^A-Za-z0-9_]|$)/\1OPLUS_FEATURE_PHOENIX_DISABLED\2/g' "$omk"
    fi
  fi
  # GKI(android14+/6.x) 上用 main 分支编 LKM 时, kernelsu.ko 需要 vmlinux 导出
  # path_umount / __arm64_sys_close (modpost: undefined!), 而 AOSP 上游树默认不导出 →
  # 直接在对应源文件末尾补 EXPORT_SYMBOL (只在内核树里加, 不影响 ko 与刷机使用)。
  if [ "$KSU_MODE" = m ] && [ "$SEL_GKI" = 1 ]; then
    local nsx=fs/namespace.c ocf=fs/open.c
    if [ -f "$nsx" ] && grep -q '^int path_umount(' "$nsx" && ! grep -q 'EXPORT_SYMBOL(path_umount)' "$nsx"; then
      printf '\n/* suki-builder: export for KernelSU LKM */\nEXPORT_SYMBOL(path_umount);\n' >> "$nsx"
      info "兼容修复(GKI): fs/namespace.c 导出 path_umount (kernelsu.ko modpost 需要)"
    fi
    if [ -f "$ocf" ] && grep -q 'SYSCALL_DEFINE1(close' "$ocf" && ! grep -q 'EXPORT_SYMBOL(__arm64_sys_close)' "$ocf"; then
      printf '\n/* suki-builder: export for KernelSU LKM */\nEXPORT_SYMBOL(__arm64_sys_close);\n' >> "$ocf"
      info "兼容修复(GKI): fs/open.c 导出 __arm64_sys_close (kernelsu.ko modpost 需要)"
    fi
  fi
  # 厂商源码 #include "hwid.h" 而 hwid 目录从未公开 (marble/garnet/flourite 等 5.10+ 树):
  # 桩头提供 gpio-testing-mode.c 用到的两个符号 (get_hw_country_version / CountryCN),
  # 其余引用方通常只 include 不使用符号 → 桩头足够编译通过。
  local hsrc hdir
  while IFS= read -r hsrc; do
    [ -n "$hsrc" ] || continue
    hdir=$(dirname "$hsrc")
    for hp2 in "$hdir/hwid.h" "drivers/misc/hwid.h"; do
      if [ ! -e "$hp2" ]; then
        mkdir -p "$(dirname "$hp2")" 2>/dev/null || true
        printf '/* stub by sukisu-kernel-builder: 厂商未公开 hwid.h */\n#ifndef _SUKI_HWID_STUB_H\n#define _SUKI_HWID_STUB_H\nstatic inline unsigned int get_hw_country_version(void) { return 0; }\nenum { CountryCN = 1 };\n#endif\n' > "$hp2" 2>/dev/null || true
      fi
    done
    info "兼容修复: 为 $(basename "$hsrc") 生成 hwid.h 桩头 (厂商未公开私有头)"
  done < <(grep -rIl --include='*.c' -E '^[[:space:]]*#include[[:space:]]*[<"]hwid\.h[>"]' drivers 2>/dev/null || true)
}

# 小米公开源码树常引用未公开的 vendor 驱动 Kconfig (如 drivers/misc/hwid/Kconfig),
# 导致 olddefconfig 直接报 "can't open file" (run #20/#21 marble)。把指向不存在
# 路径的 source 行注释掉 (Kconfig source 路径相对内核树根)。
# 注意1: 厂商树常写成不带引号的形式, 例如 OnePlus 的 `source block/uxio_first/Kconfig`
#        (还包在 #ifdef OPLUS_FEATURE_xxx 里) —— 必须同时匹配 "path" 与 path 两种写法。
# 注意2 (run #24/#25 教训): 绝不能动带变量的引用, 如 source "arch/$(SRCARCH)/Kconfig"
# —— 字面存在性检查必然失败, 误注释会断开整个 Kconfig 树 (arch/arm64/Kconfig 不被加载,
# CONFIG_ARM64/CONFIG_64BIT 全部丢失, 表现为 atomic64_t 未定义)。同理只处理带 "/"
# 的真实路径, 避免误伤 scripts/kconfig/tests 里的夹具。
fix_missing_kconfig_sources() {
  cd "$KERNEL_DIR"
  local list_file missing_file cnt total
  list_file="$(mktemp)"; missing_file="$(mktemp)"
  grep -rhoE '^[[:space:]]*source[[:space:]]+"?[^"[:space:]]+"?' --include='Kconfig*' . 2>/dev/null \
    | sed -E 's/^[[:space:]]*source[[:space:]]+"?([^"[:space:]]+)"?/\1/' | sort -u > "$list_file" || true
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
        if (match($0, /source[[:space:]]+"?[^"[:space:]]+"?/)) {
          p = substr($0, RSTART, RLENGTH)
          sub(/^source[[:space:]]+/, "", p)
          gsub(/"/, "", p)
          if (p in M) { print "# " $0; next }
        }
        print
      }' "$f" > "$f.dsh.tmp" && mv "$f.dsh.tmp" "$f"
  done < <(grep -rlE '^[[:space:]]*source[[:space:]]+"?[^"[:space:]]+' --include='Kconfig*' . 2>/dev/null)
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
              # 目录存在但缺 Makefile/Kbuild 也视为不可构建 (camellian 的 drivers/mihw
              # 目录被厂商清空但 Makefile 仍 `obj-y += mihw/` → ar 报 built-in.o No such file)。
              if (system("d=\"" dir "/" p "\"; { [ -d \"$d\" ] && [ -f \"$d/Makefile\" ] || [ -f \"$d/Kbuild\" ]; }") != 0) hit = 1
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

# MTK 5.10 树 (yunluo/rubens/xaga/pearl) 的 drivers/gpu/mediatek/ged/src/ged_kpi.c 引用了
# disp_arr.h / mtk_drm_arr.h (DRM FPS 变更回调), 但这两个头在厂商公开树里不存在。
# ged_kpi.c 只在 CONFIG_DRM_MEDIATEK / CONFIG_MTK_HIGH_FRAME_RATE 分支里调用
# drm/ disp_register_fps_chg_callback(...), 这里给缺失头生成 no-op 桩, 避免影响 DRM 正常路径。
fix_vendor_api_compat() {
  cd "$KERNEL_DIR"
  local f n=0
  # 清理旧版本兼容桩：工具链缓存会复用内核树，避免旧 governor 桩与厂商实现重定义。
  # 清理兼容层旧头；对厂商自带 governor 头加一次性保护，避免重复包含导致函数重定义。
  rm -f include/linux/devfreq/governor.h 2>/dev/null || true
  for _gov in $(find -L drivers -type f -path '*/devfreq/governor.h' -print 2>/dev/null); do
    # 该厂商头与 include/linux/devfreq/governor.h 同名但内容不同；UFS 只需兼容结构，禁用其重复实现。
    if grep -q 'devfreq_update_stats' "$_gov"; then
      # 保留厂商实现但改名，避免与内核 governor API 同名重定义。
      sed -i -E 's/\bdevfreq_update_stats\b/suki_vendor_devfreq_update_stats/g' "$_gov" || true
    fi
  done
  # 老 ARM64 头在部分厂商树未间接包含 errno.h；补充 EOPNOTSUPP 的兼容定义。
  if grep -RIl --include='*.h' 'EOPNOTSUPP' arch/arm64/include >/dev/null 2>&1; then
    for _eh in arch/arm64/include/asm/cpuidle.h; do
      if [ -f "$_eh" ] && ! grep -q 'suki-builder: EOPNOTSUPP' "$_eh"; then
        sed -i '1i#ifndef EOPNOTSUPP\n#define EOPNOTSUPP 95\n#endif /* suki-builder: EOPNOTSUPP */' "$_eh" || true
      fi
    done
  fi
  # 老 MTK 相机驱动仍 include linux/wakelock.h；该 Android 私有头在主线树中已移除，提供最小兼容桩。
  if [ ! -f include/linux/wakelock.h ] && grep -RIl --include='*.c' --include='*.h' 'linux/wakelock.h' drivers/misc/mediatek >/dev/null 2>&1; then
    mkdir -p include/linux
    cat > include/linux/wakelock.h <<'EOF'
#ifndef _SUKI_WAKELOCK_COMPAT_H
#define _SUKI_WAKELOCK_COMPAT_H
#include <linux/types.h>
struct wake_lock { int dummy; };
#define WAKE_LOCK_SUSPEND 0
static inline void wake_lock_init(struct wake_lock *l, int t, const char *n) { (void)l; (void)t; (void)n; }
static inline void wake_lock_destroy(struct wake_lock *l) { (void)l; }
static inline void wake_lock(struct wake_lock *l) { (void)l; }
static inline void wake_unlock(struct wake_lock *l) { (void)l; }
static inline int wake_lock_active(struct wake_lock *l) { (void)l; return 0; }
static inline void wake_lock_timeout(struct wake_lock *l, long t) { (void)l; (void)t; }
#endif
EOF
  fi
  # 部分 5.10 厂商 UFS 头直接嵌入 devfreq_simple_ondemand_data, 却未包含其定义。
  # governor 头在老树中提供该结构; 仅在 ufshcd.h 确有字段且缺 include 时补入。
  for f in $(find -L drivers/scsi/ufs -type f -name '*.h' -print 2>/dev/null | while read -r x; do grep -ql 'struct devfreq_simple_ondemand_data' "$x" && printf '%s\n' "$x"; done); do
    if ! grep -q 'struct devfreq_simple_ondemand_data[[:space:]]*{' "$f"; then
      sed -i '1i#ifndef _SUKI_UFS_DEVFREQ_DATA\n#define _SUKI_UFS_DEVFREQ_DATA\nstruct devfreq_simple_ondemand_data { unsigned int upthreshold; unsigned int downdifferential; };\n#endif' "$f"
      n=$((n+1))
    fi
    sed -i '/#include <linux\/devfreq\/governor\.h>/d' "$f" || true
  done
  # proc_compat_ioctl 仅存在于较新的 proc_ops; 老树 struct proc_ops 无此成员时删除指定初始化行。
  # 老 proc_ops 没有 proc_compat_ioctl；某些厂商头会在注释/其它结构中误含同名文本，
  # 不以全文件 grep 判定，直接对旧内核树的指定初始化项做兼容删除。
  local _pkmaj _pkmin
  _pkmaj="${KVER%%.*}"; _pkmin="${KVER#*.}"; _pkmin="${_pkmin%%.*}"
  if { [ -f include/linux/proc_fs.h ] && ! grep -q 'proc_compat_ioctl' include/linux/proc_fs.h; } || [ -z "${_pkmaj:-}" ] || [ "${_pkmaj:-99}" -lt 5 ] || { [ "${_pkmaj:-99}" -eq 5 ] && [ "${_pkmin:-99}" -lt 5 ]; }; then
    for f in $(find -L drivers -type f -name '*.c' -print 2>/dev/null | while read -r x; do grep -qlE '^[[:space:]]*\.proc_compat_ioctl[[:space:]]*=' "$x" && printf '%s\n' "$x"; done); do
      sed -i '/^[[:space:]]*\.proc_compat_ioctl[[:space:]]*=.*/d' "$f" || true
      n=$((n+1))
    done
  fi
  # 部分 MTK CCCI 公开树缺少厂商私有 sec_osal.h；该头在公开代码中仅提供私有 OSAL 声明，
  # 先生成最小桩以继续暴露真实缺失符号，避免在兼容探测阶段直接中止。
  for f in $(find -L drivers -type f \( -name '*.c' -o -name '*.h' \) -print 2>/dev/null | while read -r x; do grep -qE '^[[:space:]]*#include[[:space:]]*[<"](sec_(osal|export)|scp_ipi)\.h[>"]' "$x" && printf '%s\n' "$x"; done); do
    d="$(dirname "$f")"
    for _sec_h in sec_osal.h sec_export.h scp_ipi.h; do
      if [ ! -f "$d/$_sec_h" ]; then
        cat > "$d/$_sec_h" <<EOF
#ifndef _SUKI_${_sec_h//./_}_STUB_H
#define _SUKI_${_sec_h//./_}_STUB_H
/* Vendor-private $_sec_h is absent from the published kernel tree. */
#if defined(_SUKI_sec_osal_h_STUB_H)
#define OSAL_FILE_SEEK_FAIL (-1)
#define OSAL_FILE_GET_POS_FAIL (-1)
#define OSAL_FILE_READ_FAIL (-1)
#endif
#endif
EOF
        n=$((n+1))
      fi
    done
  done
  # MTK charger 的回调在公开树中缺少前置声明；补一个本地原型避免 static/implicit 冲突。
  for _cf in $(find -L drivers/power/supply -type f -name 'mtk_charger.c' -print 2>/dev/null); do
    # 公开树缺少该回调的前置声明；将其定义改为外部链接，避免 clang 将隐式声明视为 extern 后与 static 冲突。
    sed -i '/suki-builder: usbpd prototype/d;/static void usbpd_mi_vdm_received_cb(struct mtk_charger \*pinfo, struct tcp_ny_uvdm uvdm);/d;s/^void usbpd_mi_vdm_received_cb(/static void usbpd_mi_vdm_received_cb(/' "$_cf" || true
    if grep -q 'usbpd_mi_vdm_received_cb' "$_cf" && ! grep -q 'suki-builder: usbpd prototype' "$_cf"; then
      sed -i '/^#include/i /* suki-builder: usbpd prototype */\nstatic void usbpd_mi_vdm_received_cb();' "$_cf" || true
    fi
  done
  # scp_ipi.h 对应的 CCCI SCP 驱动依赖未公开的时钟/通知器私有 API；空桩无法安全模拟。
  # 若源文件存在但其私有头缺失，跳过该可选对象，避免污染内核其它 CCCI 功能。
  # connectivity 适配器依赖已移除/变更的厂商回调，跳过该不完整对象。
  for _mf in $(find -L drivers -type f -name 'Makefile' -print 2>/dev/null); do
    if grep -q 'connectivity_build_in_adapter\.o' "$_mf" 2>/dev/null; then
      sed -i -E 's@^[[:space:]]*(.*connectivity_build_in_adapter\.o.*)$@# suki-builder: unavailable connectivity vendor API; \1@' "$_mf" || true
    fi
  done
  for f in $(find -L drivers -type f -name 'Makefile' -print 2>/dev/null); do
    if grep -qE 'ccci_(fsm_scp|core)\.o' "$f" 2>/dev/null; then
      sed -i -E 's@^[[:space:]]*(.*ccci_(fsm_scp|core)\.o.*)$@# suki-builder: unavailable private SCP API; \1@' "$f" || true
      n=$((n+1))
    fi
    if grep -q 'camera_mfb\.o' "$f" 2>/dev/null; then
      sed -i -E 's@^[[:space:]]*(.*camera_mfb\.o.*)$@# suki-builder: unavailable private MFB map table; \1@' "$f" || true
      n=$((n+1))
    fi
    if grep -qE 'swpm[_-]perf[_-]arm[_-]pmu\.o' "$f" 2>/dev/null; then
      sed -i -E 's@^[[:space:]]*(.*swpm[_-]perf[_-]arm[_-]pmu\.o.*)$@# suki-builder: unavailable vendor PMU ABI; \1@' "$f" || true
      n=$((n+1))
    fi
  done
  [ "$n" -gt 0 ] && info "兼容修复: 补 UFS/proc_ops/MTK 私有头桩并跳过缺失 SCP 对象 ($n 处)"
}

fix_mtk_disp_arr_stub() {
  cd "$KERNEL_DIR"
  local stub f d n=0
  read -r -d '' stub <<'EOF' || true
#ifndef _SUKI_DISP_ARR_STUB_H
#define _SUKI_DISP_ARR_STUB_H
static inline void disp_register_fps_chg_callback(void (*cb)(unsigned int)) { (void)cb; }
static inline void disp_unregister_fps_chg_callback(void (*cb)(unsigned int)) { (void)cb; }
static inline void drm_register_fps_chg_callback(void (*cb)(unsigned int)) { (void)cb; }
static inline void drm_unregister_fps_chg_callback(void (*cb)(unsigned int)) { (void)cb; }
static inline void drm_invoke_fps_chg_callbacks(unsigned int fps) { (void)fps; }
#ifndef LFR_MODE_BOTH_MODE
#define LFR_MODE_BOTH_MODE 0
#endif
#ifndef LFR_TYPE_HSYNC_ONLY
#define LFR_TYPE_HSYNC_ONLY 0
#endif
#endif
EOF
  for f in $(grep -rlE '^[[:space:]]*#include[[:space:]]*[<"]disp_arr\.h[>"]' drivers 2>/dev/null || true); do
    d="$(dirname "$f")"
    printf '%s\n' "$stub" > "$d/disp_arr.h"
    n=$((n+1))
  done
  for f in $(grep -rlE '^[[:space:]]*#include[[:space:]]*[<"]mtk_drm_arr\.h[>"]' drivers 2>/dev/null || true); do
    d="$(dirname "$f")"
    printf '%s\n' "$stub" > "$d/mtk_drm_arr.h"
    n=$((n+1))
  done
  [ "$n" -gt 0 ] && ok "兼容修复: 为缺失的 disp_arr.h / mtk_drm_arr.h 生成桩头 (MTK GED FPS 回调, $n 处)"
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
# drivers/kernelsu 是 setup.sh/手动集成建的**符号链接** (指向 KernelSU/kernel)。
# KSU 自己的 Kbuild 用 -I$(KSU_KERNEL_DIR)/include 找 klog.h / uapi/app_profile.h,
# 个别内核版本 (实测 6.12 android16) 下 $(src) 推导不到真实目录 → 头文件找不到。
# 这里补上指向真实目录的绝对 include 路径 (幂等, 只加一次)。
ksu_include_fixup() {
  local real="$KERNEL_DIR/KernelSU/kernel"
  local kfile=""
  [ -d "$real" ] || return 0
  # 直接写真实目录 (drivers/kernelsu 是符号链接; MSYS/Windows 上写链接路径可能静默失效)
  if [ -f "$real/Kbuild" ]; then
    kfile="$real/Kbuild"
  elif [ -f "$real/Makefile" ]; then
    kfile="$real/Makefile"
  fi
  [ -n "$kfile" ] || return 0
  grep -q 'suki-builder: ksu include dirs' "$kfile" && return 0
  {
    printf '\n# suki-builder: ksu include dirs (drivers/kernelsu 是符号链接, $(src) 推导不到 include/ 时兜底)\n'
    printf 'ccflags-y += -I%s -I%s/include -I%s/include/uapi\n' "$real" "$real" "$real"
  } >>"$kfile"
  ok "兼容修复: SukiSU 的 Kbuild/Makefile 补绝对 include 路径 (klog.h / uapi/app_profile.h)"
}

integrate_sukisu() {
  (
    cd "$KERNEL_DIR"
    info "集成 SukiSU-Ultra (分支: $KSU_BRANCH) ..."
    if [ "$KSU_BRANCH" = main ]; then
      # main: 先尝试官方 setup.sh (zako 私有源, runner 可达但可能不稳), 失败回退 GitHub 手动集成
      info "  尝试官方 setup.sh: curl .../setup.sh | bash -s $KSU_BRANCH"
      if curl -LSs "$SUKISU_SETUP_URL" | bash -s "$KSU_BRANCH" >>"$LOG_FILE" 2>&1; then
        ok "官方 setup.sh 集成成功"
        ksu_include_fixup
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
    ksu_include_fixup
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
    # -fno-builtin-memcmp/-bcmp: 部分厂商老树删掉了 lib/string.c 的 bcmp, 而 clang 会把
    # memcmp(a,b,n)==0 优化成 bcmp 调用 (begonia 4.14.94: undefined reference to `bcmp')
    kc="-fno-builtin-sprintf -fno-builtin-stpcpy -fno-builtin-memcmp -fno-builtin-bcmp"
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
    kc="$kc -Wno-error -Wno-error=int-conversion -Wno-error=implicit-function-declaration"
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
    # GKI(main) 树同样关 BTF: android1x-5.15/6.6 的 gki_defconfig 默认开 CONFIG_DEBUG_INFO_BTF,
    # kbuild 会先构建 tools/bpf/resolve_btfids + libbpf, 新版 clang 下 libbpf 的 const 丢弃告警被
    # -Werror 升级成错误 (run #9 批跑: gki-a15 6.6 "assigning to 'char *' from 'const char *'" 失败)。
    # KSU 不需要 BTF, 直接关闭; LKM 模式只产出 kernelsu.ko, 不影响 GKI 模块加载 (vermagic 才是校验项)。
    $SC -d DEBUG_INFO_BTF >/dev/null 2>&1 || true
    $SC -d DEBUG_INFO_BTF_MODULES >/dev/null 2>&1 || true
    # GKI 的 gki_defconfig 默认开 CONFIG_LTO_CLANG_FULL (ThinLTO/Full LTO): vmlinux.o 的 LTO
    # 链接在 2 核 runner 上要多花 30~60 分钟, 且实测 gki-a13 在 "LTO vmlinux.o" 阶段被
    # runner 回收(SIGTERM 143)。KSU 不依赖 LTO → 关闭, 显著缩短 GKI 构建时间。
    $SC -d LTO_CLANG >/dev/null 2>&1 || true
    $SC -d LTO_CLANG_FULL >/dev/null 2>&1 || true
    $SC -d LTO_CLANG_THIN >/dev/null 2>&1 || true
    $SC -e LTO_NONE >/dev/null 2>&1 || true
    $SC -d DEBUG_INFO >/dev/null 2>&1 || true
    $SC -d DEBUG_INFO_DWARF4 >/dev/null 2>&1 || true
  fi
  # gold-s-oss 已知 crypto/ecdsasignature.asn1.h 规则损坏;按设备 ID 兜底关闭 ECDSA。
  # 其它树仅在 Makefile 明确没有 %.asn1.h 规则时关闭，避免误伤正常内核。
  if [ "$SEL_DEVICE_ID" = gold ] || { [ -f crypto/Makefile ] && ! grep -qE 'asn1_compiler|%\.asn1\.h' crypto/Makefile; }; then
    $SC -d CRYPTO_ECDSA >/dev/null 2>&1 || true
    info "兼容设置: crypto/Makefile 的 ECDSA ASN.1 头规则不可用, 关闭 CONFIG_CRYPTO_ECDSA"
  fi
  # 厂商 defconfig 常打开 CONFIG_HEADERS_INSTALL=y: 构建期会跑 usr/include 的 hdrtest
  # (厂商自加的头文件测试), 用新 glibc 会报 "field has incomplete type 'struct timespec'"
  # 直接中断整次编译 (op9 5.4 OnePlus SM8350 实测)。我们只需要 Image, 关掉头文件导出。
  $SC -d HEADERS_INSTALL >/dev/null 2>&1 || true
  # 非 GKI 的老厂商树 (kver<5.10) 额外收尾:
  #  * DEBUG_INFO: 老树默认开 DWARF 调试信息, binutils 2.27 遇到 clang 12 生成的 DWARF5
  #    (.file 0/.loc 0) 会报 "file number less than one" / "junk at end of line"
  #    (munch 4.19.157 / camellian / pissarro 4.14.186 实测); 不需要调试符号, 关掉还省很多时间。
  #  * MODVERSIONS: 只产出 Image 从不打包 module, 关掉可避免 4.14 树 vmlinux 链接阶段
  #    "ld.lld: error: cannot find linker script .tmp_symversions" (cannon v2 实测)。
  if [ "$SEL_GKI" != 1 ]; then
    local _kmaj _kmin
    _kmaj="$(echo "${KVER:-0}" | cut -d. -f1)"
    _kmin="$(echo "${KVER:-0}" | cut -d. -f2)"
    if [ -n "$_kmaj" ] && { [ "$_kmaj" -lt 5 ] || { [ "$_kmaj" -eq 5 ] && [ "${_kmin:-0}" -lt 10 ]; }; }; then
      $SC -d DEBUG_INFO >/dev/null 2>&1 || true
      $SC -d DEBUG_INFO_DWARF4 >/dev/null 2>&1 || true
      $SC -d MODVERSIONS >/dev/null 2>&1 || true
      info "兼容设置: 老内核关闭 DEBUG_INFO/DWARF4 (binutils 2.27 与 DWARF5 不兼容) 与 MODVERSIONS"
    fi
  fi
  if ! "${MK[@]}" olddefconfig >>"$LOG_FILE" 2>&1; then
    die_log "$LOG_FILE" "olddefconfig 失败"
  fi
  # olddefconfig 可能因 select/default 重新打开损坏的 ECDSA ASN.1 配置，最终配置后再次强制关闭。
  if [ "$SEL_DEVICE_ID" = gold ] || { [ -f "$KERNEL_DIR/crypto/Makefile" ] && ! grep -qE 'asn1_compiler|%\.asn1\.h' "$KERNEL_DIR/crypto/Makefile"; }; then
    $SC -d CRYPTO_ECDSA >/dev/null 2>&1 || true
    info "最终配置确认: 关闭损坏的 CONFIG_CRYPTO_ECDSA ASN.1 规则"
    if [ -f "$KERNEL_DIR/crypto/Makefile" ]; then
      sed -i -E 's@^([[:space:]]*obj-[^=]*\$\(CONFIG_CRYPTO_ECDSA\)[[:space:]]*\+=[[:space:]]+.*ecdsa\.o.*)$@# suki-builder: disabled broken ECDSA ASN1 rule\n# \1@' "$KERNEL_DIR/crypto/Makefile" || true
    fi
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
  fix_missing_makefile_objs || warn "缺失 Makefile 条目修复出现非致命错误, 继续构建"
  fix_vendor_api_compat || warn "vendor API 兼容修复出现非致命错误, 继续构建"
  fix_mtk_disp_arr_stub || warn "MTK 显示桩修复出现非致命错误, 继续构建"
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
