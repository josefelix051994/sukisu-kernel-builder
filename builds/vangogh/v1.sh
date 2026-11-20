#!/usr/bin/env bash
# ============================================================================
#  自动生成脚本 (tools/gen_build_scripts.sh), 请勿手改。
#  设备   : vangogh (vangogh)
#  版本   : 第 1 个 — Android 10 · Linux 4.19.81
#  仓库   : https://github.com/MiCode/Xiaomi_Kernel_OpenSource @ vangogh-q-oss
#  内核   : Linux 4.19.81 · Android 10 · GKI=0
#  defconfig: vendor/vangogh_user_defconfig
#
#  用法:
#    bash builds/vangogh/v1.sh                # 正式开始编译
#    bash builds/vangogh/v1.sh --dry-run      # 演练(不下载不编译)
#    bash builds/vangogh/v1.sh --kpm          # 追加任意 build.sh 参数
# ============================================================================
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$DIR/../../build.sh" --device "vangogh" --version "1" --yes "$@"
