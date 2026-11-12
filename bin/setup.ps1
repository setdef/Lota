# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Lota's development tools on Windows, from the pins in mise.toml, as
# bin/setup does on Linux and macOS. Run it from PowerShell in the
# checkout. Every step does nothing when it is already satisfied, so it is
# quick to run again, and under CI=true it never prompts.
#
# It needs mise (https://mise.jdx.dev), which it does not install. It
# installs RubyInstaller's Ruby with winget, at mise.toml's version, since
# mise cannot build Ruby on Windows; the tools the Windows checks use
# through mise (Python and the REUSE tool; CMake and Ninja come from
# MSYS2); and the MSYS2 packages of RubyInstaller's devkit that .github/windows_prepush.sh
# builds with. The gate (bundle exec rake) does not run on Windows
# (doc/contributors/windows.md), so it installs no bundle.
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not (Get-Command mise -ErrorAction SilentlyContinue)) {
  Write-Error "mise isn't installed. Please install it to continue: https://mise.jdx.dev"
  exit 1
}

# LÖVE's engine (vendor/love) and the libraries it builds against.
git submodule update --init

# The Ruby version comes from mise.toml, so there is one pin.
$rubyVersion = (Select-String -Path mise.toml -Pattern '^ruby\s*=\s*"([^"]+)"').Matches.Groups[1].Value
$rubyMajorMinor = ($rubyVersion -split '\.')[0..1] -join '.'

# RubyInstaller's Ruby is built with MinGW and carries the MSYS2 devkit,
# which Lota's native extension has to match (ADR 011).
if (-not (Get-Command ruby -ErrorAction SilentlyContinue) -or -not ((ruby --version) -match [regex]::Escape($rubyMajorMinor))) {
  Write-Host "Ruby $rubyMajorMinor is required but not installed."
  # Under CI=true nothing may prompt or ask for administrator rights.
  if ($env:CI -eq "true") {
    Write-Error "RubyInstaller's Ruby $rubyMajorMinor (RubyInstallerTeam.RubyWithDevKit.$rubyMajorMinor in winget) is not installed; install it, then run bin/setup.ps1 again."
    exit 1
  }
  $answer = Read-Host "Install it now via RubyInstaller (winget)? This may require administrator privileges. [Y/n]"
  if ($answer -and $answer -notmatch '^[Yy]') {
    Write-Error "Cannot continue without Ruby."
    exit 1
  }
  winget install --id "RubyInstallerTeam.RubyWithDevKit.$rubyMajorMinor" --accept-source-agreements --accept-package-agreements
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# mise.toml gives Windows only Python, uv, and the REUSE tool: its other
# tools carry an os option that leaves Windows out.
mise install
mise x -- reuse --version

# RubyInstaller's devkit is an MSYS2; the Windows checks build in its
# UCRT64 environment (doc/contributors/windows.md).
$msys = (ruby -e 'print RubyInstaller::Runtime.msys2_installation.msys_path rescue nil')
$packages = @("patch", "make", "mingw-w64-ucrt-x86_64-gcc", "mingw-w64-ucrt-x86_64-cmake", "mingw-w64-ucrt-x86_64-ninja", "mingw-w64-ucrt-x86_64-ccache")
if ($msys -and (Test-Path "$msys\usr\bin\pacman.exe")) {
  & "$msys\usr\bin\pacman.exe" -S --needed --noconfirm @packages
} else {
  Write-Warning "No MSYS2 found beside Ruby. Install these packages in MSYS2 (pacman -S --needed): $($packages -join ' ')"
}

Write-Host "Done. Run the Windows checks from a UCRT64 shell with: bash .github/windows_prepush.sh"
