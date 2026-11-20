#!/usr/bin/env bash
# ============================================================================
#  自动生成脚本 (tools/gen_build_scripts.sh), 请勿手改。
#  设备   : op7pro (OnePlus 7 Pro)
#  版本   : 第 3 个 — OOS 12.1 · Linux 4.14
#  仓库   : https://github.com/OnePlusOSS/android_kernel_oneplus_sm8150 @ oneplus/sm8150_s_12.1_op7pro
#  内核   : Linux 4.14 · Android 12 · GKI=0
#  defconfig: vendor/sm8150-perf_defconfig
#
#  用法:
#    bash builds/op7pro/v3.sh                # 正式开始编译
#    bash builds/op7pro/v3.sh --dry-run      # 演练(不下载不编译)
#    bash builds/op7pro/v3.sh --kpm          # 追加任意 build.sh 参数
# ============================================================================
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$DIR/../../build.sh" --device "op7pro" --version "3" --yes "$@"
