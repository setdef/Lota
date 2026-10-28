# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# LÖVE's dependencies on Linux: the shared libraries love-appimage-source
# builds from source, as LÖVE's own Linux CI builds them
# (vendor/love/.github/workflows/main.yml, the Linux job), into its
# installdir, where `rake dependencies` puts them (tasks/dependencies.rb).
# Included by CMakeLists.txt beside this file, once lota_engine exists.

set(ENGINE_DEPS_DIR ${LOTA_ROOT}/tmp/dependencies/installdir CACHE PATH
	"love-appimage-source's installdir, holding LÖVE's dependencies")
if(NOT EXISTS ${ENGINE_DEPS_DIR}/lib/libSDL3.so)
	message(FATAL_ERROR "${ENGINE_DEPS_DIR} holds no lib/libSDL3.so; "
		"run `bundle exec rake dependencies`, which builds LÖVE's Linux dependencies there")
endif()
# For the extensions' rpaths (cmake/LotaExtension.cmake).
set(ENGINE_LIBRARY_DIRS ${ENGINE_DEPS_DIR}/lib PARENT_SCOPE)

target_include_directories(lota_engine PUBLIC
	# <SDL3/...>, <ogg/...>, <vorbis/...>, <theora/...>, <libmodplug/...>,
	# and <zlib.h>.
	${ENGINE_DEPS_DIR}/include
	# LÖVE includes OpenAL Soft's headers without a prefix off Apple
	# (src/modules/audio/openal/Audio.h:44-56), and <ft2build.h> and <hb.h>
	# without one everywhere (src/modules/font/freetype/Font.h:28,
	# HarfbuzzShaper.cpp:27), as LÖVE's find modules point at these
	# directories (extra/cmake/FindHarfbuzz.cmake, and CMake's own FindOpenAL
	# and FindFreetype).
	${ENGINE_DEPS_DIR}/include/AL
	${ENGINE_DEPS_DIR}/include/freetype2
	${ENGINE_DEPS_DIR}/include/harfbuzz
)

# LÖVE's own Linux build links each library as a shared library apart
# (vendor/love/CMakeLists.txt:168-224), and so does Lota: OpenAL Soft
# among them, so a player can replace it, as its license, the GNU Library
# General Public License, allows; the precompiled gem carries each one with
# its license, and OpenAL Soft with its source (ext/lota/licenses.rb).
# Each extension's rpath finds them at load time (cmake/LotaExtension.cmake).
find_package(Threads REQUIRED)
target_link_libraries(lota_engine INTERFACE
	${ENGINE_DEPS_DIR}/lib/libSDL3.so
	${ENGINE_DEPS_DIR}/lib/libfreetype.so
	${ENGINE_DEPS_DIR}/lib/libharfbuzz.so
	${ENGINE_DEPS_DIR}/lib/libopenal.so
	${ENGINE_DEPS_DIR}/lib/libmodplug.so
	${ENGINE_DEPS_DIR}/lib/libtheoradec.so
	${ENGINE_DEPS_DIR}/lib/libvorbisfile.so
	${ENGINE_DEPS_DIR}/lib/libvorbis.so
	${ENGINE_DEPS_DIR}/lib/libogg.so
	${ENGINE_DEPS_DIR}/lib/libz.so
	Threads::Threads
	${CMAKE_DL_LIBS}
)
