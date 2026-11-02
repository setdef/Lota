# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# A stand-in for megasource's SDL3 target, which LÖVE's Windows install
# rules name (vendor/love/CMakeLists.txt:2053), so CMake can evaluate
# LÖVE's tree on Windows without megasource (tasks/engine_sources.rb).
if(NOT TARGET lota_sdl3_stand_in)
	add_library(lota_sdl3_stand_in SHARED IMPORTED GLOBAL)
	set_target_properties(lota_sdl3_stand_in PROPERTIES
		IMPORTED_LOCATION ${CMAKE_BINARY_DIR}/SDL3.dll
		IMPORTED_IMPLIB ${CMAKE_BINARY_DIR}/libSDL3.dll.a)
endif()
