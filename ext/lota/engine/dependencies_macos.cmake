# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# LÖVE's dependencies on macOS: the frameworks love-apple-dependencies
# builds, as LÖVE's Xcode project links them. Included by CMakeLists.txt
# beside this file, once lota_engine exists.

set(ENGINE_DEPS_DIR ${LOTA_ROOT}/vendor/love-apple-dependencies CACHE PATH "love-apple-dependencies checkout")
set(ENGINE_FRAMEWORKS ${ENGINE_DEPS_DIR}/macOS/Frameworks)
set(SDL3_FRAMEWORKS ${ENGINE_DEPS_DIR}/shared/Frameworks/SDL3.xcframework/macos-arm64_x86_64)
# For the extensions' rpaths (cmake/LotaExtension.cmake).
set(ENGINE_LIBRARY_DIRS ${ENGINE_FRAMEWORKS} ${SDL3_FRAMEWORKS} PARENT_SCOPE)

target_include_directories(lota_engine PUBLIC
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
)

target_compile_options(lota_engine PRIVATE
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
