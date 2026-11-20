$ErrorActionPreference = 'Stop'
$tok = $env:GH_TOKEN
if ([string]::IsNullOrEmpty($tok)) { Write-Error '请先设置环境变量 GH_TOKEN'; exit 1 }
$hdr = @{ Authorization = "Bearer $tok"; 'User-Agent' = 'dsh-builder' }
$out = "$env:TEMP\mi_all.csv"
Remove-Item $out -ErrorAction SilentlyContinue

function Invoke-GitHub {
  param([string]$Url)
  for ($try = 0; $try -lt 5; $try++) {
    try {
      $r = Invoke-RestMethod -Uri $Url -Headers $hdr -TimeoutSec 30
      # PS 5.1 有时把 JSON 数组包成单个对象(成员枚举成串), 强制逐项展开
      return @($r | ForEach-Object { $_ })
    } catch {
      $code = $_.Exception.Response.StatusCode.value__
      if ($code -eq 403 -or $code -eq 429) {
        Start-Sleep -Seconds ([Math]::Min(60, 5 + 8 * $try))
        continue
      }
      throw
    }
  }
  throw "API 重试耗尽: $Url"
}

# 1. 枚举 MiCode 组织全部仓库
$repos = @()
$page = 1
do {
  $r = Invoke-GitHub "https://api.github.com/orgs/MiCode/repos?per_page=100&page=$page"
  $repos += $r.name
  $page++
} while ($r.Count -eq 100)
"MiCode 仓库总数: $($repos.Count)"
$krepos = $repos | Where-Object { $_ -match 'kernel|sm\d{4}|mt\d{4}' }
"内核相关仓库: $($krepos -join ', ')"

# 版本字母映射: letter -> android 显示, kver 提示
$letterMap = @{
  'a' = @('8.1', '4.9')
  'p' = @('9', '4.9/4.14')
  'q' = @('10', '4.14/4.19')
  'r' = @('11', '4.19')
  's' = @('12', '5.4')
  't' = @('13', '5.4/5.10')
  'u' = @('14', '5.10/5.15/6.1')
  'v' = @('15', '6.1/6.6')
  'w' = @('16', '6.6/6.12')
  'x' = @('17', '6.12/6.18')
}

$rows = @()
foreach ($repo in $krepos) {
  $page = 1
  do {
    $b = Invoke-GitHub "https://api.github.com/repos/MiCode/$repo/branches?per_page=100&page=$page"
    foreach ($br in $b) {
      $name = $br.name
      if ($name -notmatch '^([a-zA-Z0-9_]+)-([a-z])([0-9]?)-(oss)$') { continue }
      $codename = $Matches[1]
      $letter = $Matches[2]
      if (-not $letterMap.ContainsKey($letter)) { continue }
      $android = $letterMap[$letter][0]
      $kverHint = $letterMap[$letter][1]
      # defconfig 探测
      $defconfig = $null
      $vendorFiles = $null
      try { $vendorFiles = @(Invoke-GitHub "https://api.github.com/repos/MiCode/$repo/contents/arch/arm64/configs/vendor?ref=$name") } catch { $vendorFiles = @() }
      $names = @()
      $inVendor = $false
      if ($vendorFiles.Count -gt 0) {
        $names = @($vendorFiles | Where-Object { $_.type -eq 'file' } | ForEach-Object { [string]$_.name })
        $inVendor = $true
      } else {
        try {
          $rootFiles = @(Invoke-GitHub "https://api.github.com/repos/MiCode/$repo/contents/arch/arm64/configs?ref=$name")
        } catch { $rootFiles = @() }
        if ($rootFiles.Count -gt 0) {
          $names = @($rootFiles | Where-Object { $_.type -eq 'file' } | ForEach-Object { [string]$_.name })
        }
      }
      if ($names.Count -gt 0) {
        foreach ($cand in @("${codename}_user_defconfig", "${codename}-user_defconfig", "${codename}_perf_defconfig", "${codename}-perf_defconfig", "${codename}_QGKI.config", "${codename}-QGKI.config", "${codename}_consolidate.config", "${codename}_GKI.config", "${codename}_defconfig")) {
          if ($names -contains $cand) { $defconfig = $cand; break }
        }
        if (-not $defconfig) {
          $defconfig = $names | Where-Object { $_ -like "${codename}*" } | Select-Object -First 1
        }
        if ($defconfig -and $inVendor) { $defconfig = "vendor/$defconfig" }
      }
      if (-not $defconfig) { continue }  # 无 defconfig 的分支跳过(如 marble/cupid 公开树不含 config)
      # 精确 kver: 读顶层 Makefile
      $kver = $kverHint
      try {
        $mk = (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/MiCode/$repo/$name/Makefile" -Headers $hdr -TimeoutSec 30 -UseBasicParsing).Content -split "`n"
        $V = ($mk | Where-Object { $_ -match '^VERSION\s*=' } | Select-Object -First 1) -replace '.*=\s*', ''
        $P = ($mk | Where-Object { $_ -match '^PATCHLEVEL\s*=' } | Select-Object -First 1) -replace '.*=\s*', ''
        $S = ($mk | Where-Object { $_ -match '^SUBLEVEL\s*=' } | Select-Object -First 1) -replace '.*=\s*', ''
        if ($V -and $P -match '^\d+$') { $kver = "$V.$P" + ($(if ($S -match '^\d+$') { ".$S" } else { '' })) }
      } catch { }
      $rows += [PSCustomObject]@{ repo = [string]$repo; branch = [string]$name; codename = [string]$codename; letter = [string]$letter; android = [string]$android; kver = [string]$kver; defconfig = [string]$defconfig }
    }
    $page++
  } while ($b.Count -eq 100)
}
$rows | Sort-Object codename, branch | Export-Csv -Path $out -NoTypeInformation -Encoding UTF8
"完成: 共 $($rows.Count) 条有效设备记录 -> $out"