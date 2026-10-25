// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// LÖVE's error messages, passed on to Ruby with their Lua names translated
// (ADR 001, section 7: "Error messages follow the same rules").
//
// LÖVE's C++ throws love::Exception, whose message sometimes names a Lua
// module ("love.image must be loaded in order to decode an ImageData.",
// vendor/love/src/modules/image/ImageData.cpp:116) or a module function
// ("love.window.setMode cannot be called while a render target is active
// in love.graphics.", vendor/love/src/modules/window/sdl/Window.cpp:477).
// Rice turns every C++ exception into a Ruby one in cpp_protect (Rice
// 4.12.0, rice/detail/cpp_protect.hpp:20-109), after first calling the
// one handler its HandlerRegistry holds (cpp_protect.hpp:34-35). Lota
// installs translate_engine_error there, so every message from the engine
// passes through one place.

#ifndef LOTA_NATIVE_ERRORS_HPP
#define LOTA_NATIVE_ERRORS_HPP

#include "native/binding.hpp"

#include "common/Exception.h"

#include <cctype>
#include <cstddef>
#include <string>
#include <string_view>

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

// Rule 13: a camelCase name in snake_case ("readbackTexture" becomes
// "readback_texture"). An upper-case letter after a lower-case letter or a
// digit starts a new word.
inline std::string snake_case(std::string_view name) {
  std::string snake;
  snake.reserve(name.size() + 4);
  char previous = '\0';
  for (const char character : name) {
    if (is_upper(character)) {
      if (previous != '\0' && !is_upper(previous) && previous != '_') {
        snake.push_back('_');
      }
      snake.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(character))));
    } else {
      snake.push_back(character);
    }
    previous = character;
  }
  return snake;
}

} // namespace errors_detail

// +message+ with every Lua name of LÖVE's API translated by ADR 001's
// rules, and nothing else changed. A module, "love.image", becomes
// "Lota::Image" (rule 1). A module function, "love.graphics.readbackTexture",
// becomes "Lota::Graphics.readback_texture": rule 1 for the module and
// rule 13 for the function. Every module function LÖVE's compiled C++
// names in a message falls under rule 13 or, for setMode and setFullscreen,
// rule 7, which gives the same name. A name counts only where it starts a
// word, so "glove.x" is left alone, and a full stop that ends a sentence
// ("active in love.graphics.") is not taken for a function.
inline std::string translate_love_names(std::string_view message) {
  using errors_detail::char_at;
  using errors_detail::identifier_length;
  using errors_detail::is_identifier;
  using errors_detail::is_lower;
  using errors_detail::snake_case;

  constexpr std::string_view prefix = "love.";
  std::string translated;
  translated.reserve(message.size());
  std::size_t index = 0;
  while (index < message.size()) {
    const bool starts_word = index == 0 || !is_identifier(char_at(message, index - 1));
    const std::size_t module_start = index + prefix.size();
    if (!starts_word || message.substr(index, prefix.size()) != prefix ||
        !is_lower(char_at(message, module_start))) {
      translated.push_back(char_at(message, index));
      ++index;
      continue;
    }

    std::size_t module_end = module_start;
    while (is_lower(char_at(message, module_end))) {
      ++module_end;
    }
    translated.append("Lota::");
    translated.push_back(static_cast<char>(
        std::toupper(static_cast<unsigned char>(char_at(message, module_start)))));
    translated.append(message.substr(module_start + 1, module_end - module_start - 1));
    index = module_end;

    const std::size_t function_start = index + 1;
    if (char_at(message, index) == '.' &&
        std::isalpha(static_cast<unsigned char>(char_at(message, function_start))) != 0) {
      const std::size_t length = identifier_length(message, function_start);
      translated.push_back('.');
      translated.append(snake_case(message.substr(function_start, length)));
      index = function_start + length;
    }
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

// Installs translate_engine_error as this bundle's handler. Each bundle has
// its own Rice registries (cmake/LotaExtension.cmake hides them), so each
// installs it.
inline void install_error_translation() {
  Rice::detail::Registries::instance.handlers.set(&translate_engine_error);
}

} // namespace lota::native

#endif // LOTA_NATIVE_ERRORS_HPP
