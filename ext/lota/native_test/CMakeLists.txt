# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# LotaNativeTest, a test-only extension (require "lota_native_test"). It
# binds a love::Object subclass that counts its own constructions and
# destructions, which love::Object itself does not, so the tests can prove
# the memory rule in native/binding.hpp; deliberate memory bugs, so rake
# test:native can prove the sanitizers report them; and posix_spawn, so
# that suite starts processes without forking a sanitized Ruby.
# dialogs.mm presses Return on dialogs through AppKit, for the parity
# harness and the tests of boot.lua's version warning.
# lota.gemspec does not package this directory, and extconf.rb builds it
# only when asked (--enable-native-test), so no installed gem contains it.
add_library(lota_native_test MODULE native_test.cpp dialogs.mm)
lota_ruby_extension(lota_native_test lota_native_test ${CMAKE_BINARY_DIR}/lib)
if(LOTA_SANITIZE)
	target_compile_definitions(lota_native_test PRIVATE LOTA_SANITIZE)
endif()

# liblota_loopback (loopback.cpp), the parity harness's audio device, which
# the harness loads into the reference love and into Lota with
# DYLD_INSERT_LIBRARIES (test/parity/parity_helper.rb). It links OpenAL
# Soft, whose calls it interposes, through the same rpath names LÖVE's
# frameworks are found by: love.app's own Frameworks folder first, where
# the reference love's OpenAL Soft is, and then
# love-apple-dependencies', where Lota's is, so that in either process it
# binds the OpenAL Soft already there.
add_library(lota_loopback SHARED loopback.cpp)
list(GET ENGINE_FRAMEWORK_DIRS 0 lota_loopback_frameworks)
set_target_properties(lota_loopback PROPERTIES
	LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib
	CXX_STANDARD 20
	CXX_STANDARD_REQUIRED ON
	CXX_EXTENSIONS OFF
	CXX_VISIBILITY_PRESET hidden
	VISIBILITY_INLINES_HIDDEN ON)
# The prototypes of the extension functions it calls, alcLoopbackOpenDeviceSOFT
# and alcRenderSamplesSOFT, which OpenAL Soft exports (alext.h).
target_compile_definitions(lota_loopback PRIVATE AL_ALEXT_PROTOTYPES)
target_compile_options(lota_loopback PRIVATE -F${lota_loopback_frameworks})
file(RELATIVE_PATH lota_loopback_relative ${CMAKE_BINARY_DIR}/lib ${lota_loopback_frameworks})
target_link_options(lota_loopback PRIVATE -F${lota_loopback_frameworks} "SHELL:-framework OpenAL-Soft"
	"LINKER:-rpath,@executable_path/../Frameworks"
	"LINKER:-rpath,@loader_path/${lota_loopback_relative}")
lota_strict_warnings(lota_loopback)
