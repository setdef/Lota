# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# LÖVE's dependencies in an Android app, as LÖVE's own Android build
# (love2d/love-android, with megasource) links them: zlib, libogg,
# libvorbis, libtheora, FreeType, HarfBuzz, and libmodplug static, from
# tasks/android_build.rb's tree for the ABI, and SDL3 and OpenAL Soft as
# the shared libraries libSDL3.so and libopenal.so, which love-android's
# GameActivity loads by name and which Fledge copies into the app beside
# libfledgeext.so (its ADR 025, section 2). OpenAL Soft stays a library
# apart, so a player can replace it, as its license, the GNU Library
# General Public License, allows. Included by CMakeLists.txt beside this
# file, once lota_engine exists.
#
# Nothing here is linked into a binary: Fledge links the extension's
# archives, with everything below, into the app's libfledgeext.so. So the
# archives and flags are also written to ${CMAKE_BINARY_DIR}/phone_link.txt,
# one to a line, for phone/android.rb, as dependencies_ios.cmake writes
# them for iOS.

set(LOTA_ANDROID_DEPS_DIR "" CACHE PATH "LÖVE's dependencies for this ABI (rake android:deps): include/ and lib/")
set(LOTA_ANDROID_SDL3_DIR "" CACHE PATH "SDL3 built shared for this ABI: include/ and lib/libSDL3.so")
if(NOT EXISTS ${LOTA_ANDROID_DEPS_DIR}/lib/libopenal.so)
	message(FATAL_ERROR "LOTA_ANDROID_DEPS_DIR (${LOTA_ANDROID_DEPS_DIR}) holds no lib/libopenal.so; "
		"build LÖVE's dependencies for Android with `rake android:deps`")
endif()
if(NOT EXISTS ${LOTA_ANDROID_SDL3_DIR}/lib/libSDL3.so)
	message(FATAL_ERROR "LOTA_ANDROID_SDL3_DIR (${LOTA_ANDROID_SDL3_DIR}) holds no lib/libSDL3.so; "
		"build SDL3 for Android with `rake android:deps`")
endif()

target_include_directories(lota_engine PUBLIC
	${LOTA_ANDROID_SDL3_DIR}/include
	# <ogg/...>, <vorbis/...>, <theora/...>, and <zlib.h>.
	${LOTA_ANDROID_DEPS_DIR}/include
	# OpenAL Soft's, FreeType's, and HarfBuzz's headers without a prefix, as
	# on Linux (dependencies_linux.cmake).
	${LOTA_ANDROID_DEPS_DIR}/include/AL
	${LOTA_ANDROID_DEPS_DIR}/include/freetype2
	${LOTA_ANDROID_DEPS_DIR}/include/harfbuzz
	# LÖVE includes <modplug.h> on Android, where megasource puts it
	# (src/modules/sound/lullaby/ModPlugDecoder.h:33-37), and
	# <libmodplug/modplug.h> elsewhere.
	${LOTA_ANDROID_DEPS_DIR}/include/libmodplug
)

set(LOTA_ANDROID_ARCHIVES
	${LOTA_ANDROID_DEPS_DIR}/lib/libfreetype.a
	${LOTA_ANDROID_DEPS_DIR}/lib/libharfbuzz.a
	${LOTA_ANDROID_DEPS_DIR}/lib/libmodplug.a
	${LOTA_ANDROID_DEPS_DIR}/lib/libtheoradec.a
	${LOTA_ANDROID_DEPS_DIR}/lib/libvorbisfile.a
	${LOTA_ANDROID_DEPS_DIR}/lib/libvorbis.a
	${LOTA_ANDROID_DEPS_DIR}/lib/libogg.a
	${LOTA_ANDROID_DEPS_DIR}/lib/libz.a
)
foreach(archive IN LISTS LOTA_ANDROID_ARCHIVES)
	if(NOT EXISTS ${archive})
		message(FATAL_ERROR "${archive} is missing; build LÖVE's dependencies for Android with `rake android:deps`")
	endif()
endforeach()

# The shared libraries by name, from their folders, the form in which
# Fledge finds a library to carry into the app (-L and -l, its ADR 025,
# section 2); the system's libraries LÖVE's Android build links
# (vendor/love/CMakeLists.txt:2003-2005, liblove and android: the asset
# manager, in src/common/android.cpp) and SDL's Android code logs with; and
# the C++ runtime, which Fledge reads as an extension with C++ and links
# statically (its ADR 027, section 4).
set(LOTA_ANDROID_FLAGS
	-L${LOTA_ANDROID_DEPS_DIR}/lib
	-lopenal
	-L${LOTA_ANDROID_SDL3_DIR}/lib
	-lSDL3
	-landroid
	-llog
	-lstdc++
)
target_link_libraries(lota_engine INTERFACE ${LOTA_ANDROID_ARCHIVES} ${LOTA_ANDROID_FLAGS})
list(JOIN LOTA_ANDROID_ARCHIVES "\n" archives)
list(JOIN LOTA_ANDROID_FLAGS "\n" flags)
file(WRITE ${CMAKE_BINARY_DIR}/phone_link.txt "${archives}\n${flags}\n")
