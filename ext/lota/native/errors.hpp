// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// LÖVE's error messages, passed on to Ruby with their Lua names translated
// (ADR 001, section 7: "Error messages follow the same rules").
//
// LÖVE's C++ throws love::Exception, whose message sometimes names a Lua
// module, a module function, or a method ("love.image must be loaded in
// order to decode an ImageData.", vendor/love/src/modules/image/
// ImageData.cpp:116). Rice turns every C++ exception into a Ruby one in
// cpp_protect (Rice 4.12.0, rice/detail/cpp_protect.hpp:20-109), after
// first calling the one handler its HandlerRegistry holds
// (cpp_protect.hpp:34-35). Lota installs translate_engine_error there, so
// every message from the engine passes through one place, and only when
// the engine raises. The rewriting itself is Ruby's, Lota::ErrorMessage
// (lib/lota/error_message.rb), with the binding generator's name table.

#ifndef LOTA_NATIVE_ERRORS_HPP
#define LOTA_NATIVE_ERRORS_HPP

#include "native/binding.hpp"

#include "common/Exception.h"

#include <string>
#include <string_view>
#include <vector>

namespace lota::native {

namespace errors_detail {

// +message+, the engine's, as the Ruby String Rice would have raised it
// in (rb_exc_new2), translated by Lota::ErrorMessage.translate. The module
// is looked up each time rather than kept: GC.compact may move what C++
// holds without telling Ruby, and the lookup costs nothing until the
// engine raises. A module is shareable, so every Ractor finds the same one.
inline VALUE translated(std::string_view message) {
  const VALUE engine =
      Rice::detail::protect(rb_str_new, message.data(), static_cast<long>(message.size()));
  const VALUE translator = Rice::detail::protect(rb_path2class, "Lota::ErrorMessage");
  return Rice::detail::protect(rb_funcallv, translator, rb_intern("translate"), 1, &engine);
}

} // namespace errors_detail

// +message+ with every Lua name of LÖVE's API translated by ADR 001's
// rules, and nothing else changed (Lota::ErrorMessage.translate).
inline std::string translate_love_names(std::string_view message) {
  const Rice::String ruby(errors_detail::translated(message));
  return ruby.str();
}

// Rice's exception handler (rice/detail/HandlerRegistry.hpp): it runs
// inside cpp_protect's catch block, rethrows what was caught, and turns a
// love::Exception into the RuntimeError Rice would have raised for it
// (cpp_protect.hpp:92-95), with its message translated. Every other
// exception goes on, unchanged, to Rice's own handling. A Ruby error the
// translation raises leaves as a Rice::Exception, which cpp_protect
// raises once every C++ frame is gone, as it raises any other.
inline void translate_engine_error() {
  try {
    throw;
  } catch (const love::Exception &error) {
    const VALUE message = errors_detail::translated(error.what());
    throw Rice::Exception(Rice::detail::protect(rb_exc_new_str, rb_eRuntimeError, message));
  }
}

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from luax_enumerror (vendor/love/src/common/runtime.cpp:
// 1120-1137), and changed to raise Ruby's ArgumentError, which Lota raises
// for a caller's mistake where LÖVE raises a Lua error (ADR 001, rule 7).

// Raises ArgumentError for +value+, which names no +enum_name+.
[[noreturn]] inline void raise_enum_error(const char *enum_name, const std::string &value) {
  throw Rice::Exception(rb_eArgError, "Invalid %s: %s", enum_name, value.c_str());
}

// Raises ArgumentError for +value+, which names none of +values+, the
// names of +enum_name+.
[[noreturn]] inline void raise_enum_error(const char *enum_name,
                                          const std::vector<std::string> &values,
                                          const std::string &value) {
  std::string expected;
  for (const std::string &name : values) {
    expected.append(expected.empty() ? "'" : ", '").append(name).append("'");
  }
  throw Rice::Exception(rb_eArgError, "Invalid %s '%s', expected one of: %s", enum_name,
                        value.c_str(), expected.c_str());
}

// SPDX-SnippetEnd

// Raises ArgumentError with +message+, as Lota raises for a caller's
// mistake where LÖVE raises luaL_argerror (ADR 001, rule 7).
[[noreturn]] inline void raise_argument_error(const char *message) {
  throw Rice::Exception(rb_eArgError, "%s", message);
}

// Loads Lota::ErrorMessage and installs translate_engine_error as this
// bundle's handler. Each bundle has its own Rice registries
// (cmake/LotaExtension.cmake hides them), so each installs it.
inline void install_error_translation() {
  Rice::detail::protect(rb_require, "lota/error_message");
  Rice::detail::Registries::instance.handlers.set(&translate_engine_error);
}

} // namespace lota::native

#endif // LOTA_NATIVE_ERRORS_HPP
