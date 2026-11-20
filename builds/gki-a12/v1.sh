#!/usr/bin/env bash
# ============================================================================
#  自动生成脚本 (tools/gen_build_scripts.sh), 请勿手改。
#  设备   : gki-a12 (通用 GKI · Android 12)
#  版本   : 第 1 个 — Android 12 · Linux 5.10 (KMI android12-5.10)
#  仓库   : https://github.com/aosp-mirror/kernel_common @ android12-5.10
#  内核   : Linux 5.10 · Android 12 · GKI=1
#  defconfig: gki_defconfig
#
#  用法:
#    bash builds/gki-a12/v1.sh                # 正式开始编译
#    bash builds/gki-a12/v1.sh --dry-run      # 演练(不下载不编译)
#    bash builds/gki-a12/v1.sh --kpm          # 追加任意 build.sh 参数
# ============================================================================
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$DIR/../../build.sh" --device "gki-a12" --version "1" --yes "$@"
