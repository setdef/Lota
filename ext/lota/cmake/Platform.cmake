# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Settings that have to reach CMake before project(), which probes the
# compilers with them. Include this file first.

# Every love-apple-dependencies binary is built for macOS 11.0 (LC_BUILD_VERSION
# minos 11.0), and this SDK's libc++ warns below 11.0, although LÖVE's Xcode
# project says 10.15 (vendor/love/platform/xcode/love.xcodeproj/project.pbxproj:584).
set(CMAKE_OSX_DEPLOYMENT_TARGET 11.0 CACHE STRING "Minimum macOS version")

# Since CMake 4.0, an empty sysroot leaves the SDK to Apple's compiler
# driver, so compile_commands.json names none. clang-tidy is not Apple's
# compiler and finds no SDK headers without one (rake cpp:tidy).
set(CMAKE_OSX_SYSROOT macosx CACHE STRING "macOS SDK")
