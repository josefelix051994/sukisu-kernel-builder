#!/usr/bin/env bash
# ============================================================================
#  自动生成脚本 (tools/gen_build_scripts.sh), 请勿手改。
#  设备   : op8t (OnePlus 8T)
#  版本   : 第 4 个 — OOS 14 · Linux 4.19
#  仓库   : https://github.com/OnePlusOSS/android_kernel_oneplus_sm8250 @ oneplus/sm8250_u_14.0.0_op8t
#  内核   : Linux 4.19 · Android 14 · GKI=0
#  defconfig: vendor/kona-perf_defconfig
#
#  用法:
#    bash builds/op8t/v4.sh                # 正式开始编译
#    bash builds/op8t/v4.sh --dry-run      # 演练(不下载不编译)
#    bash builds/op8t/v4.sh --kpm          # 追加任意 build.sh 参数
# ============================================================================
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$DIR/../../build.sh" --device "op8t" --version "4" --yes "$@"
