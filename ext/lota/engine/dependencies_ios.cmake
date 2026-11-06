# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# LÖVE's dependencies on iOS and iPadOS, as LÖVE's own iOS build links
# them: the static libraries love-apple-dependencies builds for iOS
# (iOS/libraries/*.xcframework, the liblove-ios target's frameworks,
# vendor/love/platform/xcode/liblove.xcodeproj/project.pbxproj:2340-2347),
# SDL3, and the system's frameworks, among them Apple's OpenAL, which the
# love-ios target links (love.xcodeproj/project.pbxproj:187) in place of
# OpenAL Soft. Included by CMakeLists.txt beside this file, once
# lota_engine exists. Apple's OpenAL follows LÖVE and links no LGPL code
# statically; whether Lota keeps it is the maintainer's decision (Plan
# 002, Open questions, "Phones").
#
# Nothing here is linked into a binary: an iOS app has no loadable
# extensions, so the engine and the extension are static archives, and
# the app links them with everything below (Fledge, from the archives and
# flags extconf.rb names). So the archives and flags are also written to
# ${CMAKE_BINARY_DIR}/phone_link.txt, one to a line, for extconf.rb.

set(ENGINE_DEPS_DIR ${LOTA_ROOT}/vendor/love-apple-dependencies CACHE PATH "love-apple-dependencies checkout")
# love-apple-dependencies' SDL3.xcframework holds SDL as a dynamic
# framework, which an app embeds; Fledge links an extension's libraries
# statically into the app's executable, so SDL3 is built static from
# LÖVE's version, 3.4.10, for each slice (tasks/ios_build.rb).
set(LOTA_IOS_SDL3_DIR "" CACHE PATH "SDL3 built static for this slice: include/ and lib/libSDL3.a")
if(NOT EXISTS ${LOTA_IOS_SDL3_DIR}/lib/libSDL3.a)
	message(FATAL_ERROR "LOTA_IOS_SDL3_DIR (${LOTA_IOS_SDL3_DIR}) holds no lib/libSDL3.a; "
		"build SDL3 for this slice with `rake ios:sdl3`")
endif()

# CMake's iOS support picks the Simulator or a device by the SDK
# (cmake-toolchains(7), "Cross Compiling for iOS").
if(CMAKE_OSX_SYSROOT MATCHES "[Ss]imulator")
	set(slice_pattern "ios-*-simulator")
	set(LOTA_IOS_SIMULATOR ON)
else()
	set(slice_pattern "ios-arm64*")
	set(LOTA_IOS_SIMULATOR OFF)
endif()

# Each XCFramework's slice for this SDK. love-apple-dependencies' slices
# are fat (arm64 with armv7, or with x86_64 and i386 for the Simulator),
# and an app's slice holds one architecture, so each archive is thinned to
# arm64 when CMake configures.
set(thin_dir ${CMAKE_BINARY_DIR}/ios-libraries)
file(MAKE_DIRECTORY ${thin_dir})
set(LOTA_IOS_ARCHIVES)
foreach(library IN ITEMS freetype harfbuzz modplug theora vorbis ogg)
	file(GLOB slices LIST_DIRECTORIES true ${ENGINE_DEPS_DIR}/iOS/libraries/${library}.xcframework/${slice_pattern})
	if(NOT LOTA_IOS_SIMULATOR)
		list(FILTER slices EXCLUDE REGEX "-simulator$")
	endif()
	list(LENGTH slices count)
	if(NOT count EQUAL 1)
		message(FATAL_ERROR "${library}.xcframework has ${count} slices for ${CMAKE_OSX_SYSROOT}: ${slices}")
	endif()
	file(GLOB archive ${slices}/*.a)
	get_filename_component(name ${archive} NAME)
	set(thin ${thin_dir}/${name})
	execute_process(COMMAND lipo -archs ${archive} OUTPUT_VARIABLE archs OUTPUT_STRIP_TRAILING_WHITESPACE)
	if(archs STREQUAL "arm64")
		# Already thin, as harfbuzz's device slice is; lipo -thin refuses it.
		execute_process(COMMAND ${CMAKE_COMMAND} -E copy ${archive} ${thin} RESULT_VARIABLE lipo_result
			ERROR_VARIABLE lipo_error)
	else()
		execute_process(COMMAND lipo ${archive} -thin arm64 -output ${thin} RESULT_VARIABLE lipo_result
			ERROR_VARIABLE lipo_error)
	endif()
	if(NOT lipo_result EQUAL 0)
		message(FATAL_ERROR "lipo could not thin ${archive} to arm64: ${lipo_error}")
	endif()
	set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${archive})
	target_include_directories(lota_engine PUBLIC ${slices}/Headers)
	list(APPEND LOTA_IOS_ARCHIVES ${thin})
endforeach()
list(APPEND LOTA_IOS_ARCHIVES ${LOTA_IOS_SDL3_DIR}/lib/libSDL3.a)
target_include_directories(lota_engine PUBLIC ${LOTA_IOS_SDL3_DIR}/include)

target_compile_definitions(lota_engine PUBLIC
	# The Xcode project's GCC_PREPROCESSOR_DEFINITIONS
	# (liblove.xcodeproj/project.pbxproj:5587); with LOVE_IOS,
	# src/modules/audio/openal/*.h include Apple's <OpenAL/al.h>.
	LOVE_APPLE_USE_FRAMEWORKS
)

target_compile_options(lota_engine PRIVATE
	# As on macOS (dependencies_macos.cmake): LÖVE's Objective-C relies on
	# ARC, which the Xcode project enables for every file.
	$<$<COMPILE_LANGUAGE:OBJC,OBJCXX>:-fobjc-arc>
)

# The system's frameworks: the love-ios target's
# (love.xcodeproj/project.pbxproj:160-187), with SDL3's own, which its
# sdl3.pc names, and LÖVE's engine's (vendor/love/CMakeLists.txt:298-318,
# 676-680, 1729-1736). GameController and CoreHaptics are weak, as LÖVE
# and SDL link them. libbz2 is for love-apple-dependencies' FreeType,
# whose ftbzip2.o calls BZ2_bzDecompress, and which the love-ios target
# links (love.xcodeproj/project.pbxproj:27). libobjc is not named: the
# app's link already has it, and ld warns of a duplicate.
set(LOTA_IOS_FLAGS
	-lz
	-lbz2
	-lc++
	-Wl,-framework,Foundation
	-Wl,-framework,CoreFoundation
	-Wl,-framework,UIKit
	-Wl,-framework,QuartzCore
	-Wl,-framework,Metal
	-Wl,-framework,OpenGLES
	-Wl,-framework,CoreGraphics
	-Wl,-framework,OpenAL
	-Wl,-framework,AudioToolbox
	-Wl,-framework,AVFoundation
	-Wl,-framework,CoreAudio
	-Wl,-framework,CoreMedia
	-Wl,-framework,CoreVideo
	-Wl,-framework,CoreMotion
	-Wl,-framework,CoreBluetooth
	-Wl,-weak_framework,GameController
	-Wl,-weak_framework,CoreHaptics
)
target_link_libraries(lota_engine INTERFACE ${LOTA_IOS_ARCHIVES} ${LOTA_IOS_FLAGS})
list(JOIN LOTA_IOS_ARCHIVES "\n" archives)
list(JOIN LOTA_IOS_FLAGS "\n" flags)
file(WRITE ${CMAKE_BINARY_DIR}/phone_link.txt "${archives}\n${flags}\n")
