#!/usr/bin/env bash
# ============================================================================
#  自动生成脚本 (tools/gen_build_scripts.sh), 请勿手改。
#  设备   : pissarro (pissarro)
#  版本   : 第 2 个 — Android 11 · Linux 4.14.186
#  仓库   : https://github.com/MiCode/Xiaomi_Kernel_OpenSource @ pissarro-r-oss
#  内核   : Linux 4.14.186 · Android 11 · GKI=0
#  defconfig: pissarro_user_defconfig
#
#  用法:
#    bash builds/pissarro/v2.sh                # 正式开始编译
#    bash builds/pissarro/v2.sh --dry-run      # 演练(不下载不编译)
#    bash builds/pissarro/v2.sh --kpm          # 追加任意 build.sh 参数
# ============================================================================
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$DIR/../../build.sh" --device "pissarro" --version "2" --yes "$@"
