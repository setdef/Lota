# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# The Windows kit: records what Lota's apps do on a real Windows PC and
# writes one results file, results.txt, with screenshots beside it, into
# results\lota-kit-results-STAMP, and zips that folder. run-kit.cmd starts
# it with this process's execution policy bypassed; it changes no system
# setting and needs no administrator. It writes only into the kit's
# folder, except %TEMP% (Add-Type), the save folders the games make
# (%APPDATA%\winkit and %APPDATA%\dot_popper), and, only when asked, Dot
# Popper's per-user install, which it removes again.
#
# It must run in Windows PowerShell 5.1 and in PowerShell 7, so it uses
# only what both have: no ternary or null operators, no three-argument
# Join-Path, no Process.Kill(true), no ProcessStartInfo.ArgumentList.
# The file is ASCII, since 5.1 reads a file without a BOM as ANSI: names
# outside ASCII are built from [char] codes.
#
# Every step runs in Invoke-Step, which writes its failure into the
# results and goes on; every program it starts has a timeout, after which
# it and its children are killed.
#
# Parameters for CI only (the maintainer passes none):
#   -Unattended       never ask; -Install and -HoldSeconds decide
#   -Install yes|no   whether to try the setup program (default: ask)
#   -HoldSeconds N    run the hands-on section for N seconds without asking
#   -MesaDir PATH     copy Mesa's software OpenGL beside each app
#   -NullAudio        ALSOFT_DRIVERS=null, for a computer with no audio device

[CmdletBinding()]
param(
  [switch] $Unattended,
  [ValidateSet('ask', 'yes', 'no')] [string] $Install = 'ask',
  [int] $HoldSeconds = 0,
  [string] $MesaDir = '',
  [switch] $NullAudio
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Kit = $PSScriptRoot
if (-not $Kit) { $Kit = Split-Path -Parent $MyInvocation.MyCommand.Path }
$KitStart = Get-Date
$Stamp = $KitStart.ToString('yyyyMMdd-HHmmss')
$ResultsRoot = Join-Path $Kit 'results'
$ResultsDir = Join-Path $ResultsRoot "lota-kit-results-$Stamp"
$ResultsFile = Join-Path $ResultsDir 'results.txt'
$ResultsZip = Join-Path $ResultsRoot "lota-kit-results-$Stamp.zip"
$Work = Join-Path $Kit 'work'
$Apps = Join-Path $Kit 'apps'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$Steps = New-Object System.Collections.ArrayList
$script:StepStatus = 'PASS'
$script:StepNote = ''
$script:Shots = 0
$HostExe = (Get-Process -Id $PID).Path

# Folder names outside ASCII, as Fledge asked: "Unicode" with five
# accented letters, a space, and two CJK characters ("Japan"), and "jogo"
# with an o-umlaut.
$UnicodeName = -join @([char]0xDC, 'n', [char]0xEF, 'c', [char]0xF6, 'd', [char]0xE9, ' ', [char]0x65E5, [char]0x672C)
$JogoName = -join @('j', [char]0xF6, 'go')

New-Item -ItemType Directory -Force -Path $ResultsDir | Out-Null

# ---------------------------------------------------------------- output

function Get-Stamp { (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffzzz') }

function Out-Result([string] $Text) {
  [IO.File]::AppendAllText($ResultsFile, $Text + "`r`n", $Utf8)
}

function Out-Lines([string] $Heading, $Lines) {
  Out-Result "--- $Heading"
  foreach ($line in @($Lines)) { Out-Result ([string]$line) }
}

function Out-Object([string] $Heading, $Object) {
  $text = ($Object | Format-List | Out-String -Width 250).Trim()
  Out-Lines $Heading $text
}

function Set-Step([string] $Status, [string] $Note) {
  $script:StepStatus = $Status
  if ($Note) { $script:StepNote = $Note }
}

function Invoke-Step([string] $Id, [string] $Title, [scriptblock] $Body) {
  $script:StepStatus = 'PASS'
  $script:StepNote = ''
  $started = Get-Date
  Write-Host ''
  Write-Host ("[{0}] {1} ..." -f $started.ToString('HH:mm:ss'), $Title)
  Out-Result ''
  Out-Result "=== STEP ${Id}: $Title [$(Get-Stamp)]"
  try {
    & $Body
  } catch {
    $script:StepStatus = 'FAIL'
    $script:StepNote = "error: $($_.Exception.Message)"
    Out-Result "error: $($_.Exception.Message)"
    Out-Result "where: $($_.InvocationInfo.PositionMessage)"
  }
  $seconds = [Math]::Round(((Get-Date) - $started).TotalSeconds, 1)
  Out-Result "=== END ${Id}: $($script:StepStatus) after $seconds s [$(Get-Stamp)] $($script:StepNote)"
  [void]$Steps.Add([pscustomobject]@{ Id = $Id; Title = $Title; Status = $script:StepStatus; Note = $script:StepNote })
  Write-Host ("    {0}  {1}" -f $script:StepStatus, $script:StepNote)
}

# -------------------------------------------------------- Windows helpers

$script:HaveDrawing = $false
try {
  Add-Type -AssemblyName System.Drawing
  Add-Type -AssemblyName System.Windows.Forms
  $script:HaveDrawing = $true
} catch { $script:DrawingError = $_.Exception.Message }

$script:HaveWin32 = $false
try {
  Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class LotaKitWin32 {
  public delegate bool EnumProc(IntPtr window, IntPtr data);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc proc, IntPtr data);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc proc, IntPtr data);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr window, StringBuilder text, int size);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr window, StringBuilder text, int size);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
  [DllImport("user32.dll")] public static extern IntPtr MonitorFromPoint(POINT point, uint flags);
  [DllImport("shcore.dll")] public static extern int GetDpiForMonitor(IntPtr monitor, int type, out uint x, out uint y);
  public static List<string> Texts(uint pid) {
    List<string> texts = new List<string>();
    EnumWindows(delegate (IntPtr window, IntPtr data) {
      uint owner;
      GetWindowThreadProcessId(window, out owner);
      if (owner != pid) return true;
      texts.Add("window " + Describe(window) + (IsWindowVisible(window) ? "" : " (hidden)"));
      EnumChildWindows(window, delegate (IntPtr child, IntPtr d) { texts.Add("  child " + Describe(child)); return true; }, IntPtr.Zero);
      return true;
    }, IntPtr.Zero);
    return texts;
  }
  static string Describe(IntPtr window) {
    StringBuilder name = new StringBuilder(256);
    GetClassName(window, name, 256);
    StringBuilder text = new StringBuilder(4096);
    GetWindowText(window, text, 4096);
    return "[" + name.ToString() + "] " + text.ToString().Replace("\r", "").Replace("\n", " | ");
  }
  public static string MonitorDpi(int x, int y) {
    POINT point = new POINT(); point.X = x; point.Y = y;
    IntPtr monitor = MonitorFromPoint(point, 2);
    uint dx, dy;
    int result = GetDpiForMonitor(monitor, 0, out dx, out dy);
    if (result != 0) return "unknown (GetDpiForMonitor " + result + ")";
    return dx + " dpi (" + (dx * 100 / 96) + "%)";
  }
}
'@
  $script:HaveWin32 = $true
} catch { $script:Win32Error = $_.Exception.Message }

# Screenshots come out at the screen's real size only in a process that
# is aware of the display's scale.
$script:DpiAwareness = 'not set'
if ($script:HaveWin32) {
  try {
    if ([LotaKitWin32]::SetProcessDpiAwarenessContext([IntPtr](-4))) { $script:DpiAwareness = 'per-monitor v2' }
    else { $script:DpiAwareness = 'per-monitor v2 refused (already set?)' }
  } catch {
    try { [void][LotaKitWin32]::SetProcessDPIAware(); $script:DpiAwareness = 'system' } catch { $script:DpiAwareness = "failed: $($_.Exception.Message)" }
  }
}

function Save-Screen([string] $Name) {
  if (-not $script:HaveDrawing) { Out-Result "screenshot $Name skipped: System.Drawing did not load"; return }
  try {
    $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $path = Join-Path $ResultsDir $Name
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Jpeg)
    $graphics.Dispose()
    $bitmap.Dispose()
    $script:Shots++
    Out-Result "screenshot: $Name ($($bounds.Width)x$($bounds.Height)) [$(Get-Stamp)]"
  } catch {
    Out-Result "screenshot $Name failed: $($_.Exception.Message)"
  }
}

function Get-WindowTexts([int] $ProcessId) {
  if (-not $script:HaveWin32) { return @('(window texts unavailable: Add-Type failed)') }
  try { return @([LotaKitWin32]::Texts([uint32]$ProcessId)) } catch { return @("(window texts failed: $($_.Exception.Message))") }
}

function Get-Children([int] $ProcessId) {
  try {
    return @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $ProcessId" -ErrorAction Stop |
        ForEach-Object { "$($_.Name) (pid $($_.ProcessId))" })
  } catch { return @("(child processes unreadable: $($_.Exception.Message))") }
}

function Stop-Tree($Process) {
  try {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = Join-Path $env:SystemRoot 'System32\taskkill.exe'
    $info.Arguments = "/PID $($Process.Id) /T /F"
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $killer = [System.Diagnostics.Process]::Start($info)
    [void]$killer.WaitForExit(15000)
  } catch { }
  try { if (-not $Process.HasExited) { $Process.Kill() } } catch { }
  try { [void]$Process.WaitForExit(10000) } catch { }
}

function Get-EpochMs { [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }

# The variables a desktop gives every program, for a run with a clean
# environment, as Lota's fuse workflow runs its app.
$CleanNames = 'SystemRoot', 'SystemDrive', 'windir', 'ComSpec', 'PATHEXT', 'OS', 'PROCESSOR_ARCHITECTURE',
  'NUMBER_OF_PROCESSORS', 'USERPROFILE', 'USERNAME', 'USERDOMAIN', 'HOMEDRIVE', 'HOMEPATH', 'APPDATA', 'LOCALAPPDATA',
  'ProgramData', 'ProgramFiles', 'ProgramFiles(x86)', 'PUBLIC', 'TEMP', 'TMP', 'ALSOFT_DRIVERS', 'GALLIUM_DRIVER'

# Runs a program with its output captured and a timeout; takes the
# screenshots asked for, samples the process each second when asked,
# closes or kills it at a given second when asked, and kills it, and
# its children, after the timeout or when an error dialog appears.
function Invoke-Child {
  param(
    [string] $Label, [string] $FilePath, [string] $Arguments = '', [string] $WorkingDirectory = '',
    [hashtable] $Environment = @{}, [switch] $CleanEnvironment, [int] $TimeoutSeconds = 60,
    [int[]] $ShotsAt = @(), [switch] $Sample, [switch] $WatchDialog, [int] $CloseAt = 0, [int] $KillAt = 0
  )
  $info = New-Object System.Diagnostics.ProcessStartInfo
  $info.FileName = $FilePath
  $info.Arguments = $Arguments
  $info.UseShellExecute = $false
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $info.StandardOutputEncoding = $Utf8
  $info.StandardErrorEncoding = $Utf8
  $info.CreateNoWindow = $true
  if ($WorkingDirectory) { $info.WorkingDirectory = $WorkingDirectory } else { $info.WorkingDirectory = Split-Path -Parent $FilePath }
  $variables = $info.EnvironmentVariables
  if ($CleanEnvironment) {
    $keep = @{}
    foreach ($name in $CleanNames) {
      $value = [Environment]::GetEnvironmentVariable($name)
      if ($value) { $keep[$name] = $value }
    }
    $keep['PATH'] = "$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\Wbem"
    $variables.Clear()
    foreach ($name in $keep.Keys) { $variables[$name] = $keep[$name] }
  }
  foreach ($name in $Environment.Keys) {
    if ($null -eq $Environment[$name]) { $variables.Remove($name) } else { $variables[$name] = [string]$Environment[$name] }
  }
  $r = [pscustomobject]@{
    Label = $Label; FilePath = $FilePath; Arguments = $Arguments; Result = 'exited'; Code = $null; Out = ''; Err = ''
    StartMs = 0; Seconds = 0; WindowMs = $null; Title = ''; Samples = @(); Texts = @(); Children = $null; Notes = @()
  }
  $samples = New-Object System.Collections.ArrayList
  $notes = New-Object System.Collections.ArrayList
  $shots = @($ShotsAt | Sort-Object)
  $shotIndex = 0
  $nextSample = 1
  $closed = $false
  $r.StartMs = Get-EpochMs
  $watch = [System.Diagnostics.Stopwatch]::StartNew()
  $process = [System.Diagnostics.Process]::Start($info)
  $outTask = $process.StandardOutput.ReadToEndAsync()
  $errTask = $process.StandardError.ReadToEndAsync()
  while (-not $process.HasExited) {
    $t = $watch.Elapsed.TotalSeconds
    try {
      $process.Refresh()
      if ($null -eq $r.WindowMs -and $process.MainWindowHandle -ne [IntPtr]::Zero) {
        $r.WindowMs = [int]$watch.ElapsedMilliseconds
        $r.Title = $process.MainWindowTitle
      }
      if ($WatchDialog -and $null -ne $r.WindowMs -and $process.MainWindowTitle -match 'error|fehler|erreur') {
        Start-Sleep -Milliseconds 800
        $r.Texts = Get-WindowTexts $process.Id
        Save-Screen "$Label-dialog.jpg"
        Stop-Tree $process
        $r.Result = "error dialog '$($process.MainWindowTitle)', killed"
        break
      }
      if ($Sample -and $t -ge $nextSample) {
        [void]$samples.Add(('{0,3}s cpu={1:N0}ms ws={2:N0}MB private={3:N0}MB threads={4} handles={5}' -f $nextSample,
            $process.TotalProcessorTime.TotalMilliseconds, ($process.WorkingSet64 / 1MB), ($process.PrivateMemorySize64 / 1MB),
            $process.Threads.Count, $process.HandleCount))
        $nextSample++
      }
    } catch { }
    if ($null -eq $r.Children -and $t -ge 3) { $r.Children = Get-Children $process.Id }
    if ($shotIndex -lt $shots.Count -and $t -ge $shots[$shotIndex]) {
      Save-Screen ("{0}-{1}s.jpg" -f $Label, $shots[$shotIndex])
      if ($shotIndex -eq 0) { $r.Texts = Get-WindowTexts $process.Id }
      $shotIndex++
    }
    if ($CloseAt -gt 0 -and -not $closed -and $t -ge $CloseAt) {
      $closed = $true
      [void]$notes.Add("asked its window to close (WM_CLOSE) at $([Math]::Round($t, 1)) s: $($process.CloseMainWindow())")
    }
    if ($KillAt -gt 0 -and $t -ge $KillAt) {
      Stop-Tree $process
      $r.Result = "killed on purpose at $KillAt s"
      break
    }
    if ($t -ge $TimeoutSeconds) {
      $r.Texts = Get-WindowTexts $process.Id
      Save-Screen "$Label-timeout.jpg"
      Stop-Tree $process
      $r.Result = "timeout after $TimeoutSeconds s, killed"
      break
    }
    Start-Sleep -Milliseconds 200
  }
  [void]$process.WaitForExit(10000)
  $r.Seconds = [Math]::Round($watch.Elapsed.TotalSeconds, 1)
  if ($process.HasExited) { $r.Code = $process.ExitCode } else { $r.Code = 'still running' }
  if ($outTask.Wait(5000)) { $r.Out = $outTask.Result } else { $r.Out = '(standard output still open)' }
  if ($errTask.Wait(5000)) { $r.Err = $errTask.Result } else { $r.Err = '(standard error still open)' }
  $r.Samples = @($samples)
  $r.Notes = @($notes)
  $gone = $null -eq (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)
  $r | Add-Member -NotePropertyName Gone -NotePropertyValue $gone
  return $r
}

function Format-Code($Code) {
  if ($Code -is [int]) { return ('{0} (0x{1:X8})' -f $Code, $Code) }
  return [string]$Code
}

function Out-Child($r) {
  Out-Result "run: $($r.Label)"
  Out-Result "program: $($r.FilePath) $($r.Arguments)"
  Out-Result "started at (epoch ms): $($r.StartMs)"
  Out-Result "result: $($r.Result); exit status $(Format-Code $r.Code) after $($r.Seconds) s; gone afterwards: $($r.Gone)"
  if ($null -ne $r.WindowMs) { Out-Result "window appeared after: $($r.WindowMs) ms, title '$($r.Title)'" }
  else { Out-Result 'window appeared after: (no main window seen)' }
  foreach ($line in @(Get-Timing $r)) { Out-Result $line }
  foreach ($note in $r.Notes) { Out-Result "note: $note" }
  if ($null -ne $r.Children) { Out-Result "child processes at 3 s: $(if (@($r.Children).Count) { $r.Children -join ', ' } else { 'none' })" }
  if (@($r.Texts).Count) { Out-Lines 'its windows' $r.Texts }
  if (@($r.Samples).Count) { Out-Lines 'process each second' $r.Samples }
  Out-Lines 'stdout' $r.Out.TrimEnd()
  Out-Lines 'stderr' (Limit-Text $r.Err)
  Out-Result '--- end of output'
}

function Limit-Text([string] $Text) {
  $lines = @($Text.TrimEnd() -split "`r?`n")
  if ($lines.Count -le 300) { return ($lines -join "`r`n") }
  return ((@($lines | Select-Object -First 100) + "... ($($lines.Count - 200) lines left out) ..." + @($lines | Select-Object -Last 100)) -join "`r`n")
}

# How long the game took to reach Lota.load and its first frame, from the
# times it prints and the time the kit started it.
function Get-Timing($r) {
  $lines = @()
  if ($r.Out -match 'time at load: (\d+)') { $lines += "launch to Lota.load: $([int64]$Matches[1] - $r.StartMs) ms" }
  if ($r.Out -match 'time at first frame: (\d+)') { $lines += "launch to first frame: $([int64]$Matches[1] - $r.StartMs) ms" }
  return $lines
}

# Whether a winkit run did what it should: PASS, NO-GPU (it said the
# renderer was refused), or FAIL.
function Test-Winkit($r) {
  $out = [string]$r.Out
  $timing = (@(Get-Timing $r) -join '; ')
  if ($r.Result -ne 'exited') { Set-Step 'FAIL' "did not quit by itself: $($r.Result)"; return }
  if ($r.Code -eq 4 -and $out -match 'window: refused') {
    $why = @($out -split "`r?`n" | Where-Object { $_ -match '^  \S' } | Select-Object -First 4) -join ' '
    Set-Step 'NO-GPU' "the app could not open a window here:$why"
    return
  }
  if ($r.Code -ne 0) { Set-Step 'FAIL' "exit status $(Format-Code $r.Code)"; return }
  $renderer = ''
  if ($out -match 'renderer: ([^\r\n]*)') { $renderer = $Matches[1] }
  $square = Read-Pixel $out 'pixel in the orange square'
  $corner = Read-Pixel $out 'pixel in the corner'
  if ($null -eq $square -or $null -eq $corner) { Set-Step 'FAIL' "drew, but read back no frame ($renderer)"; return }
  $right = (Test-Close $square @(1.0, 0.5, 0.0)) -and (Test-Close $corner @(0.1, 0.2, 0.6))
  if (-not $right) { Set-Step 'FAIL' "the frame read back has the wrong colours ($renderer)"; return }
  Set-Step 'PASS' "drew with $renderer; $timing"
}

function Read-Pixel([string] $Out, [string] $Label) {
  $pattern = [regex]::Escape($Label) + ': \[([-\d.]+), ([-\d.]+), ([-\d.]+)'
  $match = [regex]::Match($Out, $pattern)
  if (-not $match.Success) { return $null }
  return @([double]$match.Groups[1].Value, [double]$match.Groups[2].Value, [double]$match.Groups[3].Value)
}

function Test-Close($Actual, $Expected) {
  for ($i = 0; $i -lt 3; $i++) { if ([Math]::Abs($Actual[$i] - $Expected[$i]) -gt 0.03) { return $false } }
  return $true
}

function Get-Zone([string] $Path) {
  try {
    $zone = Get-Content -LiteralPath $Path -Stream Zone.Identifier -ErrorAction Stop
    return ((@($zone) | Where-Object { $_ -and $_ -notmatch '^\[ZoneTransfer\]' }) -join '; ')
  } catch { return 'none' }
}

function Expand-Zip([string] $Zip, [string] $Destination) {
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($Zip, $Destination)
  } catch {
    Out-Result "ZipFile could not unpack $(Split-Path -Leaf $Zip) ($($_.Exception.Message)); trying Expand-Archive"
    Expand-Archive -LiteralPath $Zip -DestinationPath $Destination -Force
  }
}

function Copy-Mesa([string] $Folder) {
  if (-not $MesaDir) { return }
  Get-ChildItem -LiteralPath $MesaDir -File | Copy-Item -Destination $Folder -Force
  Out-Result "Mesa's software OpenGL copied beside the program in $Folder (CI only)"
}

function Remove-Mesa([string] $Folder) {
  if (-not $MesaDir) { return }
  Get-ChildItem -LiteralPath $MesaDir -File | ForEach-Object {
    Remove-Item -LiteralPath (Join-Path $Folder $_.Name) -Force -ErrorAction SilentlyContinue
  }
}

function Get-Snapshot([string] $Folder) {
  $prefix = $Folder.Length
  return @(Get-ChildItem -LiteralPath $Folder -Recurse -Force -File | ForEach-Object {
      '{0} {1} {2}' -f $_.FullName.Substring($prefix), $_.Length, $_.LastWriteTimeUtc.Ticks
    })
}

function Copy-Frame([string] $Label) {
  $frame = Join-Path $env:APPDATA 'winkit\frame.png'
  if (Test-Path -LiteralPath $frame) {
    Move-Item -LiteralPath $frame -Destination (Join-Path $ResultsDir "$Label-frame.png") -Force
    Out-Result "the game's own frame: $Label-frame.png"
  }
}

function Ask([string] $Question) {
  if ($Unattended) { return $false }
  $answer = Read-Host "$Question [y/N]"
  return ($answer -match '^\s*y')
}

# ------------------------------------------------------------------ start

Write-Host 'Lota Windows kit'
Write-Host "Results go to: $ResultsDir"
Out-Result "Lota Windows kit results, started $(Get-Stamp)"
$infoFile = Join-Path $Kit 'kit-info.txt'
if (Test-Path -LiteralPath $infoFile) { Out-Lines 'kit-info.txt' (Get-Content -LiteralPath $infoFile) }
Out-Result "kit folder: $Kit"
Out-Result "parameters: Unattended=$Unattended Install=$Install HoldSeconds=$HoldSeconds MesaDir=$MesaDir NullAudio=$NullAudio"

$doInstall = $false
if ($Install -eq 'yes') { $doInstall = $true }
elseif ($Install -eq 'ask') {
  Write-Host ''
  Write-Host "Optional: also try Dot Popper's installer? It installs Dot Popper for you only (no administrator),"
  Write-Host 'starts it from the Start menu for a few seconds, and uninstalls it again. It adds about 2 minutes.'
  $doInstall = Ask 'Try the installer?'
}
Write-Host ''
Write-Host 'From now on, please do not touch the mouse or keyboard until the kit says it is done (about 6 minutes).'
Write-Host 'Windows will open and close by themselves; you may hear short tones and Dot Popper sounds.'

if ($MesaDir) { $env:GALLIUM_DRIVER = 'llvmpipe' }
if ($NullAudio) { $env:ALSOFT_DRIVERS = 'null' }

# ------------------------------------------------------------------ steps

Invoke-Step 'motw' "Download marks on the kit's files, then unblocking them" {
  Out-Result 'Zone.Identifier of each file, read before Unblock-File:'
  $kitFiles = @(@(Get-ChildItem -LiteralPath $Kit -File -Force) + @(Get-ChildItem -LiteralPath $Apps -File -Force -ErrorAction SilentlyContinue))
  foreach ($file in $kitFiles) {
    Out-Result ("  {0}: {1}" -f $file.FullName.Substring($Kit.Length + 1), (Get-Zone $file.FullName))
  }
  $downloads = $null
  try { $downloads = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}' } catch { }
  if ($downloads) { $downloads = [Environment]::ExpandEnvironmentVariables($downloads) }
  foreach ($folder in @((Split-Path -Parent $Kit), $downloads) | Where-Object { $_ } | Select-Object -Unique) {
    foreach ($zip in @(Get-ChildItem -LiteralPath $folder -Filter 'lota-windows-kit*.zip' -File -ErrorAction SilentlyContinue)) {
      Out-Result "  the kit's zip $($zip.FullName): $(Get-Zone $zip.FullName)"
    }
  }
  $marked = @($kitFiles | Where-Object { (Get-Zone $_.FullName) -ne 'none' })
  foreach ($file in $marked) { Unblock-File -LiteralPath $file.FullName }
  Out-Result "unblocked: $($marked.Count) files (Unblock-File removes only the download mark, Zone.Identifier)"
  Set-Step 'INFO' "$($marked.Count) files carried a download mark and were unblocked"
}

Invoke-Step 'checksums' "Checking the kit's files against SHA256SUMS" {
  $sums = Join-Path $Kit 'SHA256SUMS'
  if (-not (Test-Path -LiteralPath $sums)) { Set-Step 'SKIP' 'no SHA256SUMS in the kit'; return }
  $bad = 0
  foreach ($line in @(Get-Content -LiteralPath $sums | Where-Object { $_ -match '^[0-9a-f]{64} ' })) {
    $hash = $line.Substring(0, 64)
    $name = $line.Substring(64).TrimStart(' ', '*')
    $path = Join-Path $Kit $name
    if (-not (Test-Path -LiteralPath $path)) { Out-Result "missing: $name"; $bad++; continue }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $hash) { Out-Result "different: $name"; $bad++ } else { Out-Result "ok: $name" }
  }
  if ($bad) { Set-Step 'FAIL' "$bad files missing or changed" } else { Set-Step 'PASS' 'every file matches' }
}

Invoke-Step 'system' 'Recording facts about this computer' {
  Set-Step 'INFO' ''
  $os = Get-CimInstance Win32_OperatingSystem
  $version = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
  Out-Result "windows: $($os.Caption) $($version.DisplayVersion) build $($os.BuildNumber).$($version.UBR) ($($os.OSArchitecture)), version $($os.Version)"
  Out-Result "installed: $($os.InstallDate); last boot: $($os.LastBootUpTime); locale: $([Globalization.CultureInfo]::CurrentCulture.Name)"
  try {
    $codePage = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage'
    Out-Result "code pages: ANSI $($codePage.ACP), OEM $($codePage.OEMCP)"
  } catch { Out-Result "code pages: $($_.Exception.Message)" }
  $computer = Get-CimInstance Win32_ComputerSystem
  Out-Result "computer: $($computer.Manufacturer) $($computer.Model), memory $([Math]::Round($computer.TotalPhysicalMemory / 1GB, 1)) GB"
  foreach ($cpu in @(Get-CimInstance Win32_Processor)) {
    Out-Result "cpu: $($cpu.Name.Trim()), $($cpu.NumberOfCores) cores, $($cpu.NumberOfLogicalProcessors) threads, $($cpu.MaxClockSpeed) MHz"
  }
  foreach ($gpu in @(Get-CimInstance Win32_VideoController)) {
    Out-Result "gpu: $($gpu.Name); driver $($gpu.DriverVersion) of $($gpu.DriverDate); $($gpu.CurrentHorizontalResolution)x$($gpu.CurrentVerticalResolution) at $($gpu.CurrentRefreshRate) Hz (max $($gpu.MaxRefreshRate)); status $($gpu.Status)"
    Out-Result "  processor: $($gpu.VideoProcessor); PNP: $($gpu.PNPDeviceID)"
    Out-Result "  installed display drivers: $($gpu.InstalledDisplayDrivers)"
  }
  $smi = Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'
  if (Test-Path -LiteralPath $smi) {
    $r = Invoke-Child -Label 'nvidia-smi' -FilePath $smi -Arguments '--query-gpu=name,driver_version,pstate,temperature.gpu,utilization.gpu,memory.used,memory.total,display_active --format=csv' -TimeoutSeconds 20
    Out-Lines 'nvidia-smi' $r.Out.TrimEnd()
  } else { Out-Result 'nvidia-smi: not installed' }
  Out-Result "dpi awareness of the kit: $script:DpiAwareness"
  try {
    $applied = (Get-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' -ErrorAction Stop).AppliedDPI
    Out-Result "AppliedDPI (main display scale): $applied ($([int]($applied * 100 / 96))%)"
  } catch { Out-Result 'AppliedDPI: not set' }
  if ($script:HaveDrawing) {
    foreach ($screen in @([System.Windows.Forms.Screen]::AllScreens)) {
      $b = $screen.Bounds
      $dpi = 'unknown'
      if ($script:HaveWin32) { $dpi = [LotaKitWin32]::MonitorDpi($b.X + [int]($b.Width / 2), $b.Y + [int]($b.Height / 2)) }
      Out-Result "display: $($screen.DeviceName) $($b.Width)x$($b.Height) at $($b.X),$($b.Y) primary=$($screen.Primary) bits=$($screen.BitsPerPixel) scale=$dpi"
    }
  } else { Out-Result "displays: System.Drawing did not load: $script:DrawingError" }
  foreach ($monitor in @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue)) {
    $name = -join @($monitor.UserFriendlyName | Where-Object { $_ } | ForEach-Object { [char]$_ })
    Out-Result "monitor: $name (active $($monitor.Active))"
  }
  foreach ($sound in @(Get-CimInstance Win32_SoundDevice)) { Out-Result "sound device: $($sound.Name) ($($sound.Status))" }
  try {
    $render = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render'
    $best = $null
    foreach ($key in @(Get-ChildItem -LiteralPath $render -ErrorAction Stop)) {
      $device = Get-ItemProperty -LiteralPath $key.PSPath
      if ($device.DeviceState -ne 1) { continue }
      $props = Get-ItemProperty -LiteralPath (Join-Path $key.PSPath 'Properties') -ErrorAction SilentlyContinue
      $name = "$($props.'{a45c254e-df1c-4efd-8020-67d146a850e0},2') ($($props.'{b3f8fa53-0004-438e-9003-51a46e139bfc},6'))"
      $when = ''
      $role = $device.'Role:0'
      if ($role -and @($role).Count -ge 16) { $when = '{0:D4}-{1:D2}-{2:D2} {3:D2}:{4:D2}:{5:D2}' -f [BitConverter]::ToUInt16($role, 0), [BitConverter]::ToUInt16($role, 2), [BitConverter]::ToUInt16($role, 6), [BitConverter]::ToUInt16($role, 8), [BitConverter]::ToUInt16($role, 10), [BitConverter]::ToUInt16($role, 12) }
      Out-Result "audio output (active): $name, made default at $when"
      if ($when -and ($null -eq $best -or $when -gt $best.When)) { $best = [pscustomobject]@{ Name = $name; When = $when } }
    }
    if ($best) { Out-Result "default audio output (the one made default last): $($best.Name)" } else { Out-Result 'default audio output: none active' }
  } catch { Out-Result "audio outputs: $($_.Exception.Message)" }
  $pads = @(Get-CimInstance Win32_PnPEntity | Where-Object {
      $_.PNPClass -eq 'XnaComposite' -or $_.PNPClass -eq 'XboxComposite' -or "$($_.Name)" -match 'game ?pad|controller|xbox|joystick|dualsense|dualshock|gamepad'
    })
  if ($pads.Count) { foreach ($pad in $pads) { Out-Result "controller: $($pad.Name) [$($pad.PNPClass)] $($pad.Status) $($pad.DeviceID)" } }
  else { Out-Result 'controllers: none found' }
  $userProfile = $env:USERPROFILE
  Out-Result "user profile: $userProfile (outside ASCII: $($userProfile -match '[^\x00-\x7F]'), spaces: $($userProfile -match ' '))"
  Out-Result "kit folder: $Kit (outside ASCII: $($Kit -match '[^\x00-\x7F]'), spaces: $($Kit -match ' '), length: $($Kit.Length))"
  Out-Result "appdata: $env:APPDATA; localappdata: $env:LOCALAPPDATA; temp: $env:TEMP"
  Out-Result "documents: $([Environment]::GetFolderPath('MyDocuments')); desktop: $([Environment]::GetFolderPath('Desktop'))"
  Out-Result "powershell: $($PSVersionTable.PSVersion) $($PSVersionTable.PSEdition) at $HostExe; .NET $([Environment]::Version); 64-bit: $([Environment]::Is64BitProcess)"
  $elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  Out-Result "elevated (administrator): $elevated"
  Out-Result "execution policies: $((Get-ExecutionPolicy -List | ForEach-Object { "$($_.Scope)=$($_.ExecutionPolicy)" }) -join ', ')"
  foreach ($pair in @(
      @('SmartScreen (Explorer)', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer', 'SmartScreenEnabled'),
      @('SmartScreen (policy)', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System', 'EnableSmartScreen'),
      @('Smart App Control (0 off, 1 on, 2 evaluation)', 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy', 'VerifiedAndReputablePolicyState'),
      @('Developer Mode', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock', 'AllowDevelopmentWithoutDevLicense'),
      @('long paths', 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem', 'LongPathsEnabled'))) {
    $value = '(not set)'
    try { $read = (Get-ItemProperty -LiteralPath $pair[1] -ErrorAction Stop).($pair[2]); if ($null -ne $read) { $value = $read } } catch { }
    Out-Result "$($pair[0]): $value"
  }
  try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    Out-Result "defender: antivirus $($mp.AntivirusEnabled), real-time $($mp.RealTimeProtectionEnabled), tamper protected $($mp.IsTamperProtected), engine $($mp.AMEngineVersion), signatures $($mp.AntivirusSignatureVersion)"
  } catch { Out-Result "defender: unreadable ($($_.Exception.Message))" }
  try {
    foreach ($av in @(Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntivirusProduct -ErrorAction Stop)) {
      Out-Result "antivirus product: $($av.displayName) (state $($av.productState))"
    }
  } catch { Out-Result 'antivirus products: unreadable here' }
}

Invoke-Step 'computerinfo' 'Get-ComputerInfo, verbatim' {
  Set-Step 'INFO' ''
  $command = '[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); Get-ComputerInfo | Format-List | Out-String -Width 250'
  $r = Invoke-Child -Label 'computerinfo' -FilePath $HostExe -Arguments "-NoProfile -NonInteractive -Command `"$command`"" -TimeoutSeconds 90
  Out-Result "result: $($r.Result) after $($r.Seconds) s"
  Out-Lines 'Get-ComputerInfo' $r.Out.Trim()
  if ($r.Err.Trim()) { Out-Lines 'stderr' $r.Err.Trim() }
  if ($r.Result -ne 'exited') { Set-Step 'FAIL' $r.Result }
}

Invoke-Step 'timeout' 'Checking that the kit stops a program that hangs' {
  $r = Invoke-Child -Label 'hang' -FilePath $HostExe -Arguments '-NoProfile -NonInteractive -Command "Start-Sleep -Seconds 600"' -TimeoutSeconds 3
  Out-Child $r
  if ($r.Result -like 'timeout*' -and $r.Gone -and $r.Seconds -lt 30) { Set-Step 'PASS' "a program that sleeps 600 s was stopped after $($r.Seconds) s" }
  else { Set-Step 'FAIL' "result $($r.Result), gone $($r.Gone)" }
}

$WinkitRoot = $null
$WinkitExe = $null
$PopperRoot = $null
$PopperExe = $null
$Setup = $null
$WinkitBefore = @()

Invoke-Step 'unpack' 'Unpacking the apps into the work folder' {
  $links = Join-Path $Work 'links'
  if (Test-Path -LiteralPath $links) {
    # Only the link goes, never what a junction points to.
    foreach ($link in @(Get-ChildItem -LiteralPath $links -Force)) {
      try { [IO.Directory]::Delete($link.FullName) } catch { Remove-Item -LiteralPath $link.FullName -Force -ErrorAction SilentlyContinue }
    }
  }
  if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $Work | Out-Null
  $winkitZip = @(Get-ChildItem -LiteralPath $Apps -Filter 'Winkit-*.zip')[0]
  $popperZip = @(Get-ChildItem -LiteralPath $Apps -Filter 'Dot Popper-*.zip')[0]
  $script:Setup = @(Get-ChildItem -LiteralPath $Apps -Filter '*-setup.exe')[0]
  Expand-Zip $winkitZip.FullName (Join-Path $Work 'winkit')
  Expand-Zip $popperZip.FullName (Join-Path $Work 'dotpopper')
  $script:WinkitRoot = Join-Path (Join-Path $Work 'winkit') $winkitZip.BaseName
  $script:PopperRoot = Join-Path (Join-Path $Work 'dotpopper') $popperZip.BaseName
  $script:WinkitExe = Join-Path $script:WinkitRoot 'Winkit.exe'
  $script:PopperExe = Join-Path $script:PopperRoot 'Dot Popper.exe'
  foreach ($exe in $script:WinkitExe, $script:PopperExe, $script:Setup.FullName) {
    $v = (Get-Item -LiteralPath $exe).VersionInfo
    Out-Result "$(Split-Path -Leaf $exe): description '$($v.FileDescription)', product '$($v.ProductName)' $($v.ProductVersion), file $($v.FileVersion), company '$($v.CompanyName)', original '$($v.OriginalFilename)'"
    $bytes = [IO.File]::ReadAllBytes($exe)
    $pe = [BitConverter]::ToInt32($bytes, 0x3C)
    $subsystem = [BitConverter]::ToUInt16($bytes, $pe + 0x5C)
    $kind = 'other'
    if ($subsystem -eq 2) { $kind = 'windowed (no console)' } elseif ($subsystem -eq 3) { $kind = 'console' }
    $signature = Get-AuthenticodeSignature -LiteralPath $exe
    Out-Result "  subsystem $subsystem, $kind; signature: $($signature.Status); download mark: $(Get-Zone $exe)"
  }
  $files = @(Get-ChildItem -LiteralPath $script:WinkitRoot -Recurse -File)
  Out-Result "winkit app: $($files.Count) files, $([Math]::Round(($files | Measure-Object Length -Sum).Sum / 1MB, 1)) MB at $script:WinkitRoot"
  Copy-Mesa $script:WinkitRoot
  Copy-Mesa $script:PopperRoot
  $script:WinkitBefore = Get-Snapshot $script:WinkitRoot
  # A copy of the setup program with the download mark it came with, for
  # CHECKLIST.txt's SmartScreen question; only made when it had one.
  $zone = Get-Zone $script:Setup.FullName
  $smart = Join-Path $Work 'smartscreen'
  New-Item -ItemType Directory -Force -Path $smart | Out-Null
  $copy = Join-Path $smart $script:Setup.Name
  Copy-Item -LiteralPath $script:Setup.FullName -Destination $copy
  Set-Content -LiteralPath $copy -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3`r`nHostUrl=https://github.com/"
  Out-Result "a copy of the setup program marked as downloaded from the internet (ZoneId=3), for CHECKLIST.txt: $copy (the original's mark was: $zone)"
}

function Invoke-Winkit([string] $Label, [string] $Exe, [string] $Arguments = '', [hashtable] $Environment = @{}, [switch] $CleanEnvironment, [int[]] $ShotsAt = @(), [int] $TimeoutSeconds = 40) {
  $r = Invoke-Child -Label $Label -FilePath $Exe -Arguments $Arguments -Environment $Environment -CleanEnvironment:$CleanEnvironment -ShotsAt $ShotsAt -TimeoutSeconds $TimeoutSeconds -Sample
  Out-Child $r
  Copy-Frame $Label
  return $r
}

$WinkitRuns = New-Object System.Collections.ArrayList

Invoke-Step 'winkit' 'Winkit, the diagnostics app, first start' {
  $r = Invoke-Winkit 'winkit' $WinkitExe -ShotsAt @(3)
  [void]$WinkitRuns.Add($r)
  Test-Winkit $r
}

Invoke-Step 'winkit-warm' 'Winkit again, with only the variables Windows gives every program' {
  $r = Invoke-Winkit 'winkit-warm' $WinkitExe -CleanEnvironment
  [void]$WinkitRuns.Add($r)
  Test-Winkit $r
}

Invoke-Step 'winkit-rubyenv' "Winkit with a Ruby developer's variables set" {
  $environment = @{ RUBYOPT = '-rnonexistent'; RUBYLIB = 'C:\nonexistent\lib'; GEM_HOME = 'C:\nonexistent\gems'; GEM_PATH = 'C:\nonexistent\gems'; RUBYSHELL = 'C:\nonexistent\sh.exe'; BUNDLE_GEMFILE = 'C:\nonexistent\Gemfile' }
  $r = Invoke-Winkit 'winkit-rubyenv' $WinkitExe -Environment $environment
  [void]$WinkitRuns.Add($r)
  Test-Winkit $r
  if ($script:StepStatus -ne 'FAIL' -and $r.Out -notmatch 'env RUBYOPT: [^\r\n]*-rnonexistent') { Set-Step 'FAIL' 'the app did not see RUBYOPT' }
}

Invoke-Step 'winkit-unicode' 'Winkit from a folder named with spaces and letters outside ASCII' {
  $folder = Join-Path (Join-Path $Work $UnicodeName) $JogoName
  New-Item -ItemType Directory -Force -Path $folder | Out-Null
  Copy-Item -LiteralPath $WinkitRoot -Destination $folder -Recurse
  $exe = Join-Path (Join-Path $folder (Split-Path -Leaf $WinkitRoot)) 'Winkit.exe'
  Out-Result "copied to: $exe"
  $r = Invoke-Winkit 'winkit-unicode' $exe -ShotsAt @(3)
  [void]$WinkitRuns.Add($r)
  Test-Winkit $r
}

Invoke-Step 'winkit-pacing' 'Winkit for 45 seconds, for frame pacing' {
  $r = Invoke-Winkit 'winkit-pacing' $WinkitExe '--seconds=45' -ShotsAt @(20) -TimeoutSeconds 80
  Test-Winkit $r
  if ($r.Out -match 'frames: ([^\r\n]*)') { $script:StepNote = "$($script:StepNote); frames: $($Matches[1])" }
}

Invoke-Step 'winkit-shell' 'Winkit started through the shell, as a double-click in Explorer starts it' {
  $log = Join-Path $ResultsDir 'winkit-shell.log'
  $env:WINKIT_LOG = $log
  try {
    $start = Get-EpochMs
    $process = Start-Process -FilePath $WinkitExe -WorkingDirectory (Split-Path -Parent $WinkitExe) -PassThru
    $handle = $process.Handle
    Start-Sleep -Seconds 3
    Out-Result "child processes at 3 s: $((@(Get-Children $process.Id)) -join ', ')"
    Out-Lines 'its windows at 3 s' (Get-WindowTexts $process.Id)
    Save-Screen 'winkit-shell-3s.jpg'
    if (-not $process.WaitForExit(40000)) { Stop-Tree $process; Set-Step 'FAIL' 'did not quit within 43 s; killed' }
    Out-Result "exit status: $(Format-Code $process.ExitCode); handle $handle"
  } finally {
    Remove-Item Env:\WINKIT_LOG -ErrorAction SilentlyContinue
  }
  $said = ''
  if (Test-Path -LiteralPath $log) { $said = Get-Content -LiteralPath $log -Raw -Encoding UTF8 }
  Out-Lines 'what it wrote to WINKIT_LOG' $said.TrimEnd()
  Copy-Frame 'winkit-shell'
  if ($script:StepStatus -ne 'FAIL') {
    $fake = [pscustomobject]@{ Result = 'exited'; Code = $process.ExitCode; Out = $said; StartMs = $start }
    Test-Winkit $fake
  }
}

Invoke-Step 'winkit-cmd' 'Winkit started from the Command Prompt (cmd.exe)' {
  $cmd = Join-Path $env:SystemRoot 'System32\cmd.exe'
  $r = Invoke-Child -Label 'winkit-cmd' -FilePath $cmd -Arguments "/d /c `"`"$WinkitExe`"`"" -WorkingDirectory $Work -TimeoutSeconds 40 -Sample
  Out-Child $r
  Copy-Frame 'winkit-cmd'
  Test-Winkit $r
}

Invoke-Step 'winkit-close' "Winkit's window closed as its X button closes it" {
  $r = Invoke-Child -Label 'winkit-close' -FilePath $WinkitExe -Arguments '--seconds=30' -CloseAt 5 -TimeoutSeconds 30
  Out-Child $r
  if ($r.Result -eq 'exited' -and $r.Code -eq 0) { Set-Step 'PASS' 'closed, exit status 0' }
  elseif ($r.Out -match 'window: refused') { Set-Step 'NO-GPU' 'no window to close' }
  else { Set-Step 'FAIL' "result $($r.Result), exit status $(Format-Code $r.Code)" }
}

Invoke-Step 'winkit-kill' 'Winkit killed, as Task Manager ends it' {
  $r = Invoke-Child -Label 'winkit-kill' -FilePath $WinkitExe -Arguments '--seconds=30' -KillAt 4 -TimeoutSeconds 30
  Out-Child $r
  Set-Step 'INFO' "exit status when killed: $(Format-Code $r.Code); gone: $($r.Gone)"
}

Invoke-Step 'winkit-links' 'Winkit through a junction and a symbolic link' {
  $links = Join-Path $Work 'links'
  New-Item -ItemType Directory -Force -Path $links | Out-Null
  $junction = Join-Path $links 'winkit-junction'
  $statuses = @()
  try {
    New-Item -ItemType Junction -Path $junction -Target $WinkitRoot | Out-Null
    $r = Invoke-Winkit 'winkit-junction' (Join-Path $junction 'Winkit.exe')
    Test-Winkit $r
    $statuses += "junction: $($script:StepStatus)"
  } catch { $statuses += "junction: could not run ($($_.Exception.Message))"; $script:StepStatus = 'FAIL' }
  $junctionStatus = $script:StepStatus
  $symlink = Join-Path $links 'Winkit-link.exe'
  # Windows looks for a DLL beside the path a program was started by, so
  # Mesa (CI only) goes beside the link too.
  Copy-Mesa $links
  try {
    New-Item -ItemType SymbolicLink -Path $symlink -Target $WinkitExe -ErrorAction Stop | Out-Null
    $r = Invoke-Winkit 'winkit-symlink' $symlink
    Test-Winkit $r
    $statuses += "symbolic link: $($script:StepStatus)"
  } catch {
    $statuses += "symbolic link: skipped, Windows refused to make one ($($_.Exception.Message)); it needs Developer Mode or an administrator"
    $script:StepStatus = $junctionStatus
  }
  foreach ($link in $symlink, $junction) {
    if (Test-Path -LiteralPath $link) { try { [IO.Directory]::Delete($link) } catch { Remove-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue } }
  }
  Remove-Mesa $links
  Set-Step $script:StepStatus ($statuses -join '; ')
}

Invoke-Step 'winkit-summary' 'Comparing the Winkit starts' {
  Set-Step 'INFO' ''
  foreach ($r in $WinkitRuns) { Out-Result ("{0}: {1}; exit {2}; window after {3} ms" -f $r.Label, ((@(Get-Timing $r)) -join ', '), $r.Code, $r.WindowMs) }
  $after = @(Get-Snapshot $WinkitRoot)
  if (-not @($WinkitBefore).Count -or -not $after.Count) { Set-Step 'FAIL' 'no snapshot of the app folder to compare'; return }
  $changed = @(Compare-Object $WinkitBefore $after | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" })
  if ($changed.Count) { Out-Lines "files of the app folder that changed while it ran (<= before, => after)" $changed; Set-Step 'INFO' "the app folder changed: $($changed.Count) entries" }
  else { Out-Result 'the app folder stayed unwritten'; Set-Step 'INFO' 'the app folder stayed unwritten' }
  if ($MesaDir) { Out-Result '(Mesa files copied in by the kit were there before the first run, so they do not count)' }
}

function Get-PopperFiles([string] $Label) {
  $save = Join-Path $env:APPDATA 'dot_popper'
  if (-not (Test-Path -LiteralPath $save)) { Out-Result "no $save"; return }
  Out-Lines "$save after $Label" (Get-ChildItem -LiteralPath $save -Force | ForEach-Object { "{0,10} {1} {2}" -f $_.Length, $_.LastWriteTime.ToString('s'), $_.Name })
  foreach ($name in 'rounds.csv', 'lifetime.txt', 'best_score.txt', 'sound.txt', 'taught.txt') {
    $file = Join-Path $save $name
    if (Test-Path -LiteralPath $file) { Out-Lines $name (Get-Content -LiteralPath $file -Encoding UTF8) }
  }
  foreach ($shot in @(Get-ChildItem -LiteralPath $save -Filter 'shot-*.png')) {
    Copy-Item -LiteralPath $shot.FullName -Destination (Join-Path $ResultsDir "$Label-$($shot.Name)") -Force
    Out-Result "copied the game's own screenshot: $Label-$($shot.Name)"
  }
}

function Test-Popper($r) {
  if ($r.Result -ne 'exited') {
    if ($r.Result -like 'error dialog*') {
      $message = @($r.Texts | Where-Object { $_ -match '^\s+child \[Static\] \S' } | ForEach-Object { $_ -replace '^\s+child \[Static\] ', '' })
      $status = 'FAIL'
      if (($message -join ' ') -match 'Unable to create renderer') { $status = 'NO-GPU' }
      Set-Step $status "it showed an error dialog: $($message -join ' ')"
    }
    else { Set-Step 'FAIL' $r.Result }
    return
  }
  if ($r.Code -ne 0) { Set-Step 'FAIL' "exit status $(Format-Code $r.Code)"; return }
  $first = @($r.Out -split "`r?`n")[0]
  Set-Step 'PASS' "quit by itself with 0; window after $($r.WindowMs) ms; first line: $first"
}

Invoke-Step 'dotpopper' 'Dot Popper playing itself for 45 seconds' {
  $before = Join-Path $env:APPDATA 'dot_popper'
  if (Test-Path -LiteralPath $before) { Out-Lines "$before before the run" (Get-ChildItem -LiteralPath $before -Force | ForEach-Object { $_.Name }) }
  else { Out-Result "$before does not exist before the run" }
  $environment = @{ DOT_POPPER_AUTOPLAY = '1'; DOT_POPPER_SEED = '7'; DOT_POPPER_QUIT_AFTER = '45'; DOT_POPPER_SHOTS = '3,12,25,38' }
  $r = Invoke-Child -Label 'dotpopper' -FilePath $PopperExe -Environment $environment -ShotsAt @(12, 30) -TimeoutSeconds 75 -Sample -WatchDialog
  Out-Child $r
  Get-PopperFiles 'dotpopper'
  Test-Popper $r
}

Invoke-Step 'dotpopper-noshaders' 'Dot Popper for 15 seconds with its shaders off' {
  $environment = @{ DOT_POPPER_AUTOPLAY = '1'; DOT_POPPER_SEED = '7'; DOT_POPPER_QUIT_AFTER = '15'; DOT_POPPER_NO_SHADERS = '1'; DOT_POPPER_SHOTS = $null }
  $r = Invoke-Child -Label 'dotpopper-noshaders' -FilePath $PopperExe -Environment $environment -ShotsAt @(8) -TimeoutSeconds 40 -Sample -WatchDialog
  Out-Child $r
  Test-Popper $r
}

function Get-UninstallEntries {
  return @(Get-ChildItem -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue |
      Where-Object { "$((Get-ItemProperty -LiteralPath $_.PSPath).DisplayName)" -like '*Dot Popper*' })
}

function Get-PopperShortcuts {
  $places = @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('Desktop'))
  return @($places | ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -Filter '*Dot Popper*.lnk' -ErrorAction SilentlyContinue })
}

function Out-InstallState([string] $When) {
  $folder = Join-Path $env:LOCALAPPDATA 'Programs\Dot Popper'
  Out-Result "$When; folder $folder exists: $(Test-Path -LiteralPath $folder)"
  if (Test-Path -LiteralPath $folder) {
    $files = @(Get-ChildItem -LiteralPath $folder -Recurse -File -Force)
    Out-Result "  $($files.Count) files; top level: $((Get-ChildItem -LiteralPath $folder -Force | ForEach-Object { $_.Name }) -join ', ')"
  }
  foreach ($entry in Get-UninstallEntries) {
    $p = Get-ItemProperty -LiteralPath $entry.PSPath
    Out-Result "  uninstall key: $($entry.Name)"
    foreach ($property in $p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }) { Out-Result "    $($property.Name) = $($property.Value)" }
  }
  $shell = New-Object -ComObject WScript.Shell
  $app = New-Object -ComObject Shell.Application
  foreach ($link in Get-PopperShortcuts) {
    $s = $shell.CreateShortcut($link.FullName)
    $id = ''
    try { $id = $app.NameSpace($link.DirectoryName).ParseName($link.Name).ExtendedProperty('System.AppUserModel.ID') } catch { $id = "unreadable: $($_.Exception.Message)" }
    Out-Result "  shortcut: $($link.FullName) -> $($s.TargetPath) $($s.Arguments) (in $($s.WorkingDirectory), icon $($s.IconLocation)); AppUserModelID: $id"
  }
  return $folder
}

Invoke-Step 'install' "Dot Popper's setup program: install, start, reinstall, uninstall" {
  if (-not $doInstall) { Set-Step 'SKIP' 'not chosen'; return }
  $notes = @()
  [void](Out-InstallState 'before')
  $r = Invoke-Child -Label 'setup' -FilePath $Setup.FullName -Arguments '/S' -TimeoutSeconds 180 -ShotsAt @(5)
  Out-Child $r
  $notes += "silent install: $($r.Result), exit $($r.Code), $($r.Seconds) s"
  $folder = Out-InstallState 'after the install'
  $installed = Join-Path $folder 'Dot Popper.exe'
  if (-not (Test-Path -LiteralPath $installed)) { Set-Step 'FAIL' (($notes + 'Dot Popper.exe not installed') -join '; '); return }
  Copy-Mesa $folder
  $link = @(Get-PopperShortcuts | Where-Object { $_.FullName -like "$([Environment]::GetFolderPath('Programs'))*" })[0]
  if ($link) {
    $saved = @{}
    $environment = @{ DOT_POPPER_AUTOPLAY = '1'; DOT_POPPER_SEED = '7'; DOT_POPPER_QUIT_AFTER = '10'; DOT_POPPER_SHOTS = $null }
    foreach ($name in $environment.Keys) { $saved[$name] = [Environment]::GetEnvironmentVariable($name); [Environment]::SetEnvironmentVariable($name, $environment[$name]) }
    try {
      $launched = Get-Date
      Start-Process -FilePath $link.FullName
      $game = $null
      for ($i = 0; $i -lt 60 -and -not $game; $i++) {
        Start-Sleep -Milliseconds 500
        $game = @(Get-Process -Name 'Dot Popper' -ErrorAction SilentlyContinue | Where-Object { $_.StartTime -ge $launched.AddSeconds(-1) })[0]
      }
      if ($game) {
        $handle = $game.Handle
        Out-Result "started from the Start menu shortcut: pid $($game.Id), $($game.Path)"
        Start-Sleep -Seconds 4
        $game.Refresh()
        Out-Result "window title: '$($game.MainWindowTitle)'; child processes: $((@(Get-Children $game.Id)) -join ', ')"
        Save-Screen 'install-shortcut-5s.jpg'
        if (-not $game.WaitForExit(40000)) { Stop-Tree $game; $notes += 'from the shortcut: still running after 45 s, killed' }
        else { $notes += "from the shortcut: exit $($game.ExitCode)" }
      } else { $notes += 'from the shortcut: no Dot Popper process appeared' }
    } finally {
      foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }
  } else { $notes += 'no Start menu shortcut found' }
  # Installing again while the installed game runs, at its title screen.
  $game = Start-Process -FilePath $installed -PassThru
  Start-Sleep -Seconds 3
  $r = Invoke-Child -Label 'setup-while-running' -FilePath $Setup.FullName -Arguments '/S' -TimeoutSeconds 120
  Out-Child $r
  $notes += "install while it runs: $($r.Result), exit $($r.Code); the game still running: $(-not $game.HasExited)"
  Stop-Tree $game
  $r = Invoke-Child -Label 'setup-again' -FilePath $Setup.FullName -Arguments '/S' -TimeoutSeconds 120
  Out-Child $r
  $notes += "install over itself: $($r.Result), exit $($r.Code)"
  [void](Out-InstallState 'after installing again')
  Remove-Mesa $folder
  $entry = @(Get-UninstallEntries)[0]
  $uninstaller = Join-Path $folder 'uninstall.exe'
  if ($entry) {
    $command = [string](Get-ItemProperty -LiteralPath $entry.PSPath).UninstallString
    if ($command -match '^"([^"]+)"') { $uninstaller = $Matches[1] } elseif ($command) { $uninstaller = $command }
  }
  $r = Invoke-Child -Label 'uninstall' -FilePath $uninstaller -Arguments '/S' -TimeoutSeconds 120
  Out-Child $r
  for ($i = 0; $i -lt 60 -and ((Test-Path -LiteralPath $folder) -or @(Get-UninstallEntries).Count); $i++) { Start-Sleep -Milliseconds 500 }
  [void](Out-InstallState 'after the uninstall')
  $left = @()
  if (Test-Path -LiteralPath $folder) { $left += 'the folder' }
  if (@(Get-UninstallEntries).Count) { $left += 'the uninstall key' }
  if (@(Get-PopperShortcuts).Count) { $left += 'a shortcut' }
  $notes += "silent uninstall: $($r.Result), exit $($r.Code); left behind: $(if ($left.Count) { $left -join ', ' } else { 'nothing' })"
  if ($left.Count) { Set-Step 'FAIL' ($notes -join '; ') } else { Set-Step 'PASS' ($notes -join '; ') }
}

Invoke-Step 'saves' 'Where the games saved' {
  Set-Step 'INFO' ''
  foreach ($folder in (Join-Path $env:APPDATA 'winkit'), (Join-Path $env:APPDATA 'dot_popper'), (Join-Path $env:LOCALAPPDATA 'winkit'), (Join-Path $env:LOCALAPPDATA 'dot_popper'), (Join-Path $env:APPDATA 'LOVE'), (Join-Path $env:APPDATA 'Lota')) {
    if (Test-Path -LiteralPath $folder) {
      Out-Lines $folder (Get-ChildItem -LiteralPath $folder -Force -Recurse | ForEach-Object { "{0,10} {1}" -f $_.Length, $_.FullName.Substring($folder.Length) })
    } else { Out-Result "$folder does not exist" }
  }
}

Invoke-Step 'events' "Windows' own records of crashes and of Defender, since the kit started" {
  Set-Step 'INFO' ''
  $since = $KitStart.AddMinutes(-1)
  $tenMinutes = (Get-Date).AddMinutes(-10)
  if ($tenMinutes -lt $since) { $since = $tenMinutes }
  Out-Result "since: $($since.ToString('s'))"
  $crashes = @()
  try {
    $crashes = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $since } -ErrorAction Stop |
        Where-Object { $_.ProviderName -in 'Application Error', 'Windows Error Reporting', 'Application Hang', '.NET Runtime' })
  } catch { Out-Result "application log: $($_.Exception.Message)" }
  foreach ($event in $crashes) { Out-Lines "$($event.TimeCreated.ToString('s')) $($event.ProviderName) $($event.Id)" $event.Message }
  $ours = @($crashes | Where-Object { $_.Message -match 'Winkit|Dot Popper|ruby|setup' })
  Out-Result "crash or hang events: $($crashes.Count), of them naming the kit's apps: $($ours.Count)"
  foreach ($log in 'Microsoft-Windows-Windows Defender/Operational', 'Microsoft-Windows-SmartScreen/Debug', 'Microsoft-Windows-CodeIntegrity/Operational') {
    try {
      $events = @(Get-WinEvent -FilterHashtable @{ LogName = $log; StartTime = $since } -ErrorAction Stop)
      Out-Result "${log}: $($events.Count) events"
      foreach ($event in @($events | Where-Object { $_.Level -le 3 -or $_.Message -match 'Winkit|Dot Popper' } | Select-Object -First 20)) {
        Out-Lines "$($event.TimeCreated.ToString('s')) $($event.Id)" $event.Message
      }
    } catch { Out-Result "${log}: $($_.Exception.Message)" }
  }
  try {
    $threats = @(Get-MpThreatDetection -ErrorAction Stop | Where-Object { $_.InitialDetectionTime -ge $since })
    Out-Result "defender detections since then: $($threats.Count)"
    foreach ($threat in $threats) { Out-Object 'detection' $threat }
  } catch { Out-Result "defender detections: unreadable ($($_.Exception.Message))" }
  if ($ours.Count) { Set-Step 'INFO' "$($ours.Count) crash or hang events name the kit's apps" }
}

# ---------------------------------------------------------------- summary

$Meaning = @{
  'PASS' = 'worked'; 'FAIL' = 'did not work, see results.txt'; 'SKIP' = 'skipped'; 'INFO' = 'recorded'
  'NO-GPU' = 'this computer refused the graphics the app asked for'
}

function Write-Summary {
  Out-Result ''
  Out-Result "=== SUMMARY [$(Get-Stamp)]"
  Write-Host ''
  Write-Host '================ Summary ================'
  foreach ($step in $Steps) {
    $line = '{0,-7} {1}: {2}' -f $step.Status, $step.Title, $Meaning[$step.Status]
    Out-Result "$line. $($step.Note)"
    Write-Host $line
  }
  if (@($Steps | Where-Object { $_.Status -eq 'NO-GPU' }).Count) {
    $text = 'On this computer the apps could not open a window with the graphics they need (no GPU, or no OpenGL 3.3 or Vulkan driver). The kit recorded the message and went on.'
    Out-Result $text
    Write-Host $text
  }
  Out-Result "screenshots taken: $script:Shots; finished $(Get-Stamp)"
}

function Save-Zip {
  if (Test-Path -LiteralPath $ResultsZip) { Remove-Item -LiteralPath $ResultsZip -Force }
  Compress-Archive -LiteralPath $ResultsDir -DestinationPath $ResultsZip
}

Write-Summary
try { Save-Zip } catch { Write-Host "Could not zip the results: $($_.Exception.Message)" }

$hold = $HoldSeconds
if ($hold -le 0 -and -not $Unattended) {
  Write-Host ''
  Write-Host 'Optional hands-on test (1 minute): a window opens for 60 seconds. In it, move the mouse, click,'
  Write-Host 'press a few keys, and, if you have a controller, press its buttons and move its sticks.'
  if (Ask 'Do the hands-on test now?') { $hold = 60 }
}
if ($hold -gt 0) {
  Invoke-Step 'hold' 'Hands-on: the input Winkit saw' {
    $r = Invoke-Child -Label 'hold' -FilePath $WinkitExe -Arguments "--hold=$hold" -ShotsAt @(5) -TimeoutSeconds ($hold + 30)
    Out-Child $r
    Copy-Frame 'hold'
    Test-Winkit $r
    if ($r.Out -match 'inputs seen: ([^\r\n]*)') { $script:StepNote = "$($script:StepNote); inputs seen: $($Matches[1])" }
  }
  Write-Summary
  try { Save-Zip } catch { Write-Host "Could not zip the results: $($_.Exception.Message)" }
}

Write-Host ''
Write-Host 'Done. You can use the computer again.'
Write-Host "Results folder: $ResultsDir"
if (Test-Path -LiteralPath $ResultsZip) {
  Write-Host "Please send this one file back: $ResultsZip"
  Write-Host '(and CHECKLIST.txt from the kit folder too, if you filled it in).'
  if (-not $Unattended) { try { Start-Process -FilePath 'explorer.exe' -ArgumentList "/select,`"$ResultsZip`"" } catch { } }
} else {
  Write-Host 'The zip could not be made: please zip the results folder above and send it.'
}
exit 0
