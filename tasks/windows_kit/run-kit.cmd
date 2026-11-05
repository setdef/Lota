@echo off
rem SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
rem SPDX-License-Identifier: AGPL-3.0-or-later
rem
rem Starts the Windows kit: Windows PowerShell runs run-kit.ps1 with the
rem execution policy bypassed for that one process only. No setting of
rem the computer changes. Arguments go on to run-kit.ps1 (CI only).
setlocal
title Lota Windows kit
if exist "%~dp0run-kit.ps1" goto run
echo The kit's files are not next to this one.
echo Please unzip the whole kit first: right-click the .zip file, choose
echo "Extract All...", open the folder that makes, and double-click
echo run-kit.cmd there.
echo.
pause
exit /b 1

:run
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-kit.ps1" %*
set status=%errorlevel%
echo.
if not defined LOTA_KIT_NO_PAUSE pause
exit /b %status%
