param([int]$RunId = 44878048168, [string]$OutDir = "logs\fail12")
$ErrorActionPreference = 'Continue'
$tok = $env:GH_TOKEN
if (-not $tok) { Write-Error '请先设置环境变量 GH_TOKEN'; exit 1 }
$hdr = @{ Authorization = "Bearer $tok"; 'User-Agent' = 'dsh-builder'; Accept = 'application/vnd.github+json' }
$repo = 'xingyiqaq/sukisu-kernel-builder'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# 1) 鏀堕泦 job
$jobs = @()
for ($p = 1; $p -le 5; $p++) {
  $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/actions/runs/$RunId/jobs?per_page=100&page=$p" -Headers $hdr
  if (-not $r.jobs) { break }
  $jobs += $r.jobs
  if ($r.jobs.Count -lt 100) { break }
}
$fail = $jobs | Where-Object { $_.conclusion -eq 'failure' }
"run $RunId  鎬?job=$($jobs.Count)  澶辫触=$($fail.Count)  鎴愬姛=$(($jobs | Where-Object { $_.conclusion -eq 'success' }).Count)  鍏跺畠=$(($jobs | Where-Object { $_.conclusion -and $_.conclusion -notin @('success','failure') }).Count)" | Tee-Object -FilePath (Join-Path $OutDir 'summary.txt')

# 2) 閫愪釜涓嬭浇宸插畬鎴?job 鐨勫畬鏁存棩蹇楀苟鎻愬彇閿欒琛?$patterns = @(
  'fatal error:', 'error:', 'Error [0-9]', 'undefined reference', 'multiple definition',
  'No rule to make target', 'cannot open file', 'prerequisites cannot be defined',
  'is not a valid token', 'No space left', 'too many errors', 'FAILED:',
  'segmentation fault', 'internal compiler error', '\*\*\* ', 'C compiler is too old'
)
$rows = @()
foreach ($j in $fail) {
  $name = $j.name
  $m = [regex]::Match($name, '缂栬瘧\s+(\S+)\s+v(\d+)')
  $dev = if ($m.Success) { $m.Groups[1].Value } else { $name }
  $ver = if ($m.Success) { $m.Groups[2].Value } else { '?' }
  $logFile = Join-Path $OutDir ("{0}_v{1}_{2}.log" -f ($dev -replace '[^\w\.\-]', '_'), $ver, $j.id)
  $logUrl = "https://api.github.com/repos/$repo/actions/jobs/$($j.id)/logs"
  & curl.exe -sL -H "Authorization: Bearer $tok" -H 'User-Agent: dsh-builder' -H 'Accept: application/vnd.github+json' $logUrl -o $logFile 2>$null
  $size = if (Test-Path $logFile) { (Get-Item $logFile).Length } else { 0 }
  $errs = @()
  if ($size -gt 0) {
    $errs = Select-String -Path $logFile -Pattern $patterns -ErrorAction SilentlyContinue |
      ForEach-Object { $_.Line.Trim() } |
      Where-Object { $_ -notmatch '^##\[group\]' } |
      Select-Object -Last 6
  }
  $rows += [pscustomobject]@{ device = $dev; version = $ver; job = $j.id; bytes = $size; errors = ($errs -join ' || ') }
  "  {0} v{1}: {2}B, {3} err" -f $dev, $ver, $size, $errs.Count
}
$rows | Export-Csv -Path (Join-Path $OutDir 'fails.csv') -NoTypeInformation -Encoding utf8
""
"===== 閿欒琛屾眹鎬?====="
$rows | ForEach-Object { "[{0} v{1}] {2}" -f $_.device, $_.version, $_.errors }
