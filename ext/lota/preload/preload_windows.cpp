// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Loads the DLLs Lota::Native links, each by its absolute path, from the
// libraries directory beside this extension, so that when Ruby loads
// Lota::Native, Windows finds each already loaded by its name and looks
// nowhere else for it (CMakeLists.txt beside this file says why). It
// defines nothing in Ruby; loading is all it does.

#include <ruby.h>
#include <windows.h>

#include <array>
#include <string>

namespace {

// The DLLs' names (CMakeLists.txt writes the list).
constexpr std::array libraries{
#include "libraries.inc"
};

// +text+ in UTF-8, for Ruby's messages.
std::string utf8(const std::wstring &text) {
  const int size = WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()),
                                       nullptr, 0, nullptr, nullptr);
  std::string converted(static_cast<std::size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), converted.data(),
                      size, nullptr, nullptr);
  return converted;
}

// Windows' message for the error +code+.
std::string message(DWORD code) {
  wchar_t *text = nullptr;
  const DWORD length = FormatMessageW(
      FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
      nullptr, code, 0, reinterpret_cast<wchar_t *>(&text), 0, nullptr);
  std::wstring result =
      (length == 0) ? L"error " + std::to_wstring(code) : std::wstring(text, length);
  LocalFree(text);
  while (!result.empty() && (result.back() == L'\n' || result.back() == L'\r')) {
    result.pop_back();
  }
  return utf8(result);
}

// The directory this extension was loaded from, with its separator, in
// +directory+, or why it cannot say.
std::string own_directory(std::wstring &directory) {
  HMODULE self = nullptr;
  if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                             GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                         reinterpret_cast<LPCWSTR>(&own_directory), &self) == 0) {
    return "Lota could not find its own extension: " + message(GetLastError());
  }
  std::wstring path(MAX_PATH, L'\0');
  while (true) {
    const DWORD length = GetModuleFileNameW(self, path.data(), static_cast<DWORD>(path.size()));
    if (length == 0) {
      return "Lota could not find its own extension: " + message(GetLastError());
    }
    if (length < path.size()) {
      path.resize(length);
      break;
    }
    path.resize(path.size() * 2);
  }
  directory = path.substr(0, path.find_last_of(L"\\/") + 1);
  return {};
}

// Loads each DLL, or says why one would not load.
std::string preload() {
  std::wstring directory;
  if (std::string error = own_directory(directory); !error.empty()) {
    return error;
  }
  for (const wchar_t *name : libraries) {
    const std::wstring path = directory + L"libraries\\" + name;
    // The DLL's own directory first, then the process's, for the DLLs it
    // needs in turn.
    if (LoadLibraryExW(path.c_str(), nullptr,
                       LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS) ==
        nullptr) {
      return "Lota could not load " + utf8(path) + ": " + message(GetLastError());
    }
  }
  return {};
}

// The LoadError for +error+, as a Ruby object, so no C++ object is left
// alive when Ruby raises it, which unwinds past C++ destructors.
VALUE load_error(const std::string &error) {
  return rb_exc_new_str(rb_eLoadError,
                        rb_utf8_str_new(error.data(), static_cast<long>(error.size())));
}

} // namespace

// Ruby calls this when it loads the extension (require "lota/preload"),
// the only symbol it exports (cmake/LotaExtension.cmake). Each DLL is
// loaded for good: Lota::Native needs it as long as the process runs.
extern "C" __attribute__((visibility("default"))) void Init_preload() {
  VALUE error = Qnil;
  if (const std::string reason = preload(); !reason.empty()) {
    error = load_error(reason);
  }
  if (!NIL_P(error)) {
    rb_exc_raise(error);
  }
}
