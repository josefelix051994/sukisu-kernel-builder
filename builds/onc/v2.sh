#!/usr/bin/env bash
# ============================================================================
#  自动生成脚本 (tools/gen_build_scripts.sh), 请勿手改。
#  设备   : onc (onc)
#  版本   : 第 2 个 — Android 9 · Linux 4.9.112
#  仓库   : https://github.com/MiCode/Xiaomi_Kernel_OpenSource @ onc-p-oss
#  内核   : Linux 4.9.112 · Android 9 · GKI=0
#  defconfig: onc-perf_defconfig
#
#  用法:
#    bash builds/onc/v2.sh                # 正式开始编译
#    bash builds/onc/v2.sh --dry-run      # 演练(不下载不编译)
#    bash builds/onc/v2.sh --kpm          # 追加任意 build.sh 参数
# ============================================================================
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$DIR/../../build.sh" --device "onc" --version "2" --yes "$@"
