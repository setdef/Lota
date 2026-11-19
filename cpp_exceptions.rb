# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
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
# a Texture, a Font, a Mesh, an ImageData, a FileData) out of the other bundle, whose Rice
# registries it cannot see, by calling the wrapper's virtual get() with
# the object's own Ruby data type. RTYPEDDATA_TYPE returns that type as
# const, and Rice's get() takes it as non-const though it only reads it.
allow "ext/lota/native_test/native_test.cpp", line: 231,
  reason: "RTYPEDDATA_TYPE returns the type as const while Rice's WrapperBase::get takes it non-const " \
    "though it only reads it (rice.hpp, Wrapper.hpp), so the const_cast cannot go."

# The test-only extension holds a key down for the tests and the parity
# harness by writing the keyboard state SDL_GetKeyboardState returns, which
# love.keyboard.isDown reads. SDL hands that array out as const bool * and
# offers no function that sets it: a key event pushed into its queue leaves
# the state alone, and one read from macOS counts only while the window has
# keyboard focus (SDL 3.4.10, src/video/cocoa/SDL_cocoakeyboard.m,
# Cocoa_HandleKeyEvent). The array itself is SDL's own, not const
# (src/events/SDL_keyboard.c, SDL_Keyboard's keystate), so writing it
# through the cast is defined; only the cast can reach it.
allow "ext/lota/native_test/native_test.cpp", line: 410,
  reason: "SDL_GetKeyboardState returns SDL's own keystate array as const bool * and SDL has no setter; " \
    "the test-only key hold must write it, which only a const_cast can do."

# love::Variant, the value a love::event::Message carries, keeps its value
# in a union tagged by getType(), and offers no accessor but the union
# itself (vendor/love/src/common/Variant.h, Variant::Data and getData).
# LÖVE's own luax_pushvariant reads the union the same way. Reading the
# bytes some other way (memcpy) would only hide the same access from the
# check.
allow "ext/lota/native/event.cpp", lines: [183, 222],
  reason: "love::Variant exposes its value only as a union tagged by getType(); there is no other accessor."

# love::joystick::Joystick::JoystickInput, which setGamepadMapping takes
# and getGamepadMapping returns, keeps an input's axis, button, or hat in
# an anonymous union tagged by its type, and has no accessor but the union
# itself (vendor/love/src/modules/joystick/Joystick.h:177-190). LÖVE's own
# wrap_JoystickModule.cpp and wrap_Joystick.cpp fill and read it the same
# way, in a switch on the type, as Lota's two ports do.
allow "ext/lota/native/joystick.cpp", lines: [86, 96, 112, 132, 253, 271],
  reason: "Joystick::JoystickInput exposes its axis, button, and hat only as a union tagged by its type; " \
    "there is no other accessor."

# love::graphics::Shader::UniformInfo keeps a uniform's components or
# matrix size, and the memory its values go to, in anonymous unions
# tagged by baseType, and offers no accessor but the unions themselves
# (vendor/love/src/modules/graphics/Shader.h:144-181). LÖVE's own
# wrap_Shader.cpp reads them the same way. Lota reads them in one function
# and nowhere else.
allow "ext/lota/native/shader.cpp", lines: [139, 158],
  reason: "Shader::UniformInfo exposes a uniform's size and memory only as unions tagged by baseType; " \
    "there is no other accessor."

# The parity harness's audio device (ext/lota/native_test/loopback.cpp)
# interposes alcCreateContext, which OpenAL declares as taking its
# attributes as a const ALCint * ending in a zero, with no length (alc.h).
# Finding the zero means indexing the pointer, once; the list is a
# std::span from then on.
allow "ext/lota/native_test/loopback.cpp", line: 108,
  reason: "alcCreateContext's attribute list is a zero-terminated C array with no length (alc.h), which only " \
    "pointer arithmetic can measure before it is a std::span."

# The tests' X error handler (ext/lota/native_test/selections_linux.cpp)
# has the type Xlib's XSetErrorHandler takes, XErrorHandler, whose
# parameters are a Display * and an XErrorEvent *, neither to const
# (Xlib.h). It only reads both and hands both on to the handler before
# it, through that same type, so the pointees cannot be const.
allow "ext/lota/native_test/selections_linux.cpp", line: 35,
  reason: "Xlib's XErrorHandler type fixes the handler's parameters as Display * and XErrorEvent *, not to const; " \
    "the handler passes both on to the previous XErrorHandler."

# The harness's libraries on Linux reach the definitions theirs come
# before, OpenAL Soft's alcCreateContext (loopback.cpp) and SDL's
# SDL_ShowMessageBox and SDL_ShowSimpleMessageBox
# (answer_dialogs_linux.cpp), through dlsym's RTLD_NEXT, which returns
# each as a void *. C++ converts an object pointer to a function pointer
# only through reinterpret_cast, a conversion POSIX requires to work for
# what dlsym returns (POSIX.1-2017, dlsym, "Rationale"); std::bit_cast,
# which would avoid it, bugprone-bitwise-pointer-cast forbids between
# pointers.
allow "ext/lota/native_test/loopback.cpp", line: 91,
  reason: "dlsym returns OpenAL Soft's alcCreateContext as a void *, which C++ makes a function pointer only " \
    "through reinterpret_cast; bugprone-bitwise-pointer-cast forbids std::bit_cast instead."
allow "ext/lota/native_test/answer_dialogs_linux.cpp", line: 52,
  reason: "dlsym returns SDL's message box functions as a void *, which C++ makes a function pointer only " \
    "through reinterpret_cast; bugprone-bitwise-pointer-cast forbids std::bit_cast instead."

# The harness's library that keeps its runs off the network
# (ext/lota/native_test/offline_linux.cpp and offline.mm) replaces
# getaddrinfo, whose signature the C library and POSIX fix: the name and
# the service are both const char *, side by side, and a replacement must
# take them in that order to stand in for it. On Linux it reaches the C
# library's own connect and getaddrinfo through dlsym's RTLD_NEXT, which
# returns each as a void *, as loopback.cpp and answer_dialogs_linux.cpp
# reach theirs.
allow "ext/lota/native_test/offline_linux.cpp", lines: [49, 65],
  reason: "getaddrinfo's signature is POSIX's, with the name and the service both const char * side by side; " \
    "the replacement must match it to be called in its place."
allow "ext/lota/native_test/offline.mm", line: 36,
  reason: "getaddrinfo's signature is POSIX's, with the name and the service both const char * side by side; " \
    "the replacement must match it to be called in its place."
allow "ext/lota/native_test/offline_linux.cpp", line: 34,
  reason: "dlsym returns the C library's connect and getaddrinfo as a void *, which C++ makes a function " \
    "pointer only through reinterpret_cast; bugprone-bitwise-pointer-cast forbids std::bit_cast instead."

# The tests' refusal of dialogs on Windows
# (ext/lota/native_test/dialogs_windows.cpp) writes a jump over the start
# of SDL's SDL_ShowMessageBox and SDL_ShowSimpleMessageBox, which
# GetProcAddress returns as a FARPROC, a function pointer
# (libloaderapi.h), while VirtualProtect and the copy into the code it
# unprotects take an object pointer. C++ converts a function pointer to
# an object pointer only through reinterpret_cast, which every compiler
# for Windows supports, since Windows' own APIs pass code both ways;
# std::bit_cast, which would avoid it, bugprone-bitwise-pointer-cast
# forbids between pointers.
allow "ext/lota/native_test/dialogs_windows.cpp", line: 152,
  reason: "GetProcAddress returns SDL's function as a FARPROC, whose code VirtualProtect and the copy reach only " \
    "through an object pointer, which C++ makes of it only through reinterpret_cast; " \
    "bugprone-bitwise-pointer-cast forbids std::bit_cast instead."

# Windows hands a CBT hook the window that HCBT_ACTIVATE names as the
# hook's WPARAM, an integer (CBTProc's documentation), and EnumWindows
# hands its callback the caller's pointer as an LPARAM, an integer too
# (EnumWindowsProc's). The hook and the callback take those types because
# Windows calls them with them, and C++ makes a pointer of an integer only
# through reinterpret_cast.
allow "ext/lota/native_test/dialogs_windows.cpp", lines: [222, 239],
  reason: "Windows passes a CBT hook's window as its WPARAM and EnumWindows's callback its caller's pointer as " \
    "an LPARAM, both integers, which C++ makes a pointer only through reinterpret_cast."
