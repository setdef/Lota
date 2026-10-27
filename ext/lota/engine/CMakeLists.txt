# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# LÖVE's engine as one static library, without its Lua layer (ADR 001,
# section 1). LÖVE's own CMakeLists.txt cannot build it: each module target
# lists its wrap_*.cpp files, so none links without Lua. The sources come
# from a list `rake engine:sources` generates from LÖVE's CMakeLists.txt.

if(NOT APPLE)
	message(FATAL_ERROR "Lota builds its engine on macOS only so far; "
		"rake engine:sources generates the source list for the host it runs on.")
endif()

include(${CMAKE_CURRENT_SOURCE_DIR}/sources_macos.cmake)

set(ENGINE_DEPS_DIR ${LOTA_ROOT}/vendor/love-apple-dependencies CACHE PATH "love-apple-dependencies checkout")
set(ENGINE_FRAMEWORKS ${ENGINE_DEPS_DIR}/macOS/Frameworks)
set(SDL3_FRAMEWORKS ${ENGINE_DEPS_DIR}/shared/Frameworks/SDL3.xcframework/macos-arm64_x86_64)
# For the extensions' rpaths (cmake/LotaExtension.cmake).
set(ENGINE_FRAMEWORK_DIRS ${ENGINE_FRAMEWORKS} ${SDL3_FRAMEWORKS} PARENT_SCOPE)

add_library(lota_engine STATIC ${ENGINE_SOURCES})

# A game that is not fused saves in a Lota folder where LÖVE's saves in a
# LOVE one (appdata_folder.h says how, and why not by a definition here).
set_source_files_properties(${ENGINE_SOURCE_DIR}/src/modules/filesystem/physfs/Filesystem.cpp PROPERTIES
	COMPILE_OPTIONS "-include;${CMAKE_CURRENT_SOURCE_DIR}/appdata_folder.h")

# Consumers see LÖVE's headers as system headers, so Lota's -Werror never
# fires on a warning in LÖVE's code.
set_target_properties(lota_engine PROPERTIES SYSTEM ON)

target_include_directories(lota_engine PUBLIC
	# The Xcode project's HEADER_SEARCH_PATHS
	# (platform/xcode/love.xcodeproj/project.pbxproj:576-580).
	${ENGINE_SOURCE_DIR}/src
	${ENGINE_SOURCE_DIR}/src/libraries
	${ENGINE_SOURCE_DIR}/src/modules
	# vendor/love/CMakeLists.txt:1384, for <enet/enet.h>.
	${ENGINE_SOURCE_DIR}/src/libraries/enet/libenet/include
	# LÖVE includes <ft2build.h> and <hb.h> without a framework prefix
	# (src/modules/font/freetype/Font.h:28, HarfbuzzShaper.cpp:27).
	${ENGINE_FRAMEWORKS}/freetype.framework/Headers
	${ENGINE_FRAMEWORKS}/harfbuzz.framework/Headers
)

# Framework include paths, for <SDL3/...>, <ogg/...>, <vorbis/...>,
# <theora/...>, <libmodplug/...>, and <OpenAL-Soft/...>.
target_compile_options(lota_engine PUBLIC -F${ENGINE_FRAMEWORKS} -F${SDL3_FRAMEWORKS})

target_compile_definitions(lota_engine PUBLIC
	# The Xcode project's GCC_PREPROCESSOR_DEFINITIONS
	# (project.pbxproj:861); src/modules/audio/openal/*.h read it.
	LOVE_APPLE_USE_FRAMEWORKS
	# "required for enet" (vendor/love/CMakeLists.txt:175-176).
	HAS_SOCKLEN_T
)

target_compile_options(lota_engine PRIVATE
	# LÖVE's warnings are LÖVE's to fix, upstream (ADR 001, section 1).
	-w
	# LÖVE's Objective-C relies on ARC: the Xcode project enables it for
	# every file (CLANG_ENABLE_OBJC_ARC = YES, project.pbxproj:530), while
	# LÖVE's CMakeLists.txt passes -fobjc-arc only to luahttps (line 1653).
	# LÖVE's Objective-C never sends retain or release (it hands objects to
	# ARC with CFBridgingRelease, src/modules/graphics/metal/Graphics.mm:436),
	# so without ARC every object it creates would leak.
	$<$<COMPILE_LANGUAGE:OBJC,OBJCXX>:-fobjc-arc>
)

# Where to find the frameworks at link time. Where to find them at load time
# is each extension's rpath (cmake/LotaExtension.cmake), relative to where
# the extension is loaded from.
target_link_options(lota_engine INTERFACE -F${ENGINE_FRAMEWORKS} -F${SDL3_FRAMEWORKS})

# OpenAL Soft is a framework of its own, linked as LÖVE's macOS build
# links it, so a player can replace it, as its license, the GNU Library
# General Public License, allows; the precompiled gem carries it with its
# source (ext/lota/licenses.rb).
target_link_libraries(lota_engine INTERFACE
	"-framework SDL3"
	"-framework freetype"
	"-framework harfbuzz"
	"-framework OpenAL-Soft"
	"-framework libmodplug"
	"-framework theora"
	"-framework vorbis"
	"-framework ogg"
	z
	objc
	"-framework CoreFoundation"
	"-framework AppKit"
	"-framework Metal"
	"-framework QuartzCore"
	"-framework IOKit"
	"-framework Foundation"
)
