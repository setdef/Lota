# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# LotaNativeTest, a test-only extension (require "lota_native_test"). It
# binds a love::Object subclass that counts its own constructions and
# destructions, which love::Object itself does not, so the tests can prove
# the memory rule in native/binding.hpp; deliberate memory bugs, so rake
# test:native can prove the sanitizers report them; and posix_spawn, so
# that suite starts processes without forking a sanitized Ruby.
# dialogs.mm presses Return on dialogs through AppKit on macOS, for the
# parity harness and the tests of boot.lua's version warning, and
# dialogs_linux.cpp asks liblota_dialogs to on Linux.
# lota.gemspec does not package this directory, and extconf.rb builds it
# only when asked (--enable-native-test), so no installed gem contains it.
if(APPLE)
	add_library(lota_native_test MODULE native_test.cpp dialogs.mm)
else()
	add_library(lota_native_test MODULE native_test.cpp dialogs_linux.cpp selections_linux.cpp)
	# dialogs_linux.cpp gives up keyboard focus through Xlib, on the
	# display SDL opened, and selections_linux.cpp handles Xlib's errors.
	find_package(X11 REQUIRED)
	target_link_libraries(lota_native_test PRIVATE X11::X11)
endif()
lota_ruby_extension(lota_native_test lota_native_test ${CMAKE_BINARY_DIR}/lib)
if(LOTA_SANITIZE)
	target_compile_definitions(lota_native_test PRIVATE LOTA_SANITIZE)
endif()

# A shared library of the harness's own, which the harness loads into the
# reference love and into Lota before anything else, with
# DYLD_INSERT_LIBRARIES on macOS and LD_PRELOAD on Linux, written to lib/
# in the build tree.
function(lota_harness_library target)
	set_target_properties(${target} PROPERTIES
		LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib
		CXX_STANDARD 20
		CXX_STANDARD_REQUIRED ON
		CXX_EXTENSIONS OFF
		CXX_VISIBILITY_PRESET hidden
		VISIBILITY_INLINES_HIDDEN ON)
	lota_strict_warnings(${target})
endfunction()

# liblota_loopback (loopback.cpp), the parity harness's audio device
# (test/parity/parity_helper.rb). It links OpenAL Soft, whose calls it
# interposes, and finds it where the engine's libraries are found, so that
# in either process it binds the OpenAL Soft already there.
add_library(lota_loopback SHARED loopback.cpp)
lota_harness_library(lota_loopback)
# The prototypes of the extension functions it calls, alcLoopbackOpenDeviceSOFT
# and alcRenderSamplesSOFT, which OpenAL Soft exports (alext.h).
target_compile_definitions(lota_loopback PRIVATE AL_ALEXT_PROTOTYPES)
list(GET ENGINE_LIBRARY_DIRS 0 lota_loopback_libraries)
file(RELATIVE_PATH lota_loopback_relative ${CMAKE_BINARY_DIR}/lib ${lota_loopback_libraries})
if(APPLE)
	# Through the same rpath names LÖVE's frameworks are found by: love.app's
	# own Frameworks folder first, where the reference love's OpenAL Soft is,
	# and then love-apple-dependencies', where Lota's is.
	target_compile_options(lota_loopback PRIVATE -F${lota_loopback_libraries})
	target_link_options(lota_loopback PRIVATE -F${lota_loopback_libraries} "SHELL:-framework OpenAL-Soft"
		"LINKER:-rpath,@executable_path/../Frameworks"
		"LINKER:-rpath,@loader_path/${lota_loopback_relative}")
else()
	# The reference love and Lota both load the OpenAL Soft that `rake
	# dependencies` built (tasks/dependencies.rb), which the dynamic linker
	# loads once, for this library, the first it loads.
	target_include_directories(lota_loopback PRIVATE ${ENGINE_DEPS_DIR}/include)
	target_link_libraries(lota_loopback PRIVATE ${lota_loopback_libraries}/libopenal.so ${CMAKE_DL_LIBS})
	set_target_properties(lota_loopback PROPERTIES BUILD_WITH_INSTALL_RPATH ON
		INSTALL_RPATH "\$ORIGIN/${lota_loopback_relative}")

	# liblota_dialogs (answer_dialogs_linux.cpp), which answers the dialogs
	# a program shows (dialogs_linux.cpp). It links nothing of SDL's, and
	# finds SDL's own functions in whichever SDL the program loads.
	add_library(lota_dialogs SHARED answer_dialogs_linux.cpp)
	lota_harness_library(lota_dialogs)
	target_include_directories(lota_dialogs PRIVATE ${ENGINE_DEPS_DIR}/include)
	target_link_libraries(lota_dialogs PRIVATE ${CMAKE_DL_LIBS})
endif()
