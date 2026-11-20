#!/usr/bin/env bash
# ============================================================================
#  自动生成脚本 (tools/gen_build_scripts.sh), 请勿手改。
#  设备   : laurus (laurus)
#  版本   : 第 2 个 — Android 9 · Linux 4.14.98
#  仓库   : https://github.com/MiCode/Xiaomi_Kernel_OpenSource @ laurus-p-oss
#  内核   : Linux 4.14.98 · Android 9 · GKI=0
#  defconfig: vendor/laurus-perf_defconfig
#
#  用法:
#    bash builds/laurus/v2.sh                # 正式开始编译
#    bash builds/laurus/v2.sh --dry-run      # 演练(不下载不编译)
#    bash builds/laurus/v2.sh --kpm          # 追加任意 build.sh 参数
# ============================================================================
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$DIR/../../build.sh" --device "laurus" --version "2" --yes "$@"
