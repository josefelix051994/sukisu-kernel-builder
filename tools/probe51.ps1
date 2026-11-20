$ErrorActionPreference = 'Stop'
$tok = $env:GH_TOKEN
if ([string]::IsNullOrEmpty($tok)) { Write-Error '请先设置环境变量 GH_TOKEN'; exit 1 }
$hdr = @{ Authorization = "Bearer $tok"; 'User-Agent' = 'dsh-builder' }
$repo = 'Xiaomi_Kernel_OpenSource'
$name = 'alioth-r-oss'
$codename = 'alioth'
$vendorFiles = @(Invoke-RestMethod -Uri "https://api.github.com/repos/MiCode/$repo/contents/arch/arm64/configs/vendor?ref=$name" -Headers $hdr)
Write-Output ("vendorFiles type=" + $vendorFiles.GetType().Name + " count=" + $vendorFiles.Count)
$names = @($vendorFiles | Where-Object { $_.type -eq 'file' } | ForEach-Object { [string]$_.name })
Write-Output ("names count=" + $names.Count + " first=[" + $names[0] + "]")
$cand = "${codename}_user_defconfig"
Write-Output ("cand=[" + $cand + "] contains=" + ($names -contains $cand))
$defconfig = $null
foreach ($c in @("${codename}_user_defconfig", "${codename}-user_defconfig", "${codename}_defconfig")) {
  if ($names -contains $c) { $defconfig = $c; break }
}
Write-Output ("after loop: [" + $defconfig + "]")
if (-not $defconfig) {
  $defconfig = $names | Where-Object { $_ -like "${codename}*" } | Select-Object -First 1
}
Write-Output ("after fallback: [" + $defconfig + "]")