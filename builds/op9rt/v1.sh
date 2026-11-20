#!/usr/bin/env bash
# ============================================================================
#  自动生成脚本 (tools/gen_build_scripts.sh), 请勿手改。
#  设备   : op9rt (OnePlus 9RT)
#  版本   : 第 1 个 — OOS 11 · Linux 5.4
#  仓库   : https://github.com/OnePlusOSS/android_kernel_oneplus_sm8350 @ oneplus/SM8350_R_11.0_9RT
#  内核   : Linux 5.4 · Android 11 · GKI=0
#  defconfig: vendor/lahaina_QGKI.config
#
#  用法:
#    bash builds/op9rt/v1.sh                # 正式开始编译
#    bash builds/op9rt/v1.sh --dry-run      # 演练(不下载不编译)
#    bash builds/op9rt/v1.sh --kpm          # 追加任意 build.sh 参数
# ============================================================================
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$DIR/../../build.sh" --device "op9rt" --version "1" --yes "$@"
