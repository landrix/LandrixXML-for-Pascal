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
    x86                                      runs the Win32 runners d6, d6-checked,
                                             d7 and fpc322-win32 (built in this call
                                             or before) on real x86 hardware: x87
                                             results are not reliable in the x86
                                             emulator here; the x86 machine must
                                             answer
  Append "-checked" to any local toolchain (e.g. fpc322-linux-checked,
  d6-checked) to build with overflow and range checking, as consuming
  projects may do in debug builds.
  Sets: min (fpc322-linux, fpc322-linux-checked, d6, d13-win32),
        dev (before every commit: fpc322-win64, fpc322-win32,
        fpc322-linux-checked, d6, d13-win32, d13-win64),
        all (before a release: everything above plus d6-checked,
        d13-win64-checked, d13-osxarm64, mac and x86 at the end).

  Parallel: with more than one toolchain each builds (and runs its tests)
  in a child process of this script (-Worker), output in
  build/<toolchain>/worker.log, printed when it ends; -Jobs sets how many
  run at once (default: processor count minus 2), -Jobs 1 runs them one
  after the other in this process. One build.ps1 run per checkout at a
  time (the runs share build/).

  x86 machine (SSH alias ai-rtx5090, Windows 11, 32 threads, on all the
  time since 2026-11-23): the test runners of the Windows toolchains
  (fpc*-win32/-win64, d6, d7, d13-win32/-win64, also -checked; not
  fpc331-winarm) are built here and run there, all at once, natively
  instead of in the x86 emulator of this ARM machine. The runners and the
  committed test data (never tests/data/local, so Local.RealWorldFiles
  skips there) go into a fresh folder under D:\AI-Work, removed
  afterwards; their output: build/<toolchain>/x86.log. -Here runs them
  here; if the machine does not answer (also when it goes away after the
  first check) they run here with a warning; with x86 in the list an
  unreachable machine is an error. With -Here and x86 in the list, d7 is
  only built here and runs on x86, and the other runners of the x87 check
  run here and on x86 (a failure on either side counts). -NoRun skips the
  x86 step.

.EXAMPLE
  ./tools/build.ps1                 # minimum set
  ./tools/build.ps1 all
  ./tools/build.ps1 d6,d7 -NoRun
  ./tools/build.ps1 dev -Here       # the Windows tests on this machine
  ./tools/build.ps1 dev -Jobs 1     # one toolchain after the other
#>
param(
  [string[]]$Toolchains = @('min'),
  [string]$Program = 'tests/LandrixXmlTests.dpr',
  [switch]$NoRun,
  [switch]$AllowWarnings,
  [int]$Jobs = 0,
  [switch]$Here,
  # internal: one toolchain in a child process; its tests run on x86
  [switch]$Worker,
  [switch]$X86Deferred,
  # internal: the x86 step in a child process, for these toolchains
  [switch]$X86Worker,
  [string]$X86Names = ''
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
$X86Ssh = @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15', '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=8')
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
  # names are case-insensitive: d6 and D6 must not start two runs in one folder
  $t = $t.Trim().ToLowerInvariant()
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

# a toolchain whose test runner can run on the x86 machine
function Test-X86Toolchain([string]$Name) {
  return $Name -match '^(fpc\d+-win(32|64)|d(6|7)|d13-win(32|64))(-checked)?$'
}

function Invoke-Toolchain([string]$Name) {
  $out = "build/$Name"
  New-Item -ItemType Directory -Force $out | Out-Null
  # the output of an earlier x86 run must not stand next to this one
  Remove-Item -Force -ErrorAction SilentlyContinue "$out/x86.log", "$out/x86.log.err"
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
  if (-not $NoRun -and -not ($X86Deferred -and (Test-X86Toolchain $Name))) {
    if ($runCmd) { & $runCmd | Out-Host } else { & $exe $Root | Out-Host }
    $result.Run = $LASTEXITCODE
  }
  return $result
}

# Runs the test runners of the toolchains in $Names on the x86 machine, all
# at once, in a fresh folder with the committed test data; the folder is
# removed afterwards. Returns name -> exit code (1 for a runner that did not
# report) and whether the step itself failed.
function Invoke-X86Runs([string[]]$Names) {
  $out = 'build/x86'
  New-Item -ItemType Directory -Force $out | Out-Null
  $codes = @{}
  $failed = $false
  $procs = @()
  if ($ProgramName -match '[^A-Za-z0-9_.-]') { throw "x86: the program name '$ProgramName' needs quoting on the remote side" }
  $files = @()
  foreach ($r in $Names) {
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
  $created = $false
  $sw = [Diagnostics.Stopwatch]::StartNew()
  try {
    [IO.File]::WriteAllLines((Join-Path $Root $list), [string[]]$files)
    & tar.exe --no-recursion -cf $tar -T $list | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'tar failed' }
    & ssh.exe -n @X86Ssh $X86Host "mkdir D:\AI-Work\$dir" | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "ssh to $X86Host failed (exit code $LASTEXITCODE)" }
    $created = $true
    & scp.exe -q @X86Ssh $tar "${X86Host}:D:/AI-Work/$dir/x86.tar" | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'scp failed' }
    & ssh.exe -n @X86Ssh $X86Host "cd /d D:\AI-Work\$dir && tar -xf x86.tar && del x86.tar" | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'unpacking failed' }
    # one ssh session per runner, all at once (temporary files go next to
    # each runner, so they do not meet)
    foreach ($r in $Names) {
      $log = Join-Path $Root "build/$r/x86.log"
      Remove-Item -Force -ErrorAction SilentlyContinue $log, "$log.err"
      $remote = "cd /d D:\AI-Work\$dir && build\$r\$ProgramName.exe ."
      $argList = @('-n') + $X86Ssh + @($X86Host, "`"$remote`"")
      $p = Start-Process -FilePath 'ssh.exe' -ArgumentList $argList -NoNewWindow -PassThru `
        -RedirectStandardOutput $log -RedirectStandardError "$log.err"
      $null = $p.Handle  # keeps the exit code readable after the process ends
      $procs += @{ Name = $r; Proc = $p; Log = $log }
    }
    foreach ($job in $procs) {
      $job.Proc.WaitForExit()
      $code = $job.Proc.ExitCode
      if ($null -eq $code) { $code = 1 }
      $codes[$job.Name] = $code
      $lines = @()
      if (Test-Path $job.Log) { $lines = @(Get-Content $job.Log) }
      if ((Test-Path "$($job.Log).err") -and (Get-Item "$($job.Log).err").Length -gt 0) {
        $lines += @(Get-Content "$($job.Log).err" | Where-Object { $_ -notmatch '^\*\*' })
      }
      Write-Host "  $($job.Name) (exit code $code)" -ForegroundColor Cyan
      $lines | Where-Object { $_ -match 'test\(s\)|^FAIL|^ERROR' } | ForEach-Object { Write-Host "    $_" }
      if ($code -ne 0) { $lines | Select-Object -Last 15 | ForEach-Object { Write-Host "    $_" } }
    }
  } catch {
    Write-Host "  $_" -ForegroundColor Red
    $failed = $true
  } finally {
    # runners started before an error keep using the folder: wait for them
    foreach ($job in $procs) {
      if (-not $job.Proc.HasExited) { $job.Proc.WaitForExit() }
    }
    try {
      if ($created) {
        & ssh.exe -n @X86Ssh $X86Host "rmdir /s /q D:\AI-Work\$dir" | Out-Host
        if ($LASTEXITCODE -ne 0) {
          Write-Host "  could not remove D:\AI-Work\$dir on $X86Host" -ForegroundColor Red
          $failed = $true
        }
      }
    } finally {
      Remove-Item -Force -ErrorAction SilentlyContinue $tar, $list
    }
  }
  Write-Host ("  x86: {0:N1} min" -f $sw.Elapsed.TotalMinutes)
  return @{ Codes = $codes; Failed = $failed }
}

# The runners of the x86 step: the Windows toolchains built (deferred), with
# -Here and x86 in the list d7, and with x86 in the list the Win32 runners of
# the x87 check (also built before this call). $Built: results of this call.
function Get-X86Names($Built) {
  $names = @()
  if ($X86Deferred) {
    $names += @($Built | Where-Object { $_.Build -eq 0 -and (Test-X86Toolchain $_.Name) } | ForEach-Object { $_.Name })
  } elseif ($X86HereD7) {
    $names += @($Built | Where-Object { $_.Build -eq 0 -and $_.Name -like 'd7*' } | ForEach-Object { $_.Name })
  }
  if ($X86Listed -and $null -eq $x86Error) {
    foreach ($r in $X86Runners) {
      $b = @($Built | Where-Object { $_.Name -eq $r })
      if ($b.Count -gt 0 -and $b[0].Build -ne 0) { continue }
      if ($names -notcontains $r) { $names += $r }
    }
  }
  return $names
}

# The result file of a child process: written under another name and then
# renamed, so a child that dies while writing leaves no half file.
function Write-Result([string]$Path, $Value) {
  $json = $Value | ConvertTo-Json -Compress
  [IO.File]::WriteAllText("$Path.tmp", $json)
  Move-Item -Force "$Path.tmp" $Path
}

# The result of a child process, $null if it is missing or not readable or
# the process did not end with exit code 0.
function Read-Result([string]$Path, $Proc) {
  if ($Proc.ExitCode -ne 0 -or -not (Test-Path $Path)) { return $null }
  try {
    return (Get-Content -Raw $Path | ConvertFrom-Json)
  } catch {
    return $null
  }
}

function Invoke-ToolchainSafe([string]$Name) {
  try {
    return Invoke-Toolchain $Name
  } catch {
    Write-Host "  $_" -ForegroundColor Red
    return @{ Name = $Name; Build = -1; Diag = 0; Run = $null }
  }
}

if ($X86Worker) {
  # child process of a parallel run: the x86 step, result as JSON
  try {
    $x = Invoke-X86Runs @($X86Names.Split(',') | Where-Object { $_ -ne '' })
  } catch {
    Write-Host "  $_" -ForegroundColor Red
    $x = @{ Codes = @{}; Failed = $true }
  }
  New-Item -ItemType Directory -Force (Join-Path $Root 'build/x86') | Out-Null
  Write-Result (Join-Path $Root 'build/x86/worker-result.json') @{ Codes = $x.Codes; Failed = $x.Failed }
  exit 0
}

if ($Worker) {
  # child process of a parallel run: one toolchain, result as JSON
  $name = $expanded[0]
  $r = Invoke-ToolchainSafe $name
  Write-Result (Join-Path $Root "build/$name/worker-result.json") @{ Name = $r.Name; Build = $r.Build; Diag = $r.Diag; Run = $r.Run }
  exit 0
}

# Where the Windows tests run. With x86 in the list the machine must answer;
# without it the tests run here when it does not.
# Nothing runs with -NoRun, so neither does the x86 step.
$X86Listed = ($expanded -contains 'x86') -and -not $NoRun
$local = @($expanded | Where-Object { $_ -ne 'x86' } | Select-Object -Unique)
$X86Deferred = $false
$X86Note = $null
$x86Error = $null
$wantX86 = -not $NoRun -and ($X86Listed -or (-not $Here -and @($local | Where-Object { Test-X86Toolchain $_ }).Count -gt 0))
if ($wantX86) {
  # ssh writes to stderr when the machine does not answer; with 'Stop' that
  # would end the script before the fallback
  $saved = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & ssh.exe -n -o BatchMode=yes -o ConnectTimeout=8 $X86Host 'exit' 2>$null | Out-Null
    $probe = $LASTEXITCODE
  } catch {
    $probe = 1
  } finally {
    $ErrorActionPreference = $saved
  }
  if ($probe -ne 0) {
    if ($X86Listed) { $x86Error = "x86 machine $X86Host not reachable" }
    $X86Note = "x86 machine $X86Host not reachable: the Windows tests ran here"
    Write-Host "  $X86Note" -ForegroundColor Yellow
  } elseif (-not $Here) {
    $X86Deferred = $true
  }
}
# -Here with x86 in the list: d7 only builds here (the emulator gets some
# x87 results wrong), the x86 step runs it
$X86HereD7 = $Here -and $X86Listed -and $null -eq $x86Error

if ($Jobs -le 0) { $Jobs = [Math]::Max(1, [Environment]::ProcessorCount - 2) }
$results = @()
if ($Jobs -eq 1 -or $local.Count -le 1) {
  foreach ($t in $local) {
    Write-Host "=== $t ===" -ForegroundColor Cyan
    $saved = $X86Deferred
    if ($X86HereD7 -and $t -like 'd7*') { $X86Deferred = $true }
    $results += Invoke-ToolchainSafe $t
    $X86Deferred = $saved
  }
} else {
  $pwsh = (Get-Process -Id $PID).Path
  $byName = @{}
  $pending = [Collections.ArrayList]@($local)
  $running = @()
  # the x86 step starts as soon as the toolchains whose runners it takes
  # are built, while the others still run
  $x86Wanted = @()
  if ($X86Deferred) { $x86Wanted = @($local | Where-Object { Test-X86Toolchain $_ }) }
  elseif ($X86HereD7) { $x86Wanted = @($local | Where-Object { $_ -like 'd7*' }) }
  # the Win32 runners of the x87 check that this call builds
  if ($X86Listed) { $x86Wanted += @($local | Where-Object { $X86Runners -contains $_ -and $x86Wanted -notcontains $_ }) }
  $x86Started = -not ($X86Deferred -or $X86HereD7 -or ($X86Listed -and $null -eq $x86Error))
  $x86Early = $null
  Write-Host "running $($local.Count) toolchains, up to $Jobs at once" -ForegroundColor Cyan
  while ($pending.Count -gt 0 -or $running.Count -gt 0) {
    while ($pending.Count -gt 0 -and $running.Count -lt $Jobs) {
      $t = $pending[0]
      $pending.RemoveAt(0)
      $dir = Join-Path $Root "build/$t"
      New-Item -ItemType Directory -Force $dir | Out-Null
      Remove-Item -Force -ErrorAction SilentlyContinue "$dir/worker-result.json", "$dir/worker-result.json.tmp", "$dir/worker.log", "$dir/worker.err"
      $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Toolchains', $t,
        '-Program', "`"$Program`"", '-Worker')
      if ($NoRun) { $argList += '-NoRun' }
      if ($AllowWarnings) { $argList += '-AllowWarnings' }
      if ($X86Deferred -or ($X86HereD7 -and $t -like 'd7*')) { $argList += '-X86Deferred' }
      $proc = Start-Process -FilePath $pwsh -ArgumentList $argList -NoNewWindow -PassThru `
        -RedirectStandardOutput "$dir/worker.log" -RedirectStandardError "$dir/worker.err"
      $null = $proc.Handle  # keeps the exit code readable after the process ends
      $running += @{ Name = $t; Proc = $proc; Start = Get-Date }
    }
    if (-not $x86Started -and @($x86Wanted | Where-Object { -not $byName.ContainsKey($_) }).Count -eq 0) {
      $x86Started = $true
      $names = @(Get-X86Names @($local | Where-Object { $byName.ContainsKey($_) } | ForEach-Object { $byName[$_] }))
      if ($names.Count -gt 0) {
        $dir = Join-Path $Root 'build/x86'
        New-Item -ItemType Directory -Force $dir | Out-Null
        Remove-Item -Force -ErrorAction SilentlyContinue "$dir/worker-result.json", "$dir/worker-result.json.tmp", "$dir/worker.log", "$dir/worker.err"
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Toolchains', 'x86',
          '-Program', "`"$Program`"", '-X86Worker', '-X86Names', ($names -join ','))
        $proc = Start-Process -FilePath $pwsh -ArgumentList $argList -NoNewWindow -PassThru `
          -RedirectStandardOutput "$dir/worker.log" -RedirectStandardError "$dir/worker.err"
        $null = $proc.Handle
        $running += @{ Name = 'x86'; Proc = $proc; Start = Get-Date; X86 = $true; Names = $names }
      }
    }
    $done = @($running | Where-Object { $_.Proc.HasExited })
    if ($done.Count -eq 0) { Start-Sleep -Milliseconds 500; continue }
    $running = @($running | Where-Object { $done -notcontains $_ })
    foreach ($job in $done) {
      $t = $job.Name
      $dir = "build/$t"
      if ($job.X86) {
        Write-Host ("=== x86: {0} ({1:N1} min) ===" -f ($job.Names -join ', '), ((Get-Date) - $job.Start).TotalMinutes) -ForegroundColor Cyan
        if (Test-Path "$dir/worker.log") { Get-Content "$dir/worker.log" | ForEach-Object { Write-Host $_ } }
        if ((Test-Path "$dir/worker.err") -and (Get-Item "$dir/worker.err").Length -gt 0) {
          Get-Content "$dir/worker.err" | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        }
        $x86Early = @{ Names = $job.Names; Codes = @{}; Failed = $true }
        $j = Read-Result "$dir/worker-result.json" $job.Proc
        if ($null -ne $j) {
          $x86Early.Failed = [bool]$j.Failed
          foreach ($prop in $j.Codes.PSObject.Properties) { $x86Early.Codes[$prop.Name] = [int]$prop.Value }
        } else {
          Write-Host "  x86 worker ended without a result (exit code $($job.Proc.ExitCode))" -ForegroundColor Red
        }
        continue
      }
      Write-Host ("=== {0} ({1:N1} min) ===" -f $t, ((Get-Date) - $job.Start).TotalMinutes) -ForegroundColor Cyan
      if (Test-Path "$dir/worker.log") { Get-Content "$dir/worker.log" | ForEach-Object { Write-Host $_ } }
      if ((Test-Path "$dir/worker.err") -and (Get-Item "$dir/worker.err").Length -gt 0) {
        Get-Content "$dir/worker.err" | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
      }
      $j = Read-Result "$dir/worker-result.json" $job.Proc
      if ($null -ne $j) {
        $byName[$t] = @{ Name = $t; Build = [int]$j.Build; Diag = [int]$j.Diag; Run = $(if ($null -eq $j.Run) { $null } else { [int]$j.Run }) }
      } else {
        Write-Host "  worker ended without a result (exit code $($job.Proc.ExitCode))" -ForegroundColor Red
        $byName[$t] = @{ Name = $t; Build = -1; Diag = 0; Run = $null }
      }
    }
  }
  # the order of the list
  foreach ($t in $local) { $results += $byName[$t] }
}

$x86Run = @()
if ($null -ne $x86Early) {
  $x86Run = $x86Early.Names
  $x86 = $x86Early
} else {
  $x86Run = @(Get-X86Names $results)
}
if ($x86Run.Count -gt 0) {
  if ($null -eq $x86Early) {
    Write-Host "=== x86: $($x86Run -join ', ') ===" -ForegroundColor Cyan
    try {
      $x86 = Invoke-X86Runs $x86Run
    } catch {
      Write-Host "  $_" -ForegroundColor Red
      $x86 = @{ Codes = @{}; Failed = $true }
    }
  }
  # the machine went away after the probe: the deferred runners run here
  if ($X86Deferred -and $x86.Codes.Count -eq 0) {
    $X86Note = "x86 step failed before any runner ran: the Windows tests ran here"
    Write-Host "  $X86Note" -ForegroundColor Yellow
    foreach ($r in $results) {
      if ($x86Run -notcontains $r.Name) { continue }
      Write-Host "=== $($r.Name) (here) ===" -ForegroundColor Cyan
      & "build/$($r.Name)/$ProgramName.exe" $Root | Out-Host
      $x86.Codes[$r.Name] = $LASTEXITCODE
      $r.Where = 'here'
    }
    $x86.Failed = $false
  }
  foreach ($r in $results) {
    if ($x86Run -notcontains $r.Name) { continue }
    $c = $x86.Codes[$r.Name]
    if ($null -eq $c) { $c = 1 }
    if ($null -ne $r.Run) {
      # ran here as well (-Here with x86 in the list): a failure here stays
      if ($r.Run -eq 0) { $r.Run = $c }
      $r.Where = 'here and x86'
    } elseif ($r.Where -ne 'here') {
      $r.Run = $c
      $r.Where = 'x86'
    } else {
      $r.Run = $c
    }
  }
  if ($X86Listed) {
    $extra = @($x86Run | Where-Object { @($results | ForEach-Object { $_.Name }) -notcontains $_ })
    $code = $(if ($x86.Failed) { 1 } else { 0 })
    foreach ($n in $extra) { if ($x86.Codes[$n] -ne 0) { $code = 1 } }
    $results += @{ Name = 'x86'; Build = 0; Diag = 0; Run = $code; Where = 'x86' }
  } elseif ($x86.Failed) {
    $results += @{ Name = 'x86'; Build = 0; Diag = 0; Run = 1; Where = 'x86' }
  }
} elseif ($X86Listed) {
  if ($x86Error) {
    $results += @{ Name = 'x86'; Build = 0; Diag = 0; Run = 1; State = 'NOT REACHABLE' }
    Write-Host "  x86: $x86Error" -ForegroundColor Red
  }
}

Write-Host ''
Write-Host 'Summary' -ForegroundColor Cyan
if ($X86Note) { Write-Host $X86Note -ForegroundColor Yellow }
$failed = $false
foreach ($r in $results) {
  $state = 'OK'
  if ($r.Build -ne 0) { $state = 'BUILD FAILED'; $failed = $true }
  elseif ($r.Diag -gt 0 -and -not $AllowWarnings) { $state = "WARNINGS ($($r.Diag))"; $failed = $true }
  if ($r.Build -eq 0 -and $null -ne $r.Run -and $r.Run -ne 0) { $state = "TESTS FAILED"; $failed = $true }
  if ($r.State) { $state = $r.State }
  if ($r.Name -ne 'x86' -and $r.Where -match 'x86') { $state += " (tests $($r.Where -replace '^x86$', 'on x86'))" }
  '{0,-20} {1}' -f $r.Name, $state | Write-Host
}
if ($failed) { exit 1 } else { exit 0 }
