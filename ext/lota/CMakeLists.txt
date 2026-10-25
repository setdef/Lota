# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Lota's native build: LÖVE's engine as a static library (engine/), and,
# beside it, the Ruby extension Lota::Native that links it (native/).
#
# extconf.rb configures this project and writes a Makefile that builds it,
# so `rake compile` (rake-compiler) and `gem install` build it the same way.
# It passes what only Ruby knows: which Ruby, and where the Rice headers are.
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
set(ENGINE_SOURCE_DIR ${LOTA_ROOT}/vendor/love CACHE PATH "LÖVE source checkout")

# rake test:native builds a second tree with LOTA_SANITIZE on. It instruments
# everything in that tree, LÖVE's engine included, so a release or a read in
# love::Object's own code (src/common/Object.cpp) is checked too.
option(LOTA_SANITIZE "Build with AddressSanitizer and UndefinedBehaviorSanitizer" OFF)
if(LOTA_SANITIZE)
	set(LOTA_SANITIZER_FLAGS
		-fsanitize=address,undefined
		# A sanitizer report ends the process, so a test cannot pass after one.
		-fno-sanitize-recover=all
		-fno-omit-frame-pointer
		# Ruby's garbage collector finds live objects by scanning the machine
		# stack. ASan's use-after-return detection moves locals to a heap
		# "fake stack" the collector never scans, so a Ruby object held only
		# in a local would be collected while still in use.
		-fsanitize-address-use-after-return=never)
	add_compile_options(${LOTA_SANITIZER_FLAGS})
	add_link_options(-fsanitize=address,undefined)
endif()

# The test-only extension (native_test/), for rake test; never packaged.
option(LOTA_NATIVE_TEST "Build the test-only extension in native_test/" OFF)

include(cmake/LotaWarnings.cmake)
add_subdirectory(engine)

include(cmake/LotaExtension.cmake)
add_subdirectory(native)
if(LOTA_NATIVE_TEST)
	add_subdirectory(native_test)
endif()
