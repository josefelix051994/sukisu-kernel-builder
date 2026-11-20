#!/usr/bin/env bash
# ============================================================================
#  自动生成脚本 (tools/gen_build_scripts.sh), 请勿手改。
#  设备   : gki-a15 (通用 GKI · Android 15)
#  版本   : 第 1 个 — Android 15 · Linux 6.6 (KMI android15-6.6)
#  仓库   : https://github.com/aosp-mirror/kernel_common @ android15-6.6
#  内核   : Linux 6.6 · Android 15 · GKI=1
#  defconfig: gki_defconfig
#
#  用法:
#    bash builds/gki-a15/v1.sh                # 正式开始编译
#    bash builds/gki-a15/v1.sh --dry-run      # 演练(不下载不编译)
#    bash builds/gki-a15/v1.sh --kpm          # 追加任意 build.sh 参数
# ============================================================================
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$DIR/../../build.sh" --device "gki-a15" --version "1" --yes "$@"
