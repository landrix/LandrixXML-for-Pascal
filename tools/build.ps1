<#
.SYNOPSIS
  Builds and runs the LandrixXml test runner with one or more local toolchains.

.DESCRIPTION
  Every toolchain writes to build/<toolchain>/ so compiled units never mix.
  Compiler warnings, hints and notes that point into this repository count as
  failures (target: zero on all compilers). Exit code 0 = everything green.

  Toolchain names:
    fpc322-linux fpc324-linux fpc331-linux   FPC under WSL (aarch64-linux)
    fpc322-win32 fpc322-win64 fpc331-winarm  FPC on Windows
    d6 d7                                    Delphi 6 / Delphi 7 (Win32)
    d13-win32 d13-win64                      Delphi 13
    mac                                      FPC 3.2.4 on the Mac via SSH
  Append "-checked" to any local toolchain (e.g. fpc322-linux-checked,
  d6-checked) to build with overflow and range checking, as consuming
  projects may do in debug builds.
  Sets: min (fpc322-linux, fpc322-linux-checked, d6, d13-win32),
        all (everything above plus d6-checked and d13-win64-checked).

.EXAMPLE
  ./tools/build.ps1                 # minimum set
  ./tools/build.ps1 all
  ./tools/build.ps1 d6,d7 -NoRun
#>
param(
  [string[]]$Toolchains = @('min'),
  [string]$Program = 'tests/LandrixXmlTests.dpr',
  [switch]$NoRun,
  [switch]$AllowWarnings
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Delphi6  = 'D:\Projekte\Borland\Delphi6'
$Delphi7  = 'D:\Projekte\Borland\Delphi7'
$Delphi13 = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
$LocalBin = Join-Path $env:USERPROFILE '.local\bin'
$MacRunner = Join-Path $env:USERPROFILE '.local\share\remote-toolchains\macos-fpc\Run-PascalProgram.ps1'

$Sets = @{
  'min' = @('fpc322-linux', 'fpc322-linux-checked', 'd6', 'd13-win32')
  'all' = @('fpc322-linux', 'fpc322-linux-checked', 'fpc324-linux', 'fpc331-linux',
            'fpc322-win32', 'fpc322-win64', 'fpc331-winarm',
            'd6', 'd6-checked', 'd7', 'd13-win32', 'd13-win64', 'd13-win64-checked', 'mac')
}

$expanded = @()
foreach ($t in ($Toolchains -join ',').Split(',')) {
  $t = $t.Trim()
  if ($t -eq '') { continue }
  if ($Sets.ContainsKey($t)) { $expanded += $Sets[$t] } else { $expanded += $t }
}

$ProgramName = [IO.Path]::GetFileNameWithoutExtension($Program)
$WslRoot = '/mnt/' + $Root.Substring(0, 1).ToLower() + ($Root.Substring(2) -replace '\\', '/')

function Count-OwnDiagnostics([string[]]$Lines) {
  # Delphi: file.pas(12) Warning: ...   FPC: file.pas(12,5) Warning: ...
  # Language-independent (the local Delphi 13 prints "Warnung"/"Hinweis"):
  # every compiler line pointing into a source file is a diagnostic. Errors
  # already fail through the exit code.
  $own = $Lines | Where-Object {
    $_ -match '\.(pas|inc|dpr|lpr)\(\d+(,\d+)?\)'
  }
  return @($own)
}

function Invoke-Toolchain([string]$Name) {
  $out = "build/$Name"
  New-Item -ItemType Directory -Force $out | Out-Null
  $exe = $null
  $log = @()
  $runCmd = $null
  $Base = $Name -replace '-checked$', ''
  $Checked = $Base -ne $Name
  $fpcChecks = if ($Checked) { @('-Co', '-Cr') } else { @() }
  $dccChecks = if ($Checked) { @('-$Q+', '-$R+') } else { @() }

  switch -Regex ($Base) {
    '^fpc(\d+)-linux$' {
      $fpc = "~/.local/bin/fpc$($Matches[1])"
      $cmd = "cd '$WslRoot' && $fpc -B -vewnhi $($fpcChecks -join ' ') -Fusource -Fisource -FU$out -FE$out $Program 2>&1"
      $log = & wsl.exe -e bash -lc $cmd
      $code = $LASTEXITCODE
      $runCmd = { & wsl.exe -e bash -lc "cd '$WslRoot' && ./build/$Name/$ProgramName" }
    }
    '^fpc\d+-win(32|64|arm)$' {
      $wrapper = Join-Path $LocalBin "$Base.cmd"
      $log = & $wrapper -B -vewnhi @fpcChecks -Fusource -Fisource "-FU$out" "-FE$out" $Program 2>&1
      $code = $LASTEXITCODE
      $exe = "$out/$ProgramName.exe"
    }
    '^d(6|7)$' {
      $d = if ($Matches[1] -eq '6') { $Delphi6 } else { $Delphi7 }
      $winOut = $out -replace '/', '\'
      $log = & "$d\Bin\dcc32.exe" -B -Q -W -H @dccChecks "-U$d\Lib;source;tests" '-Isource' "-N$winOut" "-E$winOut" ($Program -replace '/', '\') 2>&1
      $code = $LASTEXITCODE
      $exe = "$out/$ProgramName.exe"
    }
    '^d13-win(32|64)$' {
      $bits = $Matches[1]
      $dcc = if ($bits -eq '32') { 'dcc32.exe' } else { 'dcc64.exe' }
      $log = & "$Delphi13\bin\$dcc" -B -Q -W -H @dccChecks '-NSSystem;System.Win;Winapi' "-U$Delphi13\lib\win$bits\release;source;tests" '-Isource' "-NU$out" "-E$out" $Program 2>&1
      $code = $LASTEXITCODE
      $exe = "$out/$ProgramName.exe"
    }
    '^mac$' {
      if (-not (Test-Path $MacRunner)) { throw "Mac runner not found: $MacRunner" }
      $log = & $MacRunner -Repository $Root -Program $Program -UnitPath 'source' -NoRun:$NoRun 2>&1
      $code = $LASTEXITCODE
      $log = @($log | ForEach-Object { "$_" })
      $log | Set-Content -Encoding utf8 "$out/build.log"
      Count-OwnDiagnostics $log | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
      $log | Where-Object { $_ -match 'test\(s\)|^FAIL|^ERROR|Fatal|Error:' } | ForEach-Object { Write-Host $_ }
      return @{ Name = $Name; Build = $code; Diag = (Count-OwnDiagnostics $log).Count; Run = $code; Log = $log }
    }
    default { throw "Unknown toolchain: $Name" }
  }

  $log = @($log | ForEach-Object { "$_" })
  $log | Set-Content -Encoding utf8 "$out/build.log"
  $diag = Count-OwnDiagnostics $log
  $result = @{ Name = $Name; Build = $code; Diag = $diag.Count; Run = $null; Log = $log }
  if ($code -ne 0) {
    $log | Select-Object -Last 30 | ForEach-Object { Write-Host "  $_" }
    return $result
  }
  $diag | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
  if (-not $NoRun) {
    if ($runCmd) { & $runCmd | Out-Host } else { & $exe $Root | Out-Host }
    $result.Run = $LASTEXITCODE
  }
  return $result
}

$results = @()
foreach ($t in $expanded) {
  Write-Host "=== $t ===" -ForegroundColor Cyan
  try {
    $results += Invoke-Toolchain $t
  } catch {
    Write-Host "  $_" -ForegroundColor Red
    $results += @{ Name = $t; Build = -1; Diag = 0; Run = $null }
  }
}

Write-Host ''
Write-Host 'Summary' -ForegroundColor Cyan
$failed = $false
foreach ($r in $results) {
  $state = 'OK'
  if ($r.Build -ne 0) { $state = 'BUILD FAILED'; $failed = $true }
  elseif ($r.Diag -gt 0 -and -not $AllowWarnings) { $state = "WARNINGS ($($r.Diag))"; $failed = $true }
  if ($r.Build -eq 0 -and $null -ne $r.Run -and $r.Run -ne 0) { $state = "TESTS FAILED"; $failed = $true }
  '{0,-14} {1}' -f $r.Name, $state | Write-Host
}
if ($failed) { exit 1 } else { exit 0 }
