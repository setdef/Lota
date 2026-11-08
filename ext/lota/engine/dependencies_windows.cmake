# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# LÖVE's dependencies on Windows, with MinGW (ADR 002, section 4): the
# libraries tasks/windows_build.rb builds from source into its installdir,
# where `rake dependencies` puts them. Included by CMakeLists.txt beside
# this file, once lota_engine exists.

set(ENGINE_DEPS_DIR ${LOTA_ROOT}/tmp/dependencies/installdir CACHE PATH
	"tasks/windows_build.rb's installdir, holding LÖVE's dependencies")
if(NOT EXISTS ${ENGINE_DEPS_DIR}/lib/libSDL3.a)
	message(FATAL_ERROR "${ENGINE_DEPS_DIR} holds no lib/libSDL3.a; "
		"run `bundle exec rake dependencies`, which builds LÖVE's Windows dependencies there")
endif()
# Windows has no rpath. The one DLL the extension links, OpenAL Soft's, is
# loaded by its absolute path before the extension is (preload/), from
# lib/lota/libraries, where the build copies it.
set(ENGINE_LIBRARY_DIRS ${ENGINE_DEPS_DIR}/bin PARENT_SCOPE)
set(ENGINE_RUNTIME_LIBRARIES ${ENGINE_DEPS_DIR}/bin/OpenAL32.dll PARENT_SCOPE)

target_include_directories(lota_engine PUBLIC
	# <SDL3/...>, <ogg/...>, <vorbis/...>, <theora/...>, <libmodplug/...>,
	# and <zlib.h>.
	${ENGINE_DEPS_DIR}/include
	# OpenAL Soft's, FreeType's, and HarfBuzz's headers without a prefix,
	# as on Linux (dependencies_linux.cmake).
	${ENGINE_DEPS_DIR}/include/AL
	${ENGINE_DEPS_DIR}/include/freetype2
	${ENGINE_DEPS_DIR}/include/harfbuzz
)

target_compile_definitions(lota_engine PUBLIC
	# libmodplug's header declares its functions imported from a DLL on
	# Windows unless told the library is static (src/modplug.h:14-21).
	MODPLUG_STATIC
)

# SDL's static library, with the Windows libraries it needs, as SDL's own
# CMake package names them.
find_package(SDL3 CONFIG REQUIRED COMPONENTS SDL3-static PATHS ${ENGINE_DEPS_DIR} NO_DEFAULT_PATH)

# Every library but OpenAL Soft is static, as megasource links LÖVE's
# Windows build (tasks/windows_build.rb), each archive before those it
# needs, since GNU ld reads archives once, in order. OpenAL Soft is a DLL,
# so a player can replace it, as its license, the GNU Library General
# Public License, allows; the precompiled gem carries it with its source
# (ext/lota/licenses.rb).
find_package(Threads REQUIRED)
target_link_libraries(lota_engine INTERFACE
	${ENGINE_DEPS_DIR}/lib/libharfbuzz.a
	${ENGINE_DEPS_DIR}/lib/libfreetype.a
	${ENGINE_DEPS_DIR}/lib/libOpenAL32.dll.a
	${ENGINE_DEPS_DIR}/lib/libmodplug.a
	${ENGINE_DEPS_DIR}/lib/libtheoradec.a
	${ENGINE_DEPS_DIR}/lib/libvorbisfile.a
	${ENGINE_DEPS_DIR}/lib/libvorbis.a
	${ENGINE_DEPS_DIR}/lib/libogg.a
	${ENGINE_DEPS_DIR}/lib/libzlibstatic.a
	SDL3::SDL3-static
	# What LÖVE's own Windows build links liblove with
	# (vendor/love/CMakeLists.txt:1987-1992), and enet's winmm (line 1385).
	ws2_32
	winmm
	dwmapi
	Threads::Threads
)
