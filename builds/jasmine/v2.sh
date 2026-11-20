#!/usr/bin/env bash
# ============================================================================
#  自动生成脚本 (tools/gen_build_scripts.sh), 请勿手改。
#  设备   : jasmine (jasmine)
#  版本   : 第 2 个 — Android 9 · Linux 4.4.153
#  仓库   : https://github.com/MiCode/Xiaomi_Kernel_OpenSource @ jasmine-p-oss
#  内核   : Linux 4.4.153 · Android 9 · GKI=0
#  defconfig: jasmine-perf_defconfig
#
#  用法:
#    bash builds/jasmine/v2.sh                # 正式开始编译
#    bash builds/jasmine/v2.sh --dry-run      # 演练(不下载不编译)
#    bash builds/jasmine/v2.sh --kpm          # 追加任意 build.sh 参数
# ============================================================================
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$DIR/../../build.sh" --device "jasmine" --version "2" --yes "$@"
