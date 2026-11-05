# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Checks what run-kit.ps1 left in a kit folder on a CI runner
# (.github/workflows/windows-kit.yml): one results folder whose
# results.txt holds every step's start and end and a summary,
# screenshots beside it, the zip, a hanging child stopped by its timeout,
# the download marks it was given read and removed, and, by mode, Winkit
# drawing (mesa) or reporting that it could not (nogpu). Not part of the
# kit. Exits 1 when any check fails.
#
#   check-results.ps1 -Kit FOLDER -Mode mesa|nogpu [-Installed] [-Held]

param(
  [Parameter(Mandatory = $true)] [string] $Kit,
  [Parameter(Mandatory = $true)] [ValidateSet('mesa', 'nogpu')] [string] $Mode,
  [switch] $Installed,
  [switch] $Held
)

$ErrorActionPreference = 'Stop'
$failed = 0
function Check([string] $Label, [bool] $Condition) {
  if ($Condition) { Write-Host "ok: $Label" } else { Write-Host "FAILED: $Label"; $script:failed++ }
}

$folders = @(Get-ChildItem -LiteralPath (Join-Path $Kit 'results') -Directory -Filter 'lota-kit-results-*')
Check 'one results folder' ($folders.Count -eq 1)
$folder = $folders[0].FullName
$file = Join-Path $folder 'results.txt'
$text = [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8)
Write-Host "results.txt: $((Get-Item -LiteralPath $file).Length) bytes"

$steps = 'motw', 'checksums', 'system', 'computerinfo', 'timeout', 'unpack', 'winkit', 'winkit-warm', 'winkit-rubyenv',
  'winkit-unicode', 'winkit-pacing', 'winkit-shell', 'winkit-cmd', 'winkit-close', 'winkit-kill', 'winkit-links', 'winkit-summary',
  'dotpopper', 'dotpopper-noshaders', 'install', 'saves', 'events'
if ($Held) { $steps += 'hold' }
$status = @{}
foreach ($step in $steps) {
  $begin = $text.Contains("=== STEP ${step}: ")
  $end = [regex]::Match($text, "(?m)^=== END ${step}: (\S+)")
  Check "step $step started and ended" ($begin -and $end.Success)
  if ($end.Success) { $status[$step] = $end.Groups[1].Value; Write-Host "  $step -> $($status[$step])" }
}
Check 'a summary' ($text -match '(?m)^=== SUMMARY')
$failedSteps = @($status.Keys | Where-Object { $status[$_] -eq 'FAIL' })
Check "no step failed ($($failedSteps -join ', '))" ($failedSteps.Count -eq 0)
Check 'no step failed with an exception' (-not ($text -match '(?m)^where: '))

Check 'the timeout stopped the hanging child' ($status['timeout'] -eq 'PASS' -and $text -match 'result: timeout after 3 s, killed; exit status .*; gone afterwards: True')
Check 'the download marks were read before unblocking' ($text -match 'run-kit\.ps1: ZoneId=3' -and $text -match 'unblocked: \d+ files')
Check 'no kit file still carries a mark' (@(Get-ChildItem -LiteralPath $Kit -File | Where-Object { Get-Item -LiteralPath $_.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue }).Count -eq 0)
Check 'the checksums match' ($status['checksums'] -eq 'PASS')
Check 'system facts' ($text -match '(?m)^windows: ' -and $text -match '(?m)^gpu: ' -and $text -match '(?m)^powershell: ')
Check 'Get-ComputerInfo ran' ($text -match 'WindowsBuildLabEx|OsName')

$shots = @(Get-ChildItem -LiteralPath $folder -Filter '*.jpg')
Write-Host "screenshots: $($shots.Count): $(($shots | ForEach-Object { $_.Name }) -join ', ')"
$least = 1
if ($Mode -eq 'mesa') { $least = 8 }
Check "at least $least screenshots of the screen" ($shots.Count -ge $least)
Check 'screenshots are images' (@($shots | Where-Object { $_.Length -lt 1000 }).Count -eq 0)
$zip = Join-Path (Join-Path $Kit 'results') "$($folders[0].Name).zip"
Check 'the results zip' ((Test-Path -LiteralPath $zip) -and (Get-Item -LiteralPath $zip).Length -gt 10000)

if ($Mode -eq 'mesa') {
  foreach ($step in 'winkit', 'winkit-warm', 'winkit-rubyenv', 'winkit-unicode', 'winkit-pacing', 'winkit-shell', 'winkit-cmd', 'winkit-close', 'winkit-links') {
    Check "$step drew and read its frame back" ($status[$step] -eq 'PASS')
  }
  Check 'winkit drew with llvmpipe' ($text -match 'renderer: OpenGL [^\r\n]*llvmpipe')
  Check 'its own frames were kept' (@(Get-ChildItem -LiteralPath $folder -Filter '*-frame.png').Count -ge 5)
  Check 'the shaders compiled, and the broken one did not' ($text -match 'shader vertex and pixel: compiled' -and $text -match 'shader broken, on purpose: RuntimeError')
  Check 'frame times' ($text -match 'frames: \d+ after the first half second, ms average=')
  Check 'dot popper played and quit with 0' ($status['dotpopper'] -eq 'PASS' -and $status['dotpopper-noshaders'] -eq 'PASS')
  Check "dot popper's rounds.csv" ($text -match '--- rounds\.csv')
  Check "dot popper's frame pacing lines (DOT_POPPER_PERF)" ($text -match 'Dot Popper: \d+ frames a second, longest frame' -and $text -match 'frame pacing every 5 s: ')
  Check "dot popper's own screenshots" (@(Get-ChildItem -LiteralPath $folder -Filter 'dotpopper-shot-*.png').Count -ge 1)
} else {
  Check 'winkit reported no GPU' ($status['winkit'] -eq 'NO-GPU' -and $text -match 'window: refused' -and $text -match 'Unable to create renderer')
  Check 'the summary says so in plain words' ($text -match 'could not open a window with the graphics they need')
  Check "dot popper's error dialog was read and closed" ($status['dotpopper'] -eq 'NO-GPU' -and $text -match "error dialog 'Initialization error', killed")
}
if ($Installed) {
  Check 'the installer installed, ran, and uninstalled' ($status['install'] -eq 'PASS')
} else {
  Check 'the installer was skipped' ($status['install'] -eq 'SKIP')
}
if ($Held) { Check 'the hands-on test ran' ($status['hold'] -in 'PASS', 'NO-GPU' -and $text -match 'inputs seen: ') }

Write-Host "$failed checks failed"
exit ([int]($failed -gt 0))
