// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// LÖVE's error messages, passed on to Ruby with their Lua names translated
// (ADR 001, section 7: "Error messages follow the same rules").
//
// LÖVE's C++ throws love::Exception, whose message sometimes names a Lua
// module ("love.image must be loaded in order to decode an ImageData.",
// vendor/love/src/modules/image/ImageData.cpp:116) or a module function
// ("love.window.setMode cannot be called while a render target is active
// in love.graphics.", vendor/love/src/modules/window/sdl/Window.cpp:477),
// or a method ("ImageData:getPixel does not currently support the %s pixel
// format.", ImageData.cpp:549).
// Rice turns every C++ exception into a Ruby one in cpp_protect (Rice
// 4.12.0, rice/detail/cpp_protect.hpp:20-109), after first calling the
// one handler its HandlerRegistry holds (cpp_protect.hpp:34-35). Lota
// installs translate_engine_error there, so every message from the engine
// passes through one place.

#ifndef LOTA_NATIVE_ERRORS_HPP
#define LOTA_NATIVE_ERRORS_HPP

#include "native/binding.hpp"
#include "native/generated/names.hpp"

#include "common/Exception.h"

#include <algorithm>
#include <cctype>
#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

namespace lota::native {

namespace errors_detail {

// The character at +index+ in +text+, or '\0' past its end, which no test
// below accepts.
inline char char_at(std::string_view text, std::size_t index) {
  return index < text.size() ? text.at(index) : '\0';
}

inline bool is_lower(char character) {
  return std::islower(static_cast<unsigned char>(character)) != 0;
}

inline bool is_upper(char character) {
  return std::isupper(static_cast<unsigned char>(character)) != 0;
}

inline bool is_identifier(char character) {
  return std::isalnum(static_cast<unsigned char>(character)) != 0 || character == '_';
}

// The length of the identifier that starts at +start+ in +text+.
inline std::size_t identifier_length(std::string_view text, std::size_t start) {
  std::size_t end = start;
  while (is_identifier(char_at(text, end))) {
    ++end;
  }
  return end - start;
}

// The Ruby name ADR 001's rules give the LÖVE function +love_name+
// (love.window.setMode, ImageData:getPixel), from the binding generator's
// name table, or an empty view when the table has none.
inline std::string_view ruby_name(std::string_view love_name) {
  const auto *found = std::ranges::lower_bound(LOVE_NAMES, love_name, {}, &LoveName::first);
  if (found == LOVE_NAMES.end() || found->first != love_name) {
    return {};
  }
  return found->second;
}

// Rule 1: a LÖVE module's Ruby module ("image" becomes "Lota::Image").
inline std::string module_constant(std::string_view module) {
  std::string constant("Lota::");
  constant.push_back(static_cast<char>(std::toupper(static_cast<unsigned char>(module.front()))));
  constant.append(module.substr(1));
  return constant;
}

// Appends the module or module function at +start+ in +message+, in LÖVE's
// notation ("love.image", "love.window.setMode"), to +translated+ by its
// Ruby name, and returns where it ends; or returns +start+ when none
// starts there.
inline std::size_t translate_function(std::string_view message, std::size_t start,
                                      std::string &translated) {
  constexpr std::string_view prefix = "love.";
  const std::size_t module_start = start + prefix.size();
  if (message.substr(start, prefix.size()) != prefix || !is_lower(char_at(message, module_start))) {
    return start;
  }
  std::size_t module_end = module_start;
  while (is_lower(char_at(message, module_end))) {
    ++module_end;
  }
  const std::string_view module = message.substr(module_start, module_end - module_start);
  const std::size_t function_start = module_end + 1;
  if (char_at(message, module_end) != '.' ||
      std::isalpha(static_cast<unsigned char>(char_at(message, function_start))) == 0) {
    translated.append(module_constant(module));
    return module_end;
  }
  const std::size_t function_end = function_start + identifier_length(message, function_start);
  const std::string_view ruby = ruby_name(message.substr(start, function_end - start));
  if (ruby.empty()) {
    translated.append(module_constant(module));
    translated.append(message.substr(module_end, function_end - module_end));
  } else {
    translated.append(ruby);
  }
  return function_end;
}

// Appends the method at +start+ in +message+, in LÖVE's Type:method
// notation ("ImageData:getPixel"), to +translated+ by its Ruby name, or as
// LÖVE wrote it when the name table does not know it, and returns where it
// ends; or returns +start+ when no method starts there.
inline std::size_t translate_method(std::string_view message, std::size_t start,
                                    std::string &translated) {
  if (!is_upper(char_at(message, start))) {
    return start;
  }
  const std::size_t type_end = start + identifier_length(message, start);
  if (char_at(message, type_end) != ':' || !is_lower(char_at(message, type_end + 1))) {
    translated.append(message.substr(start, type_end - start));
    return type_end;
  }
  const std::size_t method_end = type_end + 1 + identifier_length(message, type_end + 1);
  const std::string_view love_name = message.substr(start, method_end - start);
  const std::string_view ruby = ruby_name(love_name);
  translated.append(ruby.empty() ? love_name : ruby);
  return method_end;
}

} // namespace errors_detail

// +message+ with every Lua name of LÖVE's API translated by ADR 001's
// rules, and nothing else changed. A module, "love.image", becomes
// "Lota::Image" (rule 1). A function, "love.graphics.readbackTexture" or
// "ImageData:getPixel", becomes the exact Ruby name the rules give it,
// "Lota::Graphics.readback_texture" or "Lota::Image::ImageData#pixel",
// looked up in the binding generator's name table (LOVE_NAMES) rather than
// respelled here. A module function the table does not know keeps its
// module's Ruby name and LÖVE's spelling after it, and a method it does not
// know stays as LÖVE wrote it. A name counts only where it starts a word,
// so "glove.x" is left alone, and a full stop that ends a sentence ("active
// in love.graphics.") is not taken for a function.
inline std::string translate_love_names(std::string_view message) {
  using errors_detail::char_at;
  using errors_detail::is_identifier;
  using errors_detail::translate_function;
  using errors_detail::translate_method;

  std::string translated;
  translated.reserve(message.size());
  std::size_t index = 0;
  while (index < message.size()) {
    const bool starts_word = index == 0 || !is_identifier(char_at(message, index - 1));
    std::size_t next = starts_word ? translate_function(message, index, translated) : index;
    if (next == index && starts_word) {
      next = translate_method(message, index, translated);
    }
    if (next == index) {
      translated.push_back(char_at(message, index));
      next = index + 1;
    }
    index = next;
  }
  return translated;
}

// Rice's exception handler (rice/detail/HandlerRegistry.hpp): it runs
// inside cpp_protect's catch block, rethrows what was caught, and turns a
// love::Exception into the RuntimeError Rice would have raised for it
// (cpp_protect.hpp:92-95), with its message translated. Every other
// exception goes on, unchanged, to Rice's own handling.
inline void translate_engine_error() {
  try {
    throw;
  } catch (const love::Exception &error) {
    const std::string message = translate_love_names(error.what());
    throw Rice::Exception(rb_eRuntimeError, "%s", message.c_str());
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

// Installs translate_engine_error as this bundle's handler. Each bundle has
// its own Rice registries (cmake/LotaExtension.cmake hides them), so each
// installs it.
inline void install_error_translation() {
  Rice::detail::Registries::instance.handlers.set(&translate_engine_error);
}

} // namespace lota::native

#endif // LOTA_NATIVE_ERRORS_HPP
