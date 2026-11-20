#!/usr/bin/env bash
# ============================================================================
#  自动生成脚本 (tools/gen_build_scripts.sh), 请勿手改。
#  设备   : spring (spring)
#  版本   : 第 1 个 — Android 15 · Linux 6.1.93
#  仓库   : https://github.com/MiCode/Xiaomi_Kernel_OpenSource @ spring-v-oss
#  内核   : Linux 6.1.93 · Android 15 · GKI=0
#  defconfig: vendor/spring_consolidate.config
#
#  用法:
#    bash builds/spring/v1.sh                # 正式开始编译
#    bash builds/spring/v1.sh --dry-run      # 演练(不下载不编译)
#    bash builds/spring/v1.sh --kpm          # 追加任意 build.sh 参数
# ============================================================================
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$DIR/../../build.sh" --device "spring" --version "1" --yes "$@"
