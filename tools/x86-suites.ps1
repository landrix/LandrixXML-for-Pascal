<#
.SYNOPSIS
  Runs the test suites on the x86 machine, all at once, and brings their
  results back.

.DESCRIPTION
  The suite helpers are built here (fpc322-win64, x64) and run on the x86
  machine (SSH alias ai-rtx5090, Windows 11, 32 threads, Python 3 for all
  users; see CLAUDE.md) natively instead of in the x86 emulator of this ARM
  machine, each suite in its own SSH session at the same time.

  The work tree there, D:\AI-Work\landrix-xml-suites, keeps only the suites
  the runners downloaded (tests/data/*-suite, pinned and SHA-256 checked):
  everything else there is deleted before each call (also the results and
  baselines of the last one), then every tracked file (never
  tests/data/local) and the helpers are sent. One call at a time, here (the
  folder build/x86-suites/local.lock) and there (suites.lock; remove it by
  hand after a crash, once no runner of that call runs any more).

  What comes back into build/ here, as from a local run: QT3
  build/qt3/results-<profile>.txt and sets-<profile>.txt, XSLT
  build/xslt-tests/results.txt and sets.txt, XSTS build/xsts/results.txt,
  KoSIT build/kosit/results.txt; the console output of every suite (also
  xmlconf, which writes no file) is in build/x86-suites/<suite>.log (stderr
  in <suite>.log.err). -UpdateBaseline passes --update-baseline (QT3, XSLT,
  XSTS) and brings back the baseline of each suite that ended with exit
  code 0, to be reviewed and committed like a local update; under the load
  of six suites at once a timing-dependent case can drop out, so run an
  updated suite once more alone before committing its baseline.

  Suites: qt3 (XPath 2.0 profile), qt3-saxon, xslt, xsts, kosit, xmlconf.
  The XSLT cross-check is not among them: it needs Saxon and Java and runs
  on this machine as before.

.EXAMPLE
  ./tools/x86-suites.ps1                       # every suite
  ./tools/x86-suites.ps1 xslt,qt3-saxon
  ./tools/x86-suites.ps1 xslt -UpdateBaseline
#>
param(
  [string[]]$Suites = @('qt3', 'qt3-saxon', 'xslt', 'xsts', 'kosit', 'xmlconf'),
  [switch]$NoBuild,
  [switch]$UpdateBaseline,
  [int]$Sets = 25
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$X86Host = 'ai-rtx5090'
$Tree = 'D:\AI-Work\landrix-xml-suites'
$Toolchain = 'fpc322-win64'
$Ssh = @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15', '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=8')
$Threads = 30

# suite -> helper program, runner command line, files that come back
$Known = [ordered]@{
  'qt3'       = @{ Helper = 'LandrixXmlQt3'; Args = 'tools\run-qt3.py --profile xpath20'; Jobs = $true; SetsOption = $true
                   Back = @('build/qt3/results-xpath20.txt', 'build/qt3/sets-xpath20.txt'); Baseline = 'tests/data/qt3-baseline.txt' }
  'qt3-saxon' = @{ Helper = 'LandrixXmlQt3'; Args = 'tools\run-qt3.py --profile saxon'; Jobs = $true; SetsOption = $true
                   Back = @('build/qt3/results-saxon.txt', 'build/qt3/sets-saxon.txt'); Baseline = 'tests/data/qt3-baseline-saxon.txt' }
  'xslt'      = @{ Helper = 'LandrixXmlXsltSuite'; Args = 'tools\run-xslt-tests.py'; Jobs = $true; SetsOption = $true
                   Back = @('build/xslt-tests/results.txt', 'build/xslt-tests/sets.txt'); Baseline = 'tests/data/xslt-baseline.txt' }
  'xsts'      = @{ Helper = 'LandrixXmlXsts'; Args = 'tools\run-xsts.py'; Jobs = $true; SetsOption = $false
                   Back = @('build/xsts/results.txt'); Baseline = 'tests/data/xsts-baseline.txt' }
  'kosit'     = @{ Helper = 'LandrixXmlKosit'; Args = 'tools\run-kosit-suite.py'; Jobs = $false; SetsOption = $false
                   Back = @('build/kosit/results.txt'); Baseline = $null }
  'xmlconf'   = @{ Helper = 'LandrixXmlConformance'; Args = 'tools\run-xmlconf.py'; Jobs = $false; SetsOption = $false
                   Back = @(); Baseline = $null }
}

$list = @()
foreach ($s in ($Suites -join ',').Split(',')) {
  $s = $s.Trim().ToLowerInvariant()
  if ($s -eq '') { continue }
  if (-not $Known.Contains($s)) { throw "unknown suite '$s' (known: $($Known.Keys -join ', '))" }
  if ($list -notcontains $s) { $list += $s }
}
if ($list.Count -eq 0) { throw 'no suite' }

# remote commands go through cmd; an error on stderr must not end the script
function Invoke-Remote([string]$Command) {
  $saved = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & ssh.exe -n @Ssh $X86Host $Command 2>&1 | Where-Object { "$_" -notmatch '^\*\*' } | ForEach-Object { Write-Host "  $_" }
    return $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $saved
  }
}

$out = 'build/x86-suites'
New-Item -ItemType Directory -Force $out | Out-Null
# one call per checkout: the helpers are built into one folder
$localLock = "$out/local.lock"
try {
  New-Item -ItemType Directory $localLock -ErrorAction Stop | Out-Null
} catch {
  throw "$localLock exists: another x86-suites.ps1 call runs in this checkout, or remove the folder after a crash"
}

$id = "$(Get-Date -Format 'yyyyMMdd-HHmmss')-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$tarList = "$out/send-$id.txt"
$tar = "$out/send-$id.tar"
$clean = "$out/clean-$id.cmd"
$back = "$out/back-$id.tar"
$locked = $false
$failed = $false
$codes = [ordered]@{}
$procs = @()
$sw = [Diagnostics.Stopwatch]::StartNew()
try {
  # the helpers, built here
  $helpers = @($list | ForEach-Object { $Known[$_].Helper } | Select-Object -Unique)
  if (-not $NoBuild) {
    foreach ($h in $helpers) {
      $buildOut = @(& "$PSScriptRoot/build.ps1" $Toolchain -Program "tests/$h.dpr" -NoRun 6>&1 | ForEach-Object { "$_" })
      if ($LASTEXITCODE -ne 0) {
        $buildOut | ForEach-Object { Write-Host "  $_" }
        throw "building $h failed"
      }
    }
  }
  foreach ($h in $helpers) {
    if (-not (Test-Path "build/$Toolchain/$h.exe")) { throw "build/$Toolchain/$h.exe missing" }
  }

  $files = @(git -c core.quotepath=off ls-files)
  if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed' }
  $files = @($files | Where-Object { ($_ -notlike 'tests/data/local/*') -and (Test-Path -LiteralPath $_ -PathType Leaf) })
  $files += @($helpers | ForEach-Object { "build/$Toolchain/$_.exe" })
  [IO.File]::WriteAllLines((Join-Path $Root $tarList), [string[]]$files)
  & tar.exe --no-recursion -cf $tar -T $tarList | Out-Host
  if ($LASTEXITCODE -ne 0) { throw 'tar failed' }

  # the lock: an existing folder and a failed connection differ
  $code = Invoke-Remote "if not exist $Tree mkdir $Tree"
  if ($code -ne 0) { throw "ssh to $X86Host failed (exit code $code)" }
  $code = Invoke-Remote "mkdir $Tree\suites.lock"
  if ($code -eq 255) { throw "ssh to $X86Host failed (exit code 255)" }
  if ($code -ne 0) {
    throw "$Tree\suites.lock exists on ${X86Host}: another run is active, or remove the folder after a crash"
  }
  $locked = $true

  # everything there except the lock and the downloaded suites goes: no
  # result, baseline or file of an earlier call survives (a batch file
  # outside the tree, so it does not delete itself)
  $cleanCmd = @(
    '@echo off',
    "cd /d $Tree || exit /b 1",
    'for /d %%d in (*) do if /i not "%%d"=="tests" if /i not "%%d"=="suites.lock" rmdir /s /q "%%d"',
    'del /q /a * 2>nul',
    'if exist tests (',
    '  for /d %%d in (tests\*) do if /i not "%%d"=="tests\data" rmdir /s /q "%%d"',
    '  del /q /a tests\* 2>nul',
    ')',
    'if exist tests\data (',
    '  for /d %%d in (tests\data\*) do (echo %%~nxd| findstr /r /c:"-suite$" >nul || rmdir /s /q "%%d")',
    '  del /q /a tests\data\* 2>nul',
    ')',
    'exit /b 0')
  [IO.File]::WriteAllLines((Join-Path $Root $clean), [string[]]$cleanCmd)
  & scp.exe -q @Ssh $clean "${X86Host}:D:/AI-Work/landrix-xml-suites-clean.cmd" | Out-Host
  if ($LASTEXITCODE -ne 0) { throw 'scp failed' }
  if ((Invoke-Remote "D:\AI-Work\landrix-xml-suites-clean.cmd && del D:\AI-Work\landrix-xml-suites-clean.cmd") -ne 0) {
    throw 'cleaning the work tree failed'
  }
  & scp.exe -q @Ssh $tar "${X86Host}:$($Tree -replace '\\', '/')/send.tar" | Out-Host
  if ($LASTEXITCODE -ne 0) { throw 'scp failed' }
  if ((Invoke-Remote "cd /d $Tree && tar -xf send.tar && del send.tar") -ne 0) { throw 'unpacking failed' }
  Write-Host ("sent ({0:N1} min); running {1}" -f $sw.Elapsed.TotalMinutes, ($list -join ', ')) -ForegroundColor Cyan

  # both QT3 profiles read one suite: it is downloaded once before they
  # start (a run whose filter finds no test set stops after that), and it
  # must be complete then
  if ($list -contains 'qt3' -and $list -contains 'qt3-saxon') {
    Invoke-Remote "cd /d $Tree && python tools\run-qt3.py --filter no-such-test-set --exe build\$Toolchain\LandrixXmlQt3.exe" | Out-Null
    $catalog = Invoke-Remote "cd /d $Tree & (for /d %d in (tests\data\qt3-suite\qt3tests-*) do @if exist %d\catalog.xml exit 0) & exit 1"
    if ($catalog -ne 0) { throw 'the QT3 suite could not be downloaded' }
  }

  # every suite at once, the threads shared out
  $parallel = @($list | Where-Object { $Known[$_].Jobs }).Count
  $perSuite = [Math]::Max(2, [Math]::Floor($Threads / [Math]::Max(1, $parallel)))
  foreach ($s in $list) {
    $k = $Known[$s]
    $cmd = "cd /d $Tree && python $($k.Args) --exe build\$Toolchain\$($k.Helper).exe"
    if ($k.Jobs) { $cmd += " --jobs $perSuite" }
    if ($k.SetsOption -and $Sets -gt 0) { $cmd += " --sets $Sets" }
    if ($UpdateBaseline -and $k.Baseline) { $cmd += ' --update-baseline' }
    $log = Join-Path $Root "$out/$s.log"
    Remove-Item -Force -ErrorAction SilentlyContinue $log, "$log.err"
    $argList = @('-n') + $Ssh + @($X86Host, "`"$cmd`"")
    $p = Start-Process -FilePath 'ssh.exe' -ArgumentList $argList -NoNewWindow -PassThru `
      -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    $null = $p.Handle  # keeps the exit code readable after the process ends
    $procs += @{ Name = $s; Proc = $p; Log = $log; Start = Get-Date }
  }
  foreach ($job in $procs) {
    $job.Proc.WaitForExit()
    $code = $job.Proc.ExitCode
    if ($null -eq $code) { $code = 1 }
    $codes[$job.Name] = $code
    Write-Host ("=== {0} (exit code {1}, {2:N1} min) ===" -f $job.Name, $code, ($job.Proc.ExitTime - $job.Start).TotalMinutes) -ForegroundColor Cyan
    if (Test-Path $job.Log) { Get-Content $job.Log | Select-Object -Last 40 | ForEach-Object { Write-Host "  $_" } }
    if ((Test-Path "$($job.Log).err") -and (Get-Item "$($job.Log).err").Length -gt 0) {
      Get-Content "$($job.Log).err" | Where-Object { $_ -notmatch '^\*\*' } | Select-Object -Last 20 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    }
    if ($code -ne 0) { $failed = $true }
  }

  # the result files (written in this call: the tree was cleaned) and the
  # baselines of the suites that ended with exit code 0
  $wanted = @()
  foreach ($s in $list) {
    $wanted += $Known[$s].Back
    if ($UpdateBaseline -and $Known[$s].Baseline -and $codes[$s] -eq 0) { $wanted += $Known[$s].Baseline }
  }
  $wanted = @($wanted | Select-Object -Unique)
  if ($wanted.Count -gt 0) {
    $names = ($wanted | ForEach-Object { $_ -replace '/', '\' }) -join ' '
    # only the files that exist (a suite that stopped early wrote none);
    # exit code 3: nothing to fetch
    $collect = "cd /d $Tree && (if exist back.tar del back.tar) && (for %f in ($names) do @if exist %f echo %f) > back.txt " +
      "&& (for %s in (back.txt) do @if %~zs==0 exit 3) && tar -cf back.tar -T back.txt"
    $code = Invoke-Remote $collect
    if ($code -eq 0) {
      & scp.exe -q @Ssh "${X86Host}:$($Tree -replace '\\', '/')/back.tar" $back | Out-Host
      if ($LASTEXITCODE -ne 0) { throw 'fetching the results failed' }
      & tar.exe -xf $back | Out-Host
      if ($LASTEXITCODE -ne 0) { throw 'unpacking the results failed' }
    } elseif ($code -ne 3) {
      throw 'collecting the results failed'
    }
  }
} catch {
  Write-Host "  $_" -ForegroundColor Red
  $failed = $true
} finally {
  # suites started before an error keep using the tree: wait for them
  foreach ($job in $procs) {
    if (-not $job.Proc.HasExited) { $job.Proc.WaitForExit() }
  }
  if ($locked -and (Invoke-Remote "rmdir $Tree\suites.lock") -ne 0) {
    Write-Host "  could not remove $Tree\suites.lock on $X86Host" -ForegroundColor Red
    $failed = $true
  }
  Remove-Item -Force -ErrorAction SilentlyContinue $tar, $tarList, $back, $clean
  Remove-Item -Force -Recurse -ErrorAction SilentlyContinue $localLock
}

Write-Host ''
Write-Host ("Summary ({0:N1} min)" -f $sw.Elapsed.TotalMinutes) -ForegroundColor Cyan
foreach ($s in $list) {
  $state = if (-not $codes.Contains($s)) { 'NOT RUN' } elseif ($codes[$s] -eq 0) { 'OK' } else { 'FAILED' }
  '{0,-10} {1}' -f $s, $state | Write-Host
}
if ($UpdateBaseline) { Write-Host 'baselines: see git diff tests/data/*baseline*' }
if ($failed) { exit 1 } else { exit 0 }
