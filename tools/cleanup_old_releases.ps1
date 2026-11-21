# 清理旧版「每个产物一个 Release」的 build-* 发布, 只保留统一的「内核合集」。
# 用法:  $env:GH_TOKEN='ghp_xxx'; powershell -File tools/cleanup_old_releases.ps1 [-Apply]
param([switch]$Apply)
$ErrorActionPreference = 'Stop'
$tok = $env:GH_TOKEN
if (-not $tok) { Write-Error '请先设置环境变量 GH_TOKEN'; exit 1 }
$hdr = @{ Authorization = "Bearer $tok"; 'User-Agent' = 'sukisu-kernel-builder'; Accept = 'application/vnd.github+json' }
$repo = 'xingyiqaq/sukisu-kernel-builder'
$aggTag = '内核合集'

$rels = @()
$page = 1
while ($true) {
  $chunk = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases?per_page=100&page=$page" -Headers $hdr
  if (-not $chunk -or $chunk.Count -eq 0) { break }
  $rels += $chunk
  if ($chunk.Count -lt 100) { break }
  $page++
}
$agg = $rels | Where-Object { $_.tag_name -eq $aggTag } | Select-Object -First 1
if (-not $agg) { Write-Error "未找到统一 Release「$aggTag」, 请先跑一次 publish=true 的编译"; exit 1 }
$aggAssets = @($agg.assets | ForEach-Object { $_.name })
Write-Host "内核合集现有资产: $($aggAssets.Count)"
# 统一合集里的资产名形如 <品牌>_<机型>_<代码>_<kver>.<ext>(品牌/机型本身可能含下划线),
# 因此用"以 _<代码>_<kver> 结尾"的后缀匹配, 而不是猜分段。
$aggBases = @($aggAssets | ForEach-Object { $_ -replace '\.(zip|ko)$', '' })

$old = $rels | Where-Object { $_.tag_name -like 'build-*' }
Write-Host "旧 Release 数量: $($old.Count)"
$deleted = 0
$kept = 0
foreach ($r in $old) {
  $parts = $r.tag_name -split '_'
  if ($parts.Count -lt 4) { $kept++; continue }
  $kver = $parts[$parts.Count - 3]
  $code = $parts[$parts.Count - 4]
  $suffix = "_${code}_${kver}"
  $has = $false
  foreach ($b in $aggBases) {
    if ($b -eq "${code}_${kver}" -or $b.EndsWith($suffix)) { $has = $true; break }
  }
  if ($has) {
    if ($Apply) {
      try {
        Invoke-RestMethod -Method Delete -Uri "https://api.github.com/repos/$repo/releases/$($r.id)" -Headers $hdr | Out-Null
        Write-Host "已删除 $($r.tag_name)"
        $deleted++
      } catch {
        Write-Host "删除失败 $($r.tag_name): $($_.Exception.Message)"
      }
    } else {
      Write-Host "[预览] 将删除 $($r.tag_name)"
      $deleted++
    }
  } else {
    Write-Host "[保留] $($r.tag_name) (内核合集里还没有 $code / $kver)"
    $kept++
  }
}
Write-Host '=' * 50
Write-Host "处理结果: 删除(或预览)=$deleted, 保留=$kept"
if (-not $Apply) { Write-Host '这是预览模式; 确认无误后加 -Apply 真正删除。' }