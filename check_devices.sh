#!/usr/bin/env bash
set -e
cd "$(dirname "$0")" || exit 1
n=0; bad=0
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  case "$line" in ""|\#*) continue;; esac
  n=$((n+1))
  IFS='|' read -r -a f <<< "$line"
  if [ "${#f[@]}" -ne 9 ]; then echo "字段数错误(${#f[@]}): $line"; bad=1; fi
  if [ -z "${f[0]}" ] || [ -z "${f[2]}" ] || [ -z "${f[3]}" ] || [ -z "${f[4]}" ]; then
    echo "关键字段为空: $line"; bad=1
  fi
  case "${f[7]}" in 0|1) ;; *) echo "GKI 标志非法: ${f[7]} 于 $line"; bad=1;; esac
  # 分支名不能以 .git 结尾、不能含空格
  case "${f[4]}" in *.git|*" "*) echo "分支名可疑: ${f[4]}"; bad=1;; esac
done < devices.conf
echo "共 $n 条记录"
if [ $bad -eq 0 ]; then echo "格式检查: 全部通过"; else echo "格式检查: 存在问题"; exit 1; fi
