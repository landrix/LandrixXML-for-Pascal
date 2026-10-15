<#
.SYNOPSIS
  Runs the LandrixXml performance measurement (plan step 8) and reports
  times and peak memory.

.DESCRIPTION
  Builds tests/LandrixXmlPerf.dpr with the given toolchains (via build.ps1),
  then runs it twice per toolchain: once for the pull reader only and once
  for the DOM, so the peak working set of each scenario is measured
  separately (Windows toolchains only). Both peaks include generating the
  test document in memory (writer buffer and its copy), so the reader peak
  is an upper bound dominated by that step.

.EXAMPLE
  ./tools/perf.ps1                         # fpc322-win64, d13-win64, d6, 50 MB
  ./tools/perf.ps1 -Toolchains d6 -SizeMB 10
#>
param(
  [string[]]$Toolchains = @('fpc322-win64', 'd13-win64', 'd6'),
  [int]$SizeMB = 50
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

& "$PSScriptRoot/build.ps1" ($Toolchains -join ',') -Program tests/LandrixXmlPerf.dpr -NoRun | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'build failed' }

foreach ($t in $Toolchains) {
  $exe = Join-Path $Root "build/$t/LandrixXmlPerf.exe"
  Write-Host "=== $t, $SizeMB MB ===" -ForegroundColor Cyan
  foreach ($phase in 'reader', 'dom') {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = "$SizeMB $phase"
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    $peak = 0
    while (-not $p.HasExited) {
      try { $p.Refresh(); if ($p.PeakWorkingSet64 -gt $peak) { $peak = $p.PeakWorkingSet64 } } catch { }
      Start-Sleep -Milliseconds 50
    }
    $out = $p.StandardOutput.ReadToEnd()
    try { if ($p.PeakWorkingSet64 -gt $peak) { $peak = $p.PeakWorkingSet64 } } catch { }
    $out.Trim().Split("`n") | ForEach-Object { Write-Host "  $($_.Trim())" }
    if ($p.ExitCode -ne 0) { throw "$t $phase exited with $($p.ExitCode)" }
    Write-Host ("  peak working set ({0}): {1:N0} MB" -f $phase, ($peak / 1MB))
  }
}
