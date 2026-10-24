# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Lota's native build: LÖVE's engine as a static library (engine/), and,
# beside it, the Ruby extension that links it.
#
#   cmake -S ext/lota -B tmp/engine/build -G Ninja
#   cmake --build tmp/engine/build
#
# `rake engine` runs both.
cmake_minimum_required(VERSION 3.25)

include(cmake/Platform.cmake)
project(lota C CXX OBJC OBJCXX)

# As LÖVE's CMakeLists.txt sets them (vendor/love/CMakeLists.txt:31-32); a
# Ruby extension is a shared library, so it needs position-independent code.
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE TRUE)

# clang-tidy reads compile_commands.json (rake cpp:tidy).
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT CMAKE_BUILD_TYPE)
	set(CMAKE_BUILD_TYPE Release)
endif()

# Normalized, so no path CMake writes (compile_commands.json among them)
# climbs back out of ext/ with "..".
get_filename_component(LOTA_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../.. ABSOLUTE)
set(LOVE_DIR ${LOTA_ROOT}/vendor/love CACHE PATH "LÖVE source checkout")

include(cmake/LotaWarnings.cmake)
add_subdirectory(engine)
