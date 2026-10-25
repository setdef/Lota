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

set(LOVE_DEPS ${LOTA_ROOT}/vendor/love-apple-dependencies CACHE PATH "love-apple-dependencies checkout")
set(LOVE_FRAMEWORKS ${LOVE_DEPS}/macOS/Frameworks)
set(SDL3_FRAMEWORKS ${LOVE_DEPS}/shared/Frameworks/SDL3.xcframework/macos-arm64_x86_64)
# For the extensions' rpaths (cmake/LotaExtension.cmake).
set(LOVE_FRAMEWORK_DIRS ${LOVE_FRAMEWORKS} ${SDL3_FRAMEWORKS} PARENT_SCOPE)

add_library(love_engine STATIC ${LOVE_ENGINE_SOURCES})

# Consumers see LÖVE's headers as system headers, so Lota's -Werror never
# fires on a warning in LÖVE's code.
set_target_properties(love_engine PROPERTIES SYSTEM ON)

target_include_directories(love_engine PUBLIC
	# The Xcode project's HEADER_SEARCH_PATHS
	# (platform/xcode/love.xcodeproj/project.pbxproj:576-580).
	${LOVE_DIR}/src
	${LOVE_DIR}/src/libraries
	${LOVE_DIR}/src/modules
	# vendor/love/CMakeLists.txt:1384, for <enet/enet.h>.
	${LOVE_DIR}/src/libraries/enet/libenet/include
	# LÖVE includes <ft2build.h> and <hb.h> without a framework prefix
	# (src/modules/font/freetype/Font.h:28, HarfbuzzShaper.cpp:27).
	${LOVE_FRAMEWORKS}/freetype.framework/Headers
	${LOVE_FRAMEWORKS}/harfbuzz.framework/Headers
)

# Framework include paths, for <SDL3/...>, <ogg/...>, <vorbis/...>,
# <theora/...>, <libmodplug/...>, and <OpenAL-Soft/...>.
target_compile_options(love_engine PUBLIC -F${LOVE_FRAMEWORKS} -F${SDL3_FRAMEWORKS})

target_compile_definitions(love_engine PUBLIC
	# The Xcode project's GCC_PREPROCESSOR_DEFINITIONS
	# (project.pbxproj:861); src/modules/audio/openal/*.h read it.
	LOVE_APPLE_USE_FRAMEWORKS
	# "required for enet" (vendor/love/CMakeLists.txt:175-176).
	HAS_SOCKLEN_T
)

target_compile_options(love_engine PRIVATE
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
target_link_options(love_engine INTERFACE -F${LOVE_FRAMEWORKS} -F${SDL3_FRAMEWORKS})

target_link_libraries(love_engine INTERFACE
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
