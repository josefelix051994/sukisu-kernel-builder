#!/usr/bin/env bash
# ============================================================================
#  自动生成脚本 (tools/gen_build_scripts.sh), 请勿手改。
#  设备   : marble (marble)
#  版本   : 第 1 个 — Android 12 · Linux 5.10.117
#  仓库   : https://github.com/MiCode/Xiaomi_Kernel_OpenSource @ marble-s-oss
#  内核   : Linux 5.10.117 · Android 12 · GKI=0
#  defconfig: vendor/marble_consolidate.config
#
#  用法:
#    bash builds/marble/v1.sh                # 正式开始编译
#    bash builds/marble/v1.sh --dry-run      # 演练(不下载不编译)
#    bash builds/marble/v1.sh --kpm          # 追加任意 build.sh 参数
# ============================================================================
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$DIR/../../build.sh" --device "marble" --version "1" --yes "$@"
