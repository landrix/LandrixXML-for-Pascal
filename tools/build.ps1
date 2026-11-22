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
    d13-osxarm64                             Delphi 13 macOS ARM64 (LLVM back end),
                                             compile only: every unit under source/
                                             and tests/ is compiled, nothing is
                                             linked or run (no macOS SDK imported)
    mac                                      FPC 3.2.4 on the Mac via SSH
    x86                                      runs the Win32 runners built before
                                             (d6, d6-checked, d7, fpc322-win32) on
                                             real x86 hardware (SSH alias
                                             ai-rtx5090): x87 results are not
                                             reliable in the x86 emulator here
  Append "-checked" to any local toolchain (e.g. fpc322-linux-checked,
  d6-checked) to build with overflow and range checking, as consuming
  projects may do in debug builds.
  Sets: min (fpc322-linux, fpc322-linux-checked, d6, d13-win32),
        dev (before every commit: fpc322-win64, fpc322-win32,
        fpc322-linux-checked, d6, d13-win32, d13-win64),
        all (before a release: everything above plus d6-checked,
        d13-win64-checked, d13-osxarm64, mac and x86 at the end).
  With x86 in the list, d7 is only built here: the x86 emulator of this
  ARM machine computes some x87 results wrongly, its tests run on x86.

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
$X86Host = 'ai-rtx5090'
$X86Runners = @('d6', 'd6-checked', 'd7', 'fpc322-win32')
$MacRunner = Join-Path $env:USERPROFILE '.local\share\remote-toolchains\macos-fpc\Run-PascalProgram.ps1'

$Sets = @{
  'min' = @('fpc322-linux', 'fpc322-linux-checked', 'd6', 'd13-win32')
  'dev' = @('fpc322-win64', 'fpc322-win32', 'fpc322-linux-checked', 'd6', 'd13-win32', 'd13-win64')
  'all' = @('fpc322-linux', 'fpc322-linux-checked', 'fpc324-linux', 'fpc331-linux',
            'fpc322-win32', 'fpc322-win64', 'fpc331-winarm',
            'd6', 'd6-checked', 'd7', 'd13-win32', 'd13-win64', 'd13-win64-checked',
            'd13-osxarm64', 'mac', 'x86')
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
      # Absolute path: dcc32 of Delphi 6 and 7 ignores a relative -N path
      # such as "-Nbuild\d6" and writes the .dcu files next to the sources.
      $winOut = (Join-Path $Root $out) -replace '/', '\'
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
    '^d13-osxarm64$' {
      # Compile only: linking needs the macOS SDK (imported through PAServer),
      # which is not set up. -Program is ignored here.
      $code = 0
      $log = @()
      $units = @(Get-ChildItem source -Filter *.pas | Sort-Object Name) +
               @(Get-ChildItem tests -Filter *.pas | Sort-Object Name)
      foreach ($unit in $units) {
        $log += "--- $($unit.Name)"
        $log += & "$Delphi13\bin\dccosxarm64.exe" -B -Q -W -H @dccChecks '-NSSystem' "-U$Delphi13\lib\osxarm64\release;source;tests" '-Isource' "-NU$out" $unit.FullName 2>&1
        if ($LASTEXITCODE -ne 0) { $code = $LASTEXITCODE }
      }
      $log = @($log | ForEach-Object { "$_" })
      $log | Set-Content -Encoding utf8 "$out/build.log"
      $diag = Count-OwnDiagnostics $log
      if ($code -ne 0) {
        # later units keep compiling, so show the error lines, not only the tail
        $log | Where-Object { $_ -match 'Fehler|Error|Schwerwiegend|Fatal' } | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
      } else {
        $diag | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
        Write-Host '  compiled only (not linked, tests not run)'
      }
      return @{ Name = $Name; Build = $code; Diag = $diag.Count; Run = $null; Log = $log }
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
    '^x86$' {
      # The runners built before (in this call or an earlier one) and the
      # committed test data (never tests/data/local) go into a fresh folder
      # on the x86 machine; the folder is removed afterwards.
      if ($NoRun) { return @{ Name = $Name; Build = 0; Diag = 0; Run = $null; Log = @() } }
      if ($ProgramName -match '[^A-Za-z0-9_.-]') { throw "x86: the program name '$ProgramName' needs quoting on the remote side" }
      $files = @()
      foreach ($r in $X86Runners) {
        $f = "build/$r/$ProgramName.exe"
        if (-not (Test-Path $f)) { throw "$f missing: build $r first" }
        $files += $f
      }
      $data = @(git -c core.quotepath=off ls-files tests/data)
      if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed' }
      $files += @($data | Where-Object { ($_ -ne 'tests/data/local') -and ($_ -notlike 'tests/data/local/*') })
      $id = "$(Get-Date -Format 'yyyyMMdd-HHmmss')-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
      $dir = "landrix-xml-$id"
      $list = "$out/x86-$id.txt"
      $tar = "$out/x86-$id.tar"
      $ssh = @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15', '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=8')
      $code = 0
      $log = @()
      $created = $false
      try {
        [IO.File]::WriteAllLines((Join-Path $Root $list), [string[]]$files)
        & tar.exe --no-recursion -cf $tar -T $list | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'tar failed' }
        & ssh.exe @ssh $X86Host "mkdir D:\AI-Work\$dir" | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "ssh to $X86Host failed (exit code $LASTEXITCODE; switched off?)" }
        $created = $true
        & scp.exe -q @ssh $tar "${X86Host}:D:/AI-Work/$dir/x86.tar" | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'scp failed' }
        & ssh.exe @ssh $X86Host "cd /d D:\AI-Work\$dir && tar -xf x86.tar && del x86.tar" | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'unpacking failed' }
        foreach ($r in $X86Runners) {
          $rlog = @(& ssh.exe @ssh $X86Host "cd /d D:\AI-Work\$dir && build\$r\$ProgramName.exe ." 2>&1 | ForEach-Object { "$_" })
          $rcode = $LASTEXITCODE
          if ($rcode -ne 0) { $code = $rcode }
          $log += "--- $r (exit code $rcode)"
          $log += $rlog
          Write-Host "  $r" -ForegroundColor Cyan
          $rlog | Where-Object { $_ -match 'test\(s\)|^FAIL|^ERROR' } | ForEach-Object { Write-Host "    $_" }
          if ($rcode -ne 0) { $rlog | Select-Object -Last 15 | ForEach-Object { Write-Host "    $_" } }
        }
      } finally {
        try {
          if ($created) {
            & ssh.exe @ssh $X86Host "rmdir /s /q D:\AI-Work\$dir" | Out-Host
            if ($LASTEXITCODE -ne 0) {
              Write-Host "  could not remove D:\AI-Work\$dir on $X86Host" -ForegroundColor Red
              $code = 1
            }
          }
        } finally {
          Remove-Item -Force -ErrorAction SilentlyContinue $tar, $list
        }
      }
      $log | Set-Content -Encoding utf8 "$out/build.log"
      return @{ Name = $Name; Build = 0; Diag = 0; Run = $code; Log = $log }
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
  if (-not $NoRun -and -not ($X86Present -and $X86Runners -contains $Name -and $Name -like 'd7*')) {
    if ($runCmd) { & $runCmd | Out-Host } else { & $exe $Root | Out-Host }
    $result.Run = $LASTEXITCODE
  }
  return $result
}

# x86 runs the runners built in this call, so it comes last
$X86Present = $expanded -contains 'x86'
if ($X86Present) { $expanded = @($expanded | Where-Object { $_ -ne 'x86' }) + @('x86') }
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
