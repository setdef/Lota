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
