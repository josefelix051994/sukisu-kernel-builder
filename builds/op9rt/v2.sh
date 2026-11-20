#!/usr/bin/env bash
# ============================================================================
#  自动生成脚本 (tools/gen_build_scripts.sh), 请勿手改。
#  设备   : op9rt (OnePlus 9RT)
#  版本   : 第 2 个 — OOS 13.1 · Linux 5.15
#  仓库   : https://github.com/OnePlusOSS/android_kernel_oneplus_sm8350 @ oneplus/sm8350_t_13.1.0_oneplus9rt
#  内核   : Linux 5.15 · Android 13 · GKI=0
#  defconfig: vendor/lahaina_QGKI.config
#
#  用法:
#    bash builds/op9rt/v2.sh                # 正式开始编译
#    bash builds/op9rt/v2.sh --dry-run      # 演练(不下载不编译)
#    bash builds/op9rt/v2.sh --kpm          # 追加任意 build.sh 参数
# ============================================================================
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$DIR/../../build.sh" --device "op9rt" --version "2" --yes "$@"
