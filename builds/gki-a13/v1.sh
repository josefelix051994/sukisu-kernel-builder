#!/usr/bin/env bash
# ============================================================================
#  自动生成脚本 (tools/gen_build_scripts.sh), 请勿手改。
#  设备   : gki-a13 (通用 GKI · Android 13)
#  版本   : 第 1 个 — Android 13 · Linux 5.15 (KMI android13-5.15)
#  仓库   : https://github.com/aosp-mirror/kernel_common @ android13-5.15
#  内核   : Linux 5.15 · Android 13 · GKI=1
#  defconfig: gki_defconfig
#
#  用法:
#    bash builds/gki-a13/v1.sh                # 正式开始编译
#    bash builds/gki-a13/v1.sh --dry-run      # 演练(不下载不编译)
#    bash builds/gki-a13/v1.sh --kpm          # 追加任意 build.sh 参数
# ============================================================================
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$DIR/../../build.sh" --device "gki-a13" --version "1" --yes "$@"
