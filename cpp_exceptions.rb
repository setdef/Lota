# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Approved NOLINT comments in Lota's own C++ (rake cpp:no_nolint).
# Each entry must explain WHY the suppressed clang-tidy check cannot be
# satisfied, for example:
#
#   allow "ext/lota/native.cpp", line: 12, reason: "..."
#
# Review carefully before adding new entries.

# The test-only extension reads Lota::Native's objects (a RandomGenerator,
# a Texture, a Font, an ImageData, a FileData) out of the other bundle, whose Rice
# registries it cannot see, by calling the wrapper's virtual get() with
# the object's own Ruby data type. Ruby
# declares VALUE and RTYPEDDATA_TYPE in ruby/internal/ headers, whose
# paths Ruby documents as implementation details that may move ("The name
# (path) of this header file is also an implementation detail", in
# ruby/internal/value.h and ruby/internal/core/rtypeddata.h). The public
# header, ruby.h, does not export them, so misc-include-cleaner cannot be
# satisfied without tying the build to a path Ruby says will not persist.
allow "ext/lota/native_test/native_test.cpp", line: 161,
  reason: "VALUE is declared only in ruby/internal/value.h, whose path Ruby documents as an implementation detail; " \
    "Rice passes the raw Ruby object (Arg.setValue) because it converts no Rice::Object reference."
allow "ext/lota/native_test/native_test.cpp", line: 179,
  reason: "RTYPEDDATA_TYPE returns the type as const while Rice's WrapperBase::get takes it non-const " \
    "though it only reads it (rice.hpp, Wrapper.hpp), so the const_cast cannot go; and the macro is " \
    "declared only in ruby/internal/core/rtypeddata.h, whose path Ruby documents as an implementation detail."

# The test-only extension holds a key down for the tests and the parity
# harness by writing the keyboard state SDL_GetKeyboardState returns, which
# love.keyboard.isDown reads. SDL hands that array out as const bool * and
# offers no function that sets it: a key event pushed into its queue leaves
# the state alone, and one read from macOS counts only while the window has
# keyboard focus (SDL 3.4.10, src/video/cocoa/SDL_cocoakeyboard.m,
# Cocoa_HandleKeyEvent). The array itself is SDL's own, not const
# (src/events/SDL_keyboard.c, SDL_Keyboard's keystate), so writing it
# through the cast is defined; only the cast can reach it.
allow "ext/lota/native_test/native_test.cpp", line: 350,
  reason: "SDL_GetKeyboardState returns SDL's own keystate array as const bool * and SDL has no setter; " \
    "the test-only key hold must write it, which only a const_cast can do."

# love::Variant, the value a love::event::Message carries, keeps its value
# in a union tagged by getType(), and offers no accessor but the union
# itself (vendor/love/src/common/Variant.h, Variant::Data and getData).
# LÖVE's own luax_pushvariant reads the union the same way. Reading the
# bytes some other way (memcpy) would only hide the same access from the
# check.
allow "ext/lota/native/event.cpp", lines: [64, 87],
  reason: "love::Variant exposes its value only as a union tagged by getType(); there is no other accessor."
