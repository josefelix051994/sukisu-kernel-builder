$ErrorActionPreference = 'Stop'
# 合并 mi_all.csv 到 devices.conf:
#  - 按分支名去重(devices.conf 已有的分支跳过)
#  - 新条目插到小米区块末尾(OnePlus 区块之前)
#  - 显示名 = codename; 版本标签 = "Android X · Linux kver"
$root = 'E:\文档\deepseek-harness\default-workspace\sukisu-kernel-builder'
$csv = Import-Csv "$env:TEMP\mi_all.csv" -Encoding UTF8
$confPath = Join-Path $root 'devices.conf'

$lines = [System.IO.File]::ReadAllLines($confPath)
$existingBranch = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($ln in $lines) {
  if ($ln -match '^\s*#' -or $ln.Trim() -eq '') { continue }
  $parts = $ln.Split('|')
  if ($parts.Count -ge 5) { [void]$existingBranch.Add($parts[4].Trim()) }
}

$newLines = New-Object System.Collections.Generic.List[string]
$skipped = 0
foreach ($row in $csv) {
  $branch = $row.branch.Trim()
  if ($existingBranch.Contains($branch)) { $skipped++; continue }
  $defconfig = $row.defconfig.Trim()
  if ($defconfig -like '*.fragment' -or $defconfig -in @('defconfig', 'gki_defconfig')) { $skipped++; continue }  # fragment/通用配置不可直接编译
  $id = $row.codename.Trim()
  $kver = $row.kver.Trim()
  $android = $row.android.Trim()
  $repo = 'https://github.com/MiCode/' + $row.repo.Trim()
  $label = "Android $android · Linux $kver"
  $newLines.Add("$id|$label|$id|$repo|$branch|$kver|$android|0|$defconfig")
}

# 找到 OnePlus 区块前的空行位置插入
$insertAt = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^# ---------- 一加') { $insertAt = $i - 2; break }
}
if ($insertAt -lt 0) { throw '未找到一加区块' }

$sorted = $newLines | Sort-Object { ($_ -split '\|')[0] }
$out = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -le $insertAt; $i++) { $out.Add($lines[$i]) }
foreach ($l in $sorted) { $out.Add($l) }
for ($i = $insertAt + 1; $i -lt $lines.Count; $i++) { $out.Add($lines[$i]) }

[System.IO.File]::WriteAllLines($confPath, $out.ToArray(), (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("新增 $($sorted.Count) 条, 跳过已存在 $skipped 条, 新文件共 $($out.Count) 行")
